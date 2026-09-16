defmodule Jido.Plugin.OrderingTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Command
  alias Jido.Plugin.SignalContext

  defmodule Agent do
    use Jido.Agent, name: "plugin_ordering_agent"
  end

  defmodule FirstStatePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule FirstStatePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(opts) do
      key = Keyword.get(opts, :key, :first)
      {key, Zoi.integer() |> Zoi.default(0)}
    end

    @impl true
    def reduce(reduction, opts) do
      case Keyword.get(opts, :result, :ok) do
        :ok -> {:ok, reduction.plugin_state + 1}
        error -> {:error, error}
      end
    end
  end

  defmodule SecondStatePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule SecondStatePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(opts) do
      key = Keyword.get(opts, :key, :second)
      {key, Zoi.integer() |> Zoi.default(0)}
    end

    @impl true
    def reduce(reduction, opts) do
      case Keyword.get(opts, :result, :ok) do
        :ok -> {:ok, reduction.plugin_state + 1}
        error -> {:error, error}
      end
    end
  end

  defmodule SharedDirective do
    defstruct []
    def validate(%__MODULE__{} = directive), do: {:ok, directive}
  end

  defmodule FirstDirectivePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent, agent_server: __MODULE__.Server
  end

  defmodule FirstDirectivePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def directives(_opts), do: [SharedDirective]
  end

  defmodule FirstDirectivePlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def dispatch(_runtime, _directive, _context, _opts), do: :ok
  end

  defmodule SecondDirectivePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent, agent_server: __MODULE__.Server
  end

  defmodule SecondDirectivePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def directives(_opts), do: [SharedDirective]
  end

  defmodule SecondDirectivePlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def dispatch(_runtime, _directive, _context, _opts), do: :ok
  end

  defmodule FirstAdmissionPlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server
  end

  defmodule FirstAdmissionPlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def admit(runtime, _admission, _opts) do
      send(self(), {:admitted, :first, runtime})
      {:ok, :first}
    end
  end

  defmodule SecondAdmissionPlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server
  end

  defmodule SecondAdmissionPlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def admit(runtime, _admission, opts) do
      send(self(), {:admitted, :second, runtime})

      case Keyword.get(opts, :result, :ok) do
        :ok ->
          {:ok, :second}

        error ->
          {:error, error}
      end
    end
  end

  defmodule ThirdAdmissionPlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server
  end

  defmodule ThirdAdmissionPlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def admit(runtime, _admission, _opts) do
      send(self(), {:admitted, :third, runtime})
      {:ok, nil}
    end
  end

  defmodule FirstReducerFacet do
    use Jido.Agent.Plugin

    def state_spec(_opts), do: {:first_reduced, Zoi.integer() |> Zoi.default(0)}

    def reduce(%Jido.Agent.Plugin.Reduction{} = reduction, _opts),
      do: {:ok, reduction.plugin_state + 1}
  end

  defmodule FirstReducerPackage do
    use Jido.Plugin, agent: FirstReducerFacet
  end

  defmodule SecondReducerFacet do
    use Jido.Agent.Plugin

    def state_spec(_opts), do: {:second_observed, Zoi.integer() |> Zoi.default(0)}

    def reduce(%Jido.Agent.Plugin.Reduction{} = reduction, _opts) do
      send(self(), {:reduction, reduction})
      {:ok, reduction.state.first_reduced}
    end
  end

  defmodule SecondReducerPackage do
    use Jido.Plugin, agent: SecondReducerFacet
  end

  defmodule FirstOutboundPlugin do
    use Jido.Plugin, agent: __MODULE__.Agent, agent_server: __MODULE__.Server
  end

  defmodule FirstOutboundPlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(_opts), do: {:first, Zoi.atom() |> Zoi.default(:first_state)}
  end

  defmodule FirstOutboundPlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def prepare_dispatch(runtime, signal, context, _opts) do
      send(self(), {:outbound, :first, runtime, context.plugin_state})
      {:ok, append_trace(signal, :first)}
    end

    defp append_trace(signal, label) do
      %{signal | data: Map.update(signal.data, :trace, [label], &(&1 ++ [label]))}
    end
  end

  defmodule SecondOutboundPlugin do
    use Jido.Plugin, agent: __MODULE__.Agent, agent_server: __MODULE__.Server
  end

  defmodule SecondOutboundPlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(_opts), do: {:second, Zoi.atom() |> Zoi.default(:second_state)}
  end

  defmodule SecondOutboundPlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def prepare_dispatch(runtime, signal, context, _opts) do
      send(self(), {:outbound, :second, runtime, context.plugin_state})
      {:ok, append_trace(signal, :second)}
    end

    defp append_trace(signal, label) do
      %{signal | data: Map.update(signal.data, :trace, [label], &(&1 ++ [label]))}
    end
  end

  defmodule InvalidOutboundPlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server
  end

  defmodule InvalidOutboundPlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def prepare_dispatch(_runtime, signal, _context, _opts) do
      send(self(), {:outbound, :invalid})
      {:ok, %{signal | source: "not a URI reference"}}
    end
  end

  defmodule MustNotRunOutboundPlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server
  end

  defmodule MustNotRunOutboundPlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def prepare_dispatch(_runtime, signal, _context, _opts) do
      send(self(), {:outbound, :must_not_run})
      {:ok, signal}
    end
  end

  test "normalization rejects duplicate state keys and Directive owners" do
    assert {:error, state_error} =
             Jido.Plugin.Normalizer.normalize_all([
               {FirstStatePlugin, key: :shared},
               {SecondStatePlugin, key: :shared}
             ])

    assert state_error.message == "Plugin-owned Agent state keys must be unique"
    assert state_error.details.state_key == :shared

    assert {:error, directive_error} =
             Jido.Plugin.Normalizer.normalize_all([FirstDirectivePlugin, SecondDirectivePlugin])

    assert directive_error.message == "Agent Plugin Directive ownership must be unique"
    assert directive_error.details.directive == SharedDirective
  end

  test "admission runs in declaration order and stops at the first error" do
    assert {:ok, specs} =
             Jido.Plugin.Normalizer.normalize_all([
               FirstAdmissionPlugin,
               SecondAdmissionPlugin,
               ThirdAdmissionPlugin
             ])

    command = command()

    assert {:ok, admitted} =
             Jido.AgentServer.Plugin.Callbacks.admit(command, specs, %{
               FirstAdmissionPlugin => :first_runtime,
               SecondAdmissionPlugin => :second_runtime,
               ThirdAdmissionPlugin => :third_runtime
             })

    assert admitted.plugin_inputs == %{
             FirstAdmissionPlugin => %Jido.Plugin.Input{runtime: :first},
             SecondAdmissionPlugin => %Jido.Plugin.Input{runtime: :second},
             ThirdAdmissionPlugin => %Jido.Plugin.Input{runtime: nil}
           }

    assert_received {:admitted, :first, :first_runtime}
    assert_received {:admitted, :second, :second_runtime}
    assert_received {:admitted, :third, :third_runtime}

    assert {:ok, failing_specs} =
             Jido.Plugin.Normalizer.normalize_all([
               FirstAdmissionPlugin,
               {SecondAdmissionPlugin, result: :denied},
               ThirdAdmissionPlugin
             ])

    assert Jido.AgentServer.Plugin.Callbacks.admit(command, failing_specs, %{}) ==
             {:error, :denied}

    assert_received {:admitted, :first, nil}
    assert_received {:admitted, :second, nil}
    refute_received {:admitted, :third, nil}
  end

  test "outbound preparation runs in reverse order with each owned state slice" do
    assert {:ok, specs} =
             Jido.Plugin.Normalizer.normalize_all([
               FirstOutboundPlugin,
               SecondOutboundPlugin
             ])

    source = signal("plugin.order")

    context =
      struct!(SignalContext,
        turn_id: "turn-1",
        agent_id: "agent-1",
        source_signal: source,
        effective_signal: source,
        turn_context: %{},
        target: self(),
        state_version: 1,
        plugin_state: nil,
        jido: nil,
        partition: nil
      )

    assert {:ok, prepared} =
             Jido.AgentServer.Plugin.Callbacks.prepare_dispatch(
               source,
               specs,
               %{FirstOutboundPlugin => :first_runtime, SecondOutboundPlugin => :second_runtime},
               context,
               %{first: :first_state, second: :second_state}
             )

    assert prepared.data.trace == [:second, :first]
    assert_received {:outbound, :second, :second_runtime, :second_state}
    assert_received {:outbound, :first, :first_runtime, :first_state}
  end

  test "validates each outbound transform before it runs the next Plugin" do
    assert {:ok, specs} =
             Jido.Plugin.Normalizer.normalize_all([
               MustNotRunOutboundPlugin,
               InvalidOutboundPlugin
             ])

    source = signal("plugin.order")

    context =
      struct!(SignalContext,
        turn_id: "turn-1",
        agent_id: "agent-1",
        source_signal: source,
        effective_signal: source,
        turn_context: %{},
        target: self(),
        state_version: 1,
        plugin_state: nil,
        jido: nil,
        partition: nil
      )

    assert {:error, error} =
             Jido.AgentServer.Plugin.Callbacks.prepare_dispatch(source, specs, %{}, context, %{})

    assert error.details.plugin == InvalidOutboundPlugin
    assert_received {:outbound, :invalid}
    refute_received {:outbound, :must_not_run}
  end

  test "a later reducer failure does not return partially updated Plugin state" do
    assert {:ok, specs} =
             Jido.Plugin.Normalizer.normalize_all([
               FirstStatePlugin,
               {SecondStatePlugin, result: :second_failed}
             ])

    agent = %{Agent.new!() | state: %{first: 0, second: 0}}

    assert Jido.Agent.Plugin.Pipeline.run(
             {:ok, agent.state, []},
             agent,
             signal("plugin.reduce"),
             %{},
             Jido.Agent.Plugin.specs(specs)
           ) ==
             {:error, :second_failed}
  end

  test "explicit reducers form an ordered state middleware chain" do
    declarations = [FirstReducerPackage, SecondReducerPackage]
    assert {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(declarations)

    agent =
      Jido.Agent.new!(name: "ordered_reducer_agent", plugins: declarations)
      |> Jido.Agent.instantiate!()

    assert {:ok, state, []} =
             Jido.Agent.Plugin.Pipeline.run(
               {:ok, agent.state, []},
               agent,
               signal("plugin.reduce"),
               %{},
               Jido.Agent.Plugin.specs(specs)
             )

    assert state.first_reduced == 1
    assert state.second_observed == 1
    assert_received {:reduction, reduction}
    assert reduction.agent_id == agent.id
    assert reduction.agent_module == agent.module
    assert reduction.state_before == agent.state
    assert reduction.state.first_reduced == 1
    assert reduction.state_before.first_reduced == 0
  end

  defp command do
    {:ok, command} = Command.new(Agent.new!(), signal("plugin.command"))
    command
  end
end
