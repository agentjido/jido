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

  defmodule Selection do
    @behaviour Jido.Agent

    def handle_signal(signal, _agent) do
      case Process.get(:contract_selection) do
        nil -> Jido.Agent.Turn.new(JidoTest.AgentContract.Return, signal.data)
        fun when is_function(fun, 1) -> fun.(signal)
        result -> result
      end
    end
  end

  defmodule Label do
    defstruct [:key, :value, :__spark_metadata__]
  end

  defmodule Labels do
    @label %Spark.Dsl.Entity{
      name: :label,
      target: Label,
      args: [:key, :value],
      schema: [key: [type: :atom, required: true], value: [type: :any, required: true]]
    }
    use Spark.Dsl.Extension,
      dsl_patches: [%Spark.Dsl.Patch.AddEntity{section_path: [:agent], entity: @label}]

    def route_target_options, do: [:ref]

    def lower_agent(config, entities) do
      JidoTest.AgentContract.observe({:lowered, __MODULE__})
      {labels, rest} = Enum.split_with(entities, &match?(%Label{}, &1))
      metadata = Enum.reduce(labels, config.metadata, &Map.put(&2, &1.key, &1.value))

      routes =
        Enum.map(config.routes, fn
          %{target: {%Jido.Agent.Extension.RouteTarget{option: :ref, value: target}, defaults}} =
              route ->
            %{route | target: {target, defaults}}

          %{target: %Jido.Agent.Extension.RouteTarget{option: :ref, value: target}} = route ->
            %{route | target: target}

          route ->
            route
        end)

      {:ok, %{config | metadata: metadata, routes: routes}, rest}
    end
  end

  defmodule BadExtension do
    use Spark.Dsl.Extension
    def lower_agent(config, entities), do: {:ok, Map.put(config, :unknown, true), entities}
  end

  defmodule Unclaimed do
    use Spark.Dsl.Extension, dsl_patches: Labels.dsl_patches()
    def lower_agent(config, entities), do: {:ok, config, entities}
  end

  defmodule InvalidExtension do
    def lower_agent(_, _), do: :invalid
  end

  defmodule RejectedExtension do
    def lower_agent(_, _), do: {:error, Jido.Error.validation_error("extension rejected")}
  end

  defmodule OrderedExtension do
    def lower_agent(config, []) do
      {:ok, %{config | metadata: Map.put(config.metadata, :seen, config.metadata[:owner])}, []}
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
    Jido.Agent.new!(
      Keyword.merge([name: "contract", schema: schema(), routes: [{"test.run", Return}]], attrs)
    )
  end

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

  defmodule StructExtension do
    def lower_agent(_, _), do: {:ok, %URI{}, []}
  end

  defmodule ImproperExtension do
    def lower_agent(config, _), do: {:ok, config, [1 | :tail]}
  end

  defmodule AtomErrorExtension do
    def lower_agent(_, _), do: {:error, :invalid_reason}
  end

  defmodule OtherOwner do
    def route_target_options, do: [:ref]
    def lower_agent(config, entities), do: {:ok, config, entities}
  end

  defmodule InvalidClaims do
    def route_target_options, do: Process.get(:agent_contract_claims, [:ref, :ref])
    def lower_agent(config, entities), do: {:ok, config, entities}
  end

  defmodule RewriteRoutes do
    use Spark.Dsl.Extension

    def lower_agent(config, entities) do
      routes =
        case config.metadata.rewrite do
          :remove -> []
          :duplicate -> config.routes ++ config.routes
          :predicate -> Enum.map(config.routes, &Map.put(&1, :match, fn _ -> true end))
        end

      {:ok, %{config | routes: routes}, entities}
    end
  end

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

  defmodule OptionNames do
    def route_target_options, do: Process.get(:contract_route_options)

    def lower_agent(config, entities),
      do: JidoTest.AgentContract.Labels.lower_agent(config, entities)
  end

  def changed_refinement(value, opts), do: %{opts[:ctx] | valid?: true, parsed: value + 1}

  defmodule BareSelection do
    defdelegate handle_signal(signal, agent), to: JidoTest.AgentContract.Selection
  end

  defmodule NoLowerExtension do
    use Spark.Dsl.Extension
  end

  defmodule PassiveContributor do
    use Jido.Plugin
    def admit(_, _, _), do: raise("Agent commands must not call this facet")
  end
end
