defmodule JidoTest.AgentContract do
  @moduledoc false

  defmodule Return do
    use Jido.Action, name: "contract_return"

    def run(input, context) do
      if observer = context[:observer], do: send(observer, {:executed, input, context})

      case input[:mode] do
        :error -> {:error, :application_rejection}
        :raise -> raise ArgumentError, "external failure"
        _ -> {:ok, Map.get(input, :output, context.agent_state), Map.get(input, :directives, [])}
      end
    end
  end

  defmodule Add do
    use Jido.Action,
      name: "contract_add",
      schema: Zoi.object(%{amount: Zoi.integer()})

    def run(%{amount: amount}, %{agent_state: state}),
      do: {:ok, %{state | count: state.count + amount}}
  end

  defmodule Flow do
    use Jido.Flow, name: "contract_flow", schema: Zoi.object(%{amount: Zoi.integer()})

    flow do
      step "add", action: Add, params: %{amount: input(:amount)}
      output result("add")
    end
  end

  defmodule First do
    use Jido.Plugin
    def state_spec(opts), do: JidoTest.AgentContract.state_spec(opts, :first)
    def prepare(preparation, opts), do: JidoTest.AgentContract.prepare(preparation, opts)
    def reduce(reduction, opts), do: JidoTest.AgentContract.reduce(reduction, opts)
  end

  defmodule Second do
    use Jido.Plugin
    def state_spec(opts), do: JidoTest.AgentContract.state_spec(opts, :second)
    def prepare(preparation, opts), do: JidoTest.AgentContract.prepare(preparation, opts)
    def reduce(reduction, opts), do: JidoTest.AgentContract.reduce(reduction, opts)
  end

  defmodule Stateless do
    use Jido.Plugin
    def state_spec(_opts), do: :none
  end

  defmodule PreparedOnly do
    use Jido.Plugin
    def prepare(_preparation, _opts), do: {:ok, nil}
  end

  def state_spec(opts, key) do
    if opts[:stateless],
      do: :none,
      else:
        {Keyword.get(opts, :key, key),
         Zoi.integer() |> Zoi.default(Keyword.get(opts, :initial, 0))}
  end

  def prepare(preparation, opts) do
    send(self(), {:prepare, preparation})

    case opts[:prepare] do
      :reject -> {:error, :plugin_rejection}
      :invalid -> :invalid
      :nonportable -> {:ok, self()}
      :raise -> raise "prepare fault"
      _ -> {:ok, {preparation.plugin_state, preparation.signal.id}}
    end
  end

  def reduce(reduction, opts) do
    send(self(), {:reduce, reduction})

    case opts[:reduce] do
      :reject -> {:error, :reduction_rejection}
      :invalid -> :invalid
      :wrong_type -> {:ok, %{other_owner: 99}}
      :raise -> raise "reduce fault"
      _ -> {:ok, reduction.plugin_state + 1}
    end
  end

  def observe(value) do
    if observer = Process.whereis(__MODULE__.Observer), do: send(observer, {:observed, value})
    value
  end

  def schema do
    Zoi.object(%{
      count: Zoi.integer() |> Zoi.default(0),
      enabled: Zoi.boolean() |> Zoi.default(true),
      note: Zoi.string() |> Zoi.nullable() |> Zoi.default("default"),
      settings: Zoi.map() |> Zoi.default(%{a: 1, b: 2})
    })
  end

  def definition(attrs \\ []) do
    Jido.Agent.define!(
      Map.merge(
        %{
          name: "contract",
          schema: schema(),
          routes: [%{path: "test.run", handler: %{kind: :action, target: Return}}]
        },
        Map.new(attrs)
      )
    )
  end

  def contribution(provider, data \\ %{}),
    do: %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: data}

  def instance(attrs \\ []),
    do: Jido.Agent.instantiate!(definition(attrs), id: "contract-instance")

  def signal(data \\ %{}, type \\ "test.run"),
    do: Jido.Signal.new!(type, data, source: "/contract")

  def with_agent(body, callback, options \\ "") do
    module = Module.concat(__MODULE__, "Fixture#{System.unique_integer([:positive])}")

    source = """
    defmodule #{inspect(module)} do
      alias JidoTest.AgentContract, as: F, warn: false
      use Jido.Agent, name: "contract"#{options}
      #{body}
    end
    """

    JidoTest.AuthoringCompiler.with_compiled(source, fn _ -> callback.(module) end,
      modules: [module],
      timeout: 2_000
    )
  end

  def match?(%{data: data}), do: is_map(data)

  defmodule Effect do
    defstruct [:value]

    def validate(%__MODULE__{value: value} = directive) when is_integer(value) and value >= 0,
      do: {:ok, directive}

    def validate(_), do: {:error, Jido.Error.validation_error("invalid effect")}
  end

  defmodule Effects do
    use Jido.Plugin
    def state_spec(_), do: {:effects, Zoi.integer() |> Zoi.default(0)}
    def directives(_), do: [JidoTest.AgentContract.Effect]

    def reduce(reduction, _) do
      send(self(), {:effects_reduced, reduction})

      total =
        Enum.reduce(reduction.directives, reduction.plugin_state, fn
          %JidoTest.AgentContract.Effect{value: n}, acc -> acc + n
          _, acc -> acc
        end)

      {:ok, total}
    end
  end

  def changed_refinement(value, opts), do: %{opts[:ctx] | valid?: true, parsed: value + 1}

  defmodule PassiveContributor do
    use Jido.Plugin
    def admit(_, _, _), do: raise("Agent commands must not call this facet")
  end
end
