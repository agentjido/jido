defmodule Jido.Plugin.OrderingTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Command
  alias Jido.Plugin
  alias Jido.Plugin.SignalContext

  defmodule Agent do
    use Jido.Agent, name: "plugin_ordering_agent"
  end

  defmodule FirstStatePlugin do
    use Jido.Plugin

    @impl true
    def state_spec(opts) do
      key = Keyword.get(opts, :key, :first)
      {key, Zoi.integer() |> Zoi.default(0)}
    end

    @impl true
    def update_state(state, _directives, opts) do
      case Keyword.get(opts, :result, :ok) do
        :ok -> {:ok, state + 1}
        error -> {:error, error}
      end
    end
  end

  defmodule SecondStatePlugin do
    use Jido.Plugin

    @impl true
    def state_spec(opts) do
      key = Keyword.get(opts, :key, :second)
      {key, Zoi.integer() |> Zoi.default(0)}
    end

    @impl true
    def update_state(state, _directives, opts) do
      case Keyword.get(opts, :result, :ok) do
        :ok -> {:ok, state + 1}
        error -> {:error, error}
      end
    end
  end

  defmodule SharedDirective do
    defstruct []
  end

  defmodule FirstDirectivePlugin do
    use Jido.Plugin

    @impl true
    def directives(_opts), do: [SharedDirective]

    @impl true
    def validate_directive(%SharedDirective{} = directive, _opts), do: {:ok, directive}

    @impl true
    def dispatch(_runtime, _directive, _context, _opts), do: :ok
  end

  defmodule SecondDirectivePlugin do
    use Jido.Plugin

    @impl true
    def directives(_opts), do: [SharedDirective]

    @impl true
    def validate_directive(%SharedDirective{} = directive, _opts), do: {:ok, directive}

    @impl true
    def dispatch(_runtime, _directive, _context, _opts), do: :ok
  end

  defmodule FirstAdmissionPlugin do
    use Jido.Plugin

    @impl true
    def admit(runtime, command, opts) do
      send(opts[:observer], {:admitted, :first, runtime})

      {:ok,
       %{command | context: Map.update(command.context, :order, [:first], &(&1 ++ [:first]))}}
    end
  end

  defmodule SecondAdmissionPlugin do
    use Jido.Plugin

    @impl true
    def admit(runtime, command, opts) do
      send(opts[:observer], {:admitted, :second, runtime})

      case Keyword.get(opts, :result, :ok) do
        :ok ->
          {:ok,
           %{
             command
             | context: Map.update(command.context, :order, [:second], &(&1 ++ [:second]))
           }}

        error ->
          {:error, error}
      end
    end
  end

  defmodule ThirdAdmissionPlugin do
    use Jido.Plugin

    @impl true
    def admit(runtime, command, opts) do
      send(opts[:observer], {:admitted, :third, runtime})
      {:ok, command}
    end
  end

  defmodule FirstOutboundPlugin do
    use Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:first, Zoi.atom() |> Zoi.default(:first_state)}

    @impl true
    def update_state(state, _directives, _opts), do: {:ok, state}

    @impl true
    def prepare_dispatch(runtime, signal, context, opts) do
      send(opts[:observer], {:outbound, :first, runtime, context.plugin_state})
      {:ok, append_trace(signal, :first)}
    end

    defp append_trace(signal, label) do
      %{signal | data: Map.update(signal.data, :trace, [label], &(&1 ++ [label]))}
    end
  end

  defmodule SecondOutboundPlugin do
    use Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:second, Zoi.atom() |> Zoi.default(:second_state)}

    @impl true
    def update_state(state, _directives, _opts), do: {:ok, state}

    @impl true
    def prepare_dispatch(runtime, signal, context, opts) do
      send(opts[:observer], {:outbound, :second, runtime, context.plugin_state})
      {:ok, append_trace(signal, :second)}
    end

    defp append_trace(signal, label) do
      %{signal | data: Map.update(signal.data, :trace, [label], &(&1 ++ [label]))}
    end
  end

  defmodule InvalidOutboundPlugin do
    use Jido.Plugin

    @impl true
    def prepare_dispatch(_runtime, signal, _context, opts) do
      send(opts[:observer], {:outbound, :invalid})
      {:ok, %{signal | source: "not a URI reference"}}
    end
  end

  defmodule MustNotRunOutboundPlugin do
    use Jido.Plugin

    @impl true
    def prepare_dispatch(_runtime, signal, _context, opts) do
      send(opts[:observer], {:outbound, :must_not_run})
      {:ok, signal}
    end
  end

  test "normalization rejects duplicate state keys and Directive owners" do
    assert {:error, state_error} =
             Plugin.normalize_all([
               {FirstStatePlugin, key: :shared},
               {SecondStatePlugin, key: :shared}
             ])

    assert state_error.message == "Agent Plugin state keys must be unique"
    assert state_error.details.state_key == :shared

    assert {:error, directive_error} =
             Plugin.normalize_all([FirstDirectivePlugin, SecondDirectivePlugin])

    assert directive_error.message == "Agent Plugin Directive ownership must be unique"
    assert directive_error.details.directive == SharedDirective
  end

  test "admission runs in declaration order and stops at the first error" do
    observer = self()

    assert {:ok, specs} =
             Plugin.normalize_all([
               {FirstAdmissionPlugin, observer: observer},
               {SecondAdmissionPlugin, observer: observer},
               {ThirdAdmissionPlugin, observer: observer}
             ])

    command = command()

    assert {:ok, admitted} =
             Plugin.admit(command, specs, %{
               FirstAdmissionPlugin => :first_runtime,
               SecondAdmissionPlugin => :second_runtime,
               ThirdAdmissionPlugin => :third_runtime
             })

    assert admitted.context.order == [:first, :second]
    assert_received {:admitted, :first, :first_runtime}
    assert_received {:admitted, :second, :second_runtime}
    assert_received {:admitted, :third, :third_runtime}

    assert {:ok, failing_specs} =
             Plugin.normalize_all([
               {FirstAdmissionPlugin, observer: observer},
               {SecondAdmissionPlugin, observer: observer, result: :denied},
               {ThirdAdmissionPlugin, observer: observer}
             ])

    assert Plugin.admit(command, failing_specs, %{}) == {:error, :denied}
    assert_received {:admitted, :first, nil}
    assert_received {:admitted, :second, nil}
    refute_received {:admitted, :third, nil}
  end

  test "outbound preparation runs in reverse order with each owned state slice" do
    observer = self()

    assert {:ok, specs} =
             Plugin.normalize_all([
               {FirstOutboundPlugin, observer: observer},
               {SecondOutboundPlugin, observer: observer}
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
             Plugin.prepare_dispatch(
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
    observer = self()

    assert {:ok, specs} =
             Plugin.normalize_all([
               {MustNotRunOutboundPlugin, observer: observer},
               {InvalidOutboundPlugin, observer: observer}
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

    assert {:error, error} = Plugin.prepare_dispatch(source, specs, %{}, context, %{})
    assert error.details.plugin == InvalidOutboundPlugin
    assert_received {:outbound, :invalid}
    refute_received {:outbound, :must_not_run}
  end

  test "a later reducer failure does not return partially updated Plugin state" do
    assert {:ok, specs} =
             Plugin.normalize_all([
               FirstStatePlugin,
               {SecondStatePlugin, result: :second_failed}
             ])

    assert Plugin.update_state({:ok, %{first: 0, second: 0}, []}, specs) ==
             {:error, :second_failed}
  end

  defp command do
    {:ok, command} = Command.new(Agent.new!(), signal("plugin.command"))
    command
  end
end
