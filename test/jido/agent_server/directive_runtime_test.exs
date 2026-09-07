defmodule Jido.AgentServer.DirectiveRuntimeTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.{ChildInfo, DirectiveContext, DirectiveRuntime, ParentRef}
  alias Jido.Examples.RemoteCounter
  alias Jido.Tracing.{Context, Trace}

  setup %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, RemoteCounter)
    {:idle, state} = :sys.get_state(server)
    source = signal("runtime.source")
    context = %DirectiveContext{agent_id: state.agent.id, source_signal: source, signal: source}
    %{runtime: state, context: context, server: server}
  end

  test "direct Signal handlers preserve causation and use the selected relative target", %{
    runtime: state,
    context: context
  } do
    {_source, trace} = Context.ensure_from_signal(context.signal)
    outbound = signal("runtime.outbound")
    parent = ParentRef.new!(pid: self(), id: "parent", tag: :parent)
    state = %{state | parent: parent, children: %{child: child(self())}}

    for directive <- [
          Directive.emit(outbound),
          Directive.emit_to_parent(outbound),
          Directive.emit_to_child(:child, outbound)
        ] do
      assert {:ok, ^state} = DirectiveRuntime.handle(directive, context, state)
      assert_receive {:"$gen_cast", {:signal, _ref, delivered}}
      assert delivered.id == outbound.id
      assert Trace.get(delivered).trace_id == trace.trace_id
      assert Trace.get(delivered).causation_id == context.signal.id
    end
  end

  test "missing parents and non-Agent children fail before delivery", %{
    runtime: state,
    context: context
  } do
    outbound = signal("runtime.outbound")
    plugin_state = %{state | children: %{child: %{child(self()) | kind: :plugin}}}

    for {directive, runtime, reason} <- [
          {Directive.emit_to_parent(outbound), state, :no_parent},
          {Directive.emit_to_child(:child, outbound), state, {:child_not_found, :child}},
          {Directive.emit_to_child(:child, outbound), plugin_state, {:not_an_agent_child, :child}}
        ] do
      assert {:error, ^reason, ^runtime} = DirectiveRuntime.handle(directive, context, runtime)
      assert {:error, ^reason} = DirectiveRuntime.prepare_signal(directive, context, runtime)
      assert {:error, ^reason} = DirectiveRuntime.dispatch_prepared(directive, runtime, self())
    end

    refute_received {:"$gen_cast", _}
  end

  test "prepared relative delivery uses the current parent and child", %{runtime: state} do
    outbound = signal("runtime.outbound")
    parent = ParentRef.new!(pid: self(), id: "parent", tag: :parent)
    state = %{state | parent: parent, children: %{child: child(self())}}

    for directive <- [
          Directive.emit_to_parent(outbound),
          Directive.emit_to_child(:child, outbound)
        ] do
      assert :ok = DirectiveRuntime.dispatch_prepared(directive, state, self())
      assert_receive {:"$gen_cast", {:signal, _ref, ^outbound}}
    end
  end

  test "external dispatch reports errors, exceptions and throws without changing state", %{
    runtime: state,
    context: context
  } do
    outbound = signal("runtime.outbound")

    for {formatter, reason} <- [
          {fn _ -> raise "delivery failed" end, %RuntimeError{message: "delivery failed"}},
          {fn _ -> throw(:delivery_failed) end, {:throw, :delivery_failed}}
        ] do
      directive = Directive.emit_to_pid(outbound, self(), message_format: formatter)

      assert {:error, {:emit_dispatch_failed, ^reason}} =
               DirectiveRuntime.dispatch_prepared(directive, state, self())

      assert {:error, {:emit_dispatch_failed, ^reason}, ^state} =
               DirectiveRuntime.handle(directive, context, state)
    end

    invalid = Directive.emit(outbound, :invalid)

    assert {:error, {:emit_dispatch_failed, _}, ^state} =
             DirectiveRuntime.handle(invalid, context, state)

    valid = Directive.emit_to_pid(outbound, self())
    assert {:ok, ^state} = DirectiveRuntime.handle(valid, context, state)
    assert_receive {:signal, delivered}
    assert delivered.id == outbound.id
  end

  test "generic spawning handles OTP start results and reports start failures", %{
    runtime: state,
    context: context
  } do
    spec = {Elixir.Agent, fn -> :ready end}
    directive = Directive.spawn(spec)

    for result <- [{:ok, self()}, {:ok, self(), :info}, :ignore] do
      runtime = %{state | spawn_fun: fn ^spec -> result end}
      assert {:ok, ^runtime} = DirectiveRuntime.handle(directive, context, runtime)
    end

    runtime = %{state | spawn_fun: fn ^spec -> {:error, :unavailable} end}

    assert {:error, {:spawn_failed, :unavailable}, ^runtime} =
             DirectiveRuntime.handle(directive, context, runtime)

    assert {:ok, ^state} = DirectiveRuntime.handle(directive, context, state)

    assert Enum.any?(
             DynamicSupervisor.which_children(Jido.agent_supervisor_name(state.jido)),
             fn {_, pid, _, modules} ->
               modules == [Elixir.Agent] and Elixir.Agent.get(pid, & &1) == :ready
             end
           )
  end

  test "adoption rejects self, dead children, missing ids and occupied tags", %{
    runtime: state,
    context: context
  } do
    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}

    for {target, reason} <- [
          {self(), :cannot_adopt_self},
          {pid, {:adopt_child_failed, :child_not_alive}},
          {"missing", {:adopt_child_failed, :child_not_found}},
          {123, {:adopt_child_failed, {:invalid_child, 123}}}
        ] do
      assert {:error, ^reason, ^state} =
               DirectiveRuntime.handle(Directive.adopt_child(target, :child), context, state)
    end

    occupied = %{state | children: %{child: child(self())}}

    assert {:error, {:child_tag_in_use, :child}, ^occupied} =
             DirectiveRuntime.handle(Directive.adopt_child(self(), :child), context, occupied)

    assert {:error, {:child_tag_in_use, :child}, ^occupied} =
             DirectiveRuntime.handle(
               Directive.spawn_agent(RemoteCounter, :child),
               context,
               occupied
             )
  end

  test "adoption by id attaches the child and stopping it removes the relationship", %{
    runtime: state,
    context: context,
    jido: jido
  } do
    {:ok, server} = Jido.start_agent(jido, RemoteCounter, id: "adopted")

    assert {:ok, adopted} =
             DirectiveRuntime.handle(Directive.adopt_child("adopted", :child), context, state)

    assert adopted.children.child.pid == server
    assert {:ok, %{parent: %{pid: parent}}} = Server.creation_info(server)
    assert parent == self()
    ref = Process.monitor(server)

    assert {:ok, stopped} =
             DirectiveRuntime.handle(Directive.stop_child(:child), context, adopted)

    assert stopped.children == %{}
    assert_receive {:DOWN, ^ref, :process, ^server, _}
  end

  test "child stop keeps Plugin children and unresolved remote requests", %{
    runtime: state,
    context: context
  } do
    assert {:ok, ^state} = DirectiveRuntime.handle(Directive.stop_child(:missing), context, state)
    plugin = %{state | children: %{child: %{child(self()) | kind: :plugin}}}

    assert {:error, {:not_an_agent_child, :child}, ^plugin} =
             DirectiveRuntime.handle(Directive.stop_child(:child), context, plugin)

    directive = Directive.spawn_agent(RemoteCounter, :child, node: :remote@localhost)
    request = {1, make_ref()}

    pending = %{
      state
      | child_spawn_requests: %{child: %{directive: directive, request_id: request}}
    }

    reason = {:child_spawn_pending, :child, :remote@localhost, request}

    assert {:error, ^reason, ^pending} =
             DirectiveRuntime.handle(Directive.stop_child(:child), context, pending)

    changed = %{directive | opts: %{id: "different"}}
    assert {:error, ^reason, ^pending} = DirectiveRuntime.handle(changed, context, pending)
  end

  test "standalone child stops normalize exit reasons and remove monitor state", %{
    runtime: state,
    context: context
  } do
    for {reason, expected} <- [
          {:shutdown, :shutdown},
          {{:shutdown, :done}, {:shutdown, :done}},
          {:done, {:shutdown, :done}}
        ] do
      pid =
        spawn(fn ->
          receive do
            :finish -> :ok
          end
        end)

      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
      ref = Process.monitor(pid)
      runtime = %{state | jido: nil, children: %{child: child(pid)}}

      assert {:ok, stopped} =
               DirectiveRuntime.handle(Directive.stop_child(:child, reason), context, runtime)

      assert stopped.children == %{}
      assert_receive {:DOWN, ^ref, :process, ^pid, ^expected}
    end
  end

  test "reported errors and unsupported Directives retain the current state", %{
    runtime: state,
    context: context
  } do
    assert {:error, {:reported_error, :action, :failed}, ^state} =
             DirectiveRuntime.handle(Directive.error(:failed, :action), context, state)

    assert {:error, {:unsupported_agent_directive, :unknown}, ^state} =
             DirectiveRuntime.handle(:unknown, context, state)

    assert {:stop, :shutdown, ^state} =
             DirectiveRuntime.handle(Directive.stop(:shutdown), context, state)

    standalone = %{state | jido: nil}

    assert {:error, :jido_instance_required_for_child_agent, ^standalone} =
             DirectiveRuntime.handle(
               Directive.spawn_agent(RemoteCounter, :child),
               context,
               standalone
             )
  end

  defp child(pid),
    do:
      ChildInfo.new!(
        pid: pid,
        ref: Process.monitor(pid),
        module: RemoteCounter,
        id: "child",
        tag: :child
      )
end
