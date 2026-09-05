defmodule Jido.PluginTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Command
  alias Jido.Signal

  defmodule TraceAction do
    use Jido.Action, name: "agent_plugin_trace"

    @impl Jido.Action
    def run(%{trace: trace}, context) do
      {:ok, %{context.agent_state | trace: trace}}
    end
  end

  defmodule TracePlugin do
    use Jido.Plugin

    @impl true
    def prepare(%Command{} = command, opts) do
      label = Keyword.fetch!(opts, :label)

      signal = %{
        command.signal
        | data: %{command.signal.data | trace: command.signal.data.trace ++ [label]}
      }

      {:ok, %{command | signal: signal}}
    end
  end

  defmodule CallbackOnlyPlugin do
    def prepare(%Command{} = command, _opts), do: {:ok, command}
  end

  defmodule MarkerOnlyPlugin do
    def __jido_plugin__, do: :agent
    def prepare(%Command{} = command, _opts), do: {:ok, command}
  end

  defmodule RaisingMarkerPlugin do
    @behaviour Jido.Plugin

    def __jido_plugin__, do: raise("invalid marker")
    def prepare(%Command{} = command, _opts), do: {:ok, command}
  end

  defmodule SecondTracePlugin do
    use Jido.Plugin

    @impl true
    def prepare(command, opts), do: TracePlugin.prepare(command, opts)
  end

  defmodule RejectPlugin do
    use Jido.Plugin

    @impl true
    def prepare(_command, _opts), do: {:error, :rejected}
  end

  defmodule InvalidPreparePlugin do
    use Jido.Plugin

    @impl true
    def prepare(_command, _opts), do: {:ok, :not_a_command}
  end

  defmodule AdmissionPlugin do
    use Jido.Plugin

    @impl true
    def admit(_runtime, command, opts) do
      case Keyword.fetch!(opts, :mode) do
        :invalid -> {:ok, :not_a_command}
        :replace -> {:ok, %{command | agent: %{command.agent | id: "replacement"}}}
        :reject -> {:error, :denied}
      end
    end
  end

  defmodule ReplaceAgentPlugin do
    use Jido.Plugin

    @impl true
    def prepare(command, _opts) do
      {:ok, %{command | agent: %{command.agent | id: "replacement"}}}
    end
  end

  defmodule InvalidStateAction do
    use Jido.Action, name: "agent_plugin_invalid_state"

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{trace: [:invalid]}}
  end

  defmodule ReturnStop do
    use Jido.Action, name: "agent_plugin_stop_directive"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, context.agent_state, [%Jido.Agent.Directive.Stop{}]}
    end
  end

  defmodule FailingAction do
    use Jido.Action, name: "agent_plugin_failure"

    @impl Jido.Action
    def run(_params, _context), do: {:error, :action_failed}
  end

  defmodule OwnedStatePlugin do
    use Jido.Plugin

    @impl true
    def state_spec(_opts) do
      schema =
        Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
        |> Zoi.default(%{count: 0})

      {:owned, schema}
    end
  end

  defmodule NilOwnedStatePlugin do
    use Jido.Plugin

    @impl true
    def state_spec(_opts) do
      {:nil_owned, Zoi.any() |> Zoi.nullable() |> Zoi.default(nil)}
    end
  end

  defmodule OverwriteOwnedState do
    use Jido.Action, name: "agent_plugin_overwrite_owned_state"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, Map.put(context.agent_state, :owned, %{count: 10})}
    end
  end

  defmodule DeleteNilOwnedState do
    use Jido.Action, name: "agent_plugin_delete_nil_owned_state"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, Map.delete(context.agent_state, :nil_owned)}
    end
  end

  defmodule OwnedDirective do
    defstruct value: nil
  end

  defmodule ReturnOwnedDirective do
    use Jido.Action, name: "agent_plugin_owned_directive"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, context.agent_state, [%OwnedDirective{value: :original}]}
    end
  end

  defmodule ReplaceDirectiveTypePlugin do
    use Jido.Plugin

    @impl true
    def directives(_opts), do: [OwnedDirective]

    @impl true
    def validate_directive(%OwnedDirective{}, _opts) do
      {:ok, %Jido.Agent.Directive.Stop{}}
    end

    @impl true
    def dispatch(_runtime, _directive, _context, _opts), do: :ok

    def child_spec(_init) do
      Supervisor.child_spec({Elixir.Agent, fn -> nil end}, id: __MODULE__)
    end
  end

  defmodule ReducedDirective do
    defstruct []
  end

  defmodule ForeignDirective do
    defstruct []
  end

  defmodule ReturnMixedDirectives do
    use Jido.Action, name: "agent_plugin_mixed_directives"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, context.agent_state, [%ReducedDirective{}, %ForeignDirective{}]}
    end
  end

  defmodule DirectiveReducerPlugin do
    use Jido.Plugin

    @impl true
    def state_spec(_opts) do
      {:reducer, Zoi.object(%{seen: Zoi.list(Zoi.atom())}) |> Zoi.default(%{seen: []})}
    end

    @impl true
    def update_state(state, directives, _opts) do
      {:ok, %{state | seen: Enum.map(directives, & &1.__struct__)}}
    end

    @impl true
    def directives(_opts), do: [ReducedDirective]

    @impl true
    def validate_directive(%ReducedDirective{} = directive, _opts), do: {:ok, directive}
  end

  defmodule ForeignDirectivePlugin do
    use Jido.Plugin

    @impl true
    def directives(_opts), do: [ForeignDirective]

    @impl true
    def validate_directive(%ForeignDirective{} = directive, _opts), do: {:ok, directive}

    @impl true
    def dispatch(_runtime, _directive, _context, _opts), do: :ok

    def child_spec(_init) do
      Supervisor.child_spec({Elixir.Agent, fn -> nil end}, id: __MODULE__)
    end
  end

  defmodule NormalizedDirective do
    defstruct [:value]
  end

  defmodule ReturnNormalizedDirective do
    use Jido.Action, name: "agent_plugin_normalized_directive"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, context.agent_state, [%NormalizedDirective{value: "  normalized  "}]}
    end
  end

  defmodule NormalizingDirectivePlugin do
    use Jido.Plugin

    @impl true
    def state_spec(_opts) do
      {:normalized,
       Zoi.object(%{value: Zoi.string() |> Zoi.default("")}) |> Zoi.default(%{value: ""})}
    end

    @impl true
    def update_state(state, [%NormalizedDirective{value: value}], _opts) do
      {:ok, %{state | value: value}}
    end

    @impl true
    def directives(_opts), do: [NormalizedDirective]

    @impl true
    def validate_directive(%NormalizedDirective{} = directive, _opts) do
      {:ok, %{directive | value: String.trim(directive.value)}}
    end
  end

  defmodule UnhandledDirective do
    defstruct []
  end

  defmodule MissingValidationPlugin do
    use Jido.Plugin

    @impl true
    def state_spec(_opts),
      do: {:missing_validation, Zoi.integer() |> Zoi.default(0)}

    @impl true
    def update_state(state, _directives, _opts), do: {:ok, state}

    @impl true
    def directives(_opts), do: [UnhandledDirective]
  end

  defmodule UnhandledDirectivePlugin do
    use Jido.Plugin

    @impl true
    def directives(_opts), do: [UnhandledDirective]

    @impl true
    def validate_directive(%UnhandledDirective{} = directive, _opts), do: {:ok, directive}
  end

  defmodule DispatchWithoutRuntimePlugin do
    use Jido.Plugin

    @impl true
    def directives(_opts), do: [UnhandledDirective]

    @impl true
    def validate_directive(%UnhandledDirective{} = directive, _opts), do: {:ok, directive}

    @impl true
    def dispatch(_runtime, _directive, _context, _opts), do: :ok
  end

  defmodule BuiltInDirectivePlugin do
    use Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:invalid_owner, Zoi.integer() |> Zoi.default(0)}

    @impl true
    def update_state(state, _directives, _opts), do: {:ok, state}

    @impl true
    def directives(_opts), do: [Jido.Agent.Directive.Stop]

    @impl true
    def validate_directive(directive, _opts), do: {:ok, directive}
  end

  defmodule PluginAgent do
    use Jido.Agent,
      name: "plugin_agent",
      schema: Zoi.object(%{trace: Zoi.list(Zoi.string()) |> Zoi.default([])}),
      routes: [{"trace.run", TraceAction}],
      plugins: [{TracePlugin, label: "a"}, {SecondTracePlugin, label: "b"}]
  end

  defmodule RejectingAgent do
    use Jido.Agent,
      name: "rejecting_agent",
      routes: [{"trace.run", TraceAction}],
      plugins: [RejectPlugin]
  end

  defmodule InvalidPrepareAgent do
    use Jido.Agent,
      name: "invalid_prepare_agent",
      routes: [{"trace.run", TraceAction}],
      plugins: [InvalidPreparePlugin]
  end

  defmodule ReplaceAgent do
    use Jido.Agent,
      name: "replace_agent",
      routes: [{"trace.run", TraceAction}],
      plugins: [ReplaceAgentPlugin]
  end

  defmodule InvalidStateAgent do
    use Jido.Agent,
      name: "invalid_state_agent",
      schema: Zoi.object(%{trace: Zoi.list(Zoi.string()) |> Zoi.default([])}),
      routes: [{"invalid.run", InvalidStateAction}]
  end

  defmodule DirectiveAgent do
    use Jido.Agent,
      name: "directive_agent",
      routes: [{"directive.stop", ReturnStop}]
  end

  defmodule FailingAgent do
    use Jido.Agent,
      name: "failing_agent",
      routes: [{"failure.run", FailingAction}]
  end

  defmodule OwnedStateAgent do
    use Jido.Agent,
      name: "owned_state_agent",
      schema: Zoi.object(%{trace: Zoi.list(Zoi.string()) |> Zoi.default([])}),
      routes: [{"owned.overwrite", OverwriteOwnedState}],
      plugins: [OwnedStatePlugin]
  end

  defmodule NilOwnedStateAgent do
    use Jido.Agent,
      name: "nil_owned_state_agent",
      routes: [{"owned.delete_nil", DeleteNilOwnedState}],
      plugins: [NilOwnedStatePlugin]
  end

  defmodule ConflictingStateAgent do
    use Jido.Agent,
      name: "conflicting_state_agent",
      schema: Zoi.object(%{owned: Zoi.map()}),
      plugins: [OwnedStatePlugin]
  end

  defmodule ReplaceDirectiveTypeAgent do
    use Jido.Agent,
      name: "replace_directive_type_agent",
      routes: [{"directive.replace", ReturnOwnedDirective}],
      plugins: [ReplaceDirectiveTypePlugin]
  end

  defmodule DirectiveReducerAgent do
    use Jido.Agent,
      name: "directive_reducer_agent",
      routes: [{"directive.reduce", ReturnMixedDirectives}],
      plugins: [DirectiveReducerPlugin, ForeignDirectivePlugin]
  end

  defmodule NormalizingDirectiveAgent do
    use Jido.Agent,
      name: "normalizing_directive_agent",
      routes: [{"directive.normalize", ReturnNormalizedDirective}],
      plugins: [NormalizingDirectivePlugin]
  end

  test "use Jido.Plugin declares the v3 Agent Plugin contract" do
    behaviours = TracePlugin.module_info(:attributes) |> Keyword.fetch!(:behaviour)

    assert Jido.Plugin in behaviours
    assert TracePlugin.__jido_plugin__() == :agent
  end

  test "requires the use Jido.Plugin authoring boundary" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.Plugin.normalize_all([CallbackOnlyPlugin])

    assert message == "Agent Plugin must use Jido.Plugin"
  end

  test "requires validation for each declared Directive type" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.Plugin.normalize_all([MissingValidationPlugin])

    assert message == "Agent Plugin with Directives must define validate_directive/2"
  end

  test "requires each Plugin Directive to reduce state or dispatch runtime work" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.Plugin.normalize_all([UnhandledDirectivePlugin])

    assert message == "Agent Plugin Directives must update state or dispatch runtime work"
  end

  test "allows typed Directive dispatch without a Plugin process" do
    assert {:ok, [%Jido.Plugin.Spec{dispatch?: true, runtime?: false}]} =
             Jido.Plugin.normalize_all([DispatchWithoutRuntimePlugin])
  end

  test "does not let a Plugin claim a built-in Directive" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.Plugin.normalize_all([BuiltInDirectivePlugin])

    assert message == "Agent Plugin cannot own a built-in Directive"
  end

  test "does not accept a marker without the Jido.Plugin behavior" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.Plugin.normalize_all([MarkerOnlyPlugin])

    assert message == "Agent Plugin must use Jido.Plugin"
  end

  test "contains a Plugin marker fault" do
    assert {:error, %Jido.Error.ExecutionError{message: message}} =
             Jido.Plugin.normalize_all([RaisingMarkerPlugin])

    assert message == "Agent Plugin marker failed"
  end

  test "does not accept legacy Plugin module options" do
    module = "Jido.PluginOptionTest#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, ~r/use Jido.Plugin does not accept options/, fn ->
      Code.compile_string("""
      defmodule #{module} do
        use Jido.Plugin, name: "legacy"
      end
      """)
    end
  end

  test "prepares one command in declaration order" do
    agent = PluginAgent.new!()
    signal = Signal.new!("trace.run", %{trace: []}, source: "/test")

    assert PluginAgent.plugins() == [
             {TracePlugin, label: "a"},
             {SecondTracePlugin, label: "b"}
           ]

    assert agent.plugins == PluginAgent.agent().plugins
    assert Jido.Agent.definition(agent) == PluginAgent.agent()
    assert {:ok, next_agent, []} = PluginAgent.cmd(agent, signal)
    assert next_agent.state.trace == ["a", "b"]
  end

  test "can reject a command before executable work" do
    agent = RejectingAgent.new!()
    signal = Signal.new!("trace.run", %{trace: []}, source: "/test")

    assert {:error, :rejected} = RejectingAgent.cmd(agent, signal)
  end

  test "rejects an invalid prepared command" do
    agent = InvalidPrepareAgent.new!()
    signal = Signal.new!("trace.run", %{trace: []}, source: "/test")

    assert {:error, %Jido.Error.ExecutionError{}} = InvalidPrepareAgent.cmd(agent, signal)
  end

  test "admission keeps its error contract for invalid commands and Agent replacement" do
    agent = PluginAgent.new!()
    signal = Signal.new!("trace.run", %{trace: []}, source: "/test")
    assert {:ok, command} = Command.new(agent, signal)

    assert {:ok, invalid_specs} = Jido.Plugin.normalize_all([{AdmissionPlugin, mode: :invalid}])

    assert {:error, %Jido.Error.ExecutionError{} = invalid} =
             Jido.Plugin.admit(command, invalid_specs, %{})

    assert invalid.message == "Agent Plugin admit/3 returned an invalid result"
    assert invalid.details == %{plugin: AdmissionPlugin, result: {:ok, :not_a_command}}

    assert {:ok, replace_specs} = Jido.Plugin.normalize_all([{AdmissionPlugin, mode: :replace}])

    assert {:error, %Jido.Error.ExecutionError{} = replacement} =
             Jido.Plugin.admit(command, replace_specs, %{})

    assert replacement.message == "Agent Plugin cannot replace the Agent"
    assert replacement.details == %{plugin: AdmissionPlugin, callback: :admit}

    assert {:ok, reject_specs} = Jido.Plugin.normalize_all([{AdmissionPlugin, mode: :reject}])
    assert {:error, :denied} = Jido.Plugin.admit(command, reject_specs, %{})
  end

  test "does not let a Plugin replace the Agent" do
    agent = ReplaceAgent.new!()
    signal = Signal.new!("trace.run", %{trace: []}, source: "/test")

    assert {:error, %Jido.Error.ExecutionError{}} = ReplaceAgent.cmd(agent, signal)
  end

  test "validates the complete Action state" do
    agent = InvalidStateAgent.new!()
    signal = Signal.new!("invalid.run", %{}, source: "/test")

    assert {:error, %Jido.Error.ValidationError{}} = InvalidStateAgent.cmd(agent, signal)
  end

  test "validates Directives in offline Agent.cmd/3" do
    agent = DirectiveAgent.new!()
    signal = Signal.new!("directive.stop", %{}, source: "/test")

    assert {:ok, _next_agent, [%Jido.Agent.Directive.Stop{reason: :normal}]} =
             DirectiveAgent.cmd(agent, signal)
  end

  test "preserves an Action error" do
    agent = FailingAgent.new!()
    signal = Signal.new!("failure.run", %{}, source: "/test")

    assert {:error, %Jido.Action.Error.ExecutionFailureError{message: "action_failed"}} =
             FailingAgent.cmd(agent, signal)
  end

  test "does not let validation replace a Directive type" do
    agent = ReplaceDirectiveTypeAgent.new!()
    signal = Signal.new!("directive.replace", %{}, source: "/test")

    assert {:error, %Jido.Error.ExecutionError{message: message}} =
             ReplaceDirectiveTypeAgent.cmd(agent, signal)

    assert message == "Agent Plugin validate_directive/2 changed Directive type"
  end

  test "gives a Plugin state reducer only its owned Directives" do
    agent = DirectiveReducerAgent.new!()
    signal = Signal.new!("directive.reduce", %{}, source: "/test")

    assert {:ok, next_agent, [%ReducedDirective{}, %ForeignDirective{}]} =
             DirectiveReducerAgent.cmd(agent, signal)

    assert next_agent.state.reducer.seen == [ReducedDirective]
  end

  test "normalizes a Directive before Plugin state reduction" do
    agent = NormalizingDirectiveAgent.new!()
    signal = Signal.new!("directive.normalize", %{}, source: "/test")

    assert {:ok, next_agent, [%NormalizedDirective{value: "normalized"}]} =
             NormalizingDirectiveAgent.cmd(agent, signal)

    assert next_agent.state.normalized.value == "normalized"
  end

  test "adds Plugin state to the Agent schema without author schema work" do
    agent = OwnedStateAgent.new!()

    assert Keyword.keys(OwnedStateAgent.domain_schema().fields) == [:trace]
    assert Keyword.keys(OwnedStateAgent.schema().fields) == [:trace]
    assert Enum.sort(Keyword.keys(OwnedStateAgent.complete_schema().fields)) == [:owned, :trace]
    assert agent.schema == OwnedStateAgent.schema()
    assert agent.plugins == [{OwnedStatePlugin, []}]
    assert agent.state == %{owned: %{count: 0}, trace: []}
  end

  test "Agent.set/2 changes domain state but not Plugin-owned state" do
    agent = OwnedStateAgent.new!()

    assert {:ok, changed} = Jido.Agent.set(agent, %{trace: ["changed"]})
    assert changed.state == %{owned: %{count: 0}, trace: ["changed"]}

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.Agent.set(agent, %{owned: %{count: 10}})

    assert message == "Agent.set/2 accepts only domain state keys"
  end

  test "does not let an executable change Plugin-owned state" do
    agent = OwnedStateAgent.new!()
    signal = Signal.new!("owned.overwrite", %{}, source: "/test")

    assert {:error, %Jido.Error.ExecutionError{message: message}} =
             OwnedStateAgent.cmd(agent, signal)

    assert message == "Agent executable changed Plugin-owned state"
  end

  test "treats a missing Plugin key and a nil Plugin value as different state" do
    agent = NilOwnedStateAgent.new!()
    signal = Signal.new!("owned.delete_nil", %{}, source: "/test")

    assert agent.state == %{nil_owned: nil}

    assert {:error, %Jido.Error.ExecutionError{message: message}} =
             NilOwnedStateAgent.cmd(agent, signal)

    assert message == "Agent executable changed Plugin-owned state"
  end

  test "rejects unknown state keys and domain state key conflicts" do
    assert {:error, %Jido.Error.ValidationError{}} =
             OwnedStateAgent.new(state: %{owned: %{count: 0}, trace: [], extra: true})

    assert_raise Jido.Error.ValidationError, fn -> ConflictingStateAgent.new!() end
  end
end
