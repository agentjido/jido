defmodule Jido.Agent.StatelessDirectiveTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  defmodule Effect do
    @schema Zoi.struct(__MODULE__, %{kind: Zoi.enum([:reply, :block, :last])}, coerce: true)
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
    def schema, do: @schema
    def validate(%__MODULE__{} = effect), do: Zoi.parse(@schema, Map.from_struct(effect))
  end

  defmodule Effects do
    use Jido.Plugin

    @impl true
    defdelegate directives(opts), to: Jido.Agent.StatelessDirectiveTest.Effects.Agent

    @impl true
    defdelegate dispatch(runtime, directive, context, opts),
      to: Jido.Agent.StatelessDirectiveTest.Effects.Server
  end

  defmodule Effects.Agent do
    @behaviour Jido.Plugin

    @impl true
    def directives(_opts), do: [Effect]
  end

  defmodule Effects.Server do
    @behaviour Jido.Plugin

    @impl true
    def dispatch(nil, %Effect{kind: kind}, context, _opts) do
      observer = context.turn_context.observer
      send(observer, {:effect_started, kind, self()})

      case kind do
        :reply ->
          server =
            Jido.whereis_agent(context.jido, context.agent_id, partition: context.partition)

          Server.cast(server, Signal.new!("effect.result", %{value: 8}, source: "/effect"))

        :block ->
          receive do
            :release -> :ok
          end

        :last ->
          :ok
      end
    end
  end

  defmodule Submit do
    use Jido.Action,
      name: "stateless_directive_submit",
      schema: Zoi.object(%{kind: Zoi.enum([:reply, :block])})

    @impl true
    def run(%{kind: kind}, %{agent_state: state}),
      do: {:ok, %{state | value: 7}, [%Effect{kind: kind}, %Effect{kind: :last}]}
  end

  defmodule Result do
    use Jido.Action,
      name: "stateless_directive_result",
      schema: Zoi.object(%{value: Zoi.integer()})

    @impl true
    def run(%{value: value}, %{agent_state: state}), do: {:ok, %{state | value: value}}
  end

  defmodule Agent do
    use Jido.Agent, name: "stateless_directive_agent"

    agent do
      schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})

      plugin Effects
    end

    routes do
      route "effect.submit", Submit
      route "effect.result", Result
    end
  end

  test "a handler without a Plugin process sends its result through another Turn", %{jido: jido} do
    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, Agent)
    refute Map.has_key?(Server.children(server), {:plugin, Effects})

    assert {:ok, committed, _} =
             Server.call(server, signal("effect.submit", %{kind: :reply}),
               context: %{observer: self()}
             )

    assert committed.state == %{value: 7}
    assert_receive {:effect_started, :reply, worker}
    refute worker == server
    assert_receive {:effect_started, :last, _}
    eventually(fn -> Server.status(server).state_version == 2 end)
    assert Server.agent(server).state == %{value: 8}
  end
end
