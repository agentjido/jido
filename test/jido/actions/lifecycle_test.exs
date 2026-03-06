defmodule JidoTest.Actions.LifecycleTest do
  use ExUnit.Case, async: true

  alias Jido.Actions.Lifecycle
  alias Jido.Agent.Directive
  alias Jido.AgentServer.ParentRef

  describe "NotifyParent" do
    test "creates emit directive to parent when parent exists" do
      parent_pid = self()

      agent = %{
        state: %{__parent__: %ParentRef{pid: parent_pid, id: "parent-1", tag: :child, meta: %{}}}
      }

      params = %{signal_type: "child.done", payload: %{result: 42}, source: "/child"}
      context = %{agent: agent}

      {:ok, result, directives} = Lifecycle.NotifyParent.run(params, context)

      assert result == %{notified: true}
      assert [%Directive.Emit{} = emit] = directives
      assert emit.signal.type == "child.done"
      assert emit.signal.data == %{result: 42}
      assert emit.dispatch == {:pid, [target: parent_pid]}
    end

    test "returns notified: false when no parent" do
      agent = %{state: %{}}
      params = %{signal_type: "child.done", payload: %{}, source: "/child"}
      context = %{agent: agent}

      {:ok, result, directives} = Lifecycle.NotifyParent.run(params, context)

      assert result == %{notified: false}
      assert directives == []
    end
  end

  describe "NotifyPid" do
    test "creates emit directive to specified pid" do
      target = self()

      params = %{
        target_pid: target,
        signal_type: "result.ready",
        payload: %{data: "test"},
        source: "/agent",
        delivery_mode: :async
      }

      {:ok, result, [directive]} = Lifecycle.NotifyPid.run(params, %{})

      assert result == %{sent_to: target}
      assert %Directive.Emit{} = directive
      assert directive.signal.type == "result.ready"
      assert directive.signal.data == %{data: "test"}
      assert {:pid, opts} = directive.dispatch
      assert Keyword.get(opts, :target) == target
      assert Keyword.get(opts, :delivery_mode) == :async
    end

    test "supports sync delivery mode" do
      target = self()

      params = %{
        target_pid: target,
        signal_type: "sync.request",
        payload: %{},
        source: "/agent",
        delivery_mode: :sync
      }

      {:ok, _result, [directive]} = Lifecycle.NotifyPid.run(params, %{})

      assert {:pid, opts} = directive.dispatch
      assert Keyword.get(opts, :target) == target
      assert Keyword.get(opts, :delivery_mode) == :sync
    end
  end

  describe "SpawnChild" do
    test "creates spawn_agent directive" do
      params = %{
        agent_module: SomeWorker,
        tag: :worker_1,
        initial_state: %{batch_size: 100},
        meta: %{assigned: true},
        restart: :permanent
      }

      {:ok, result, [directive]} = Lifecycle.SpawnChild.run(params, %{})

      assert result == %{spawning: :worker_1}
      assert %Directive.SpawnAgent{} = directive
      assert directive.agent == SomeWorker
      assert directive.tag == :worker_1
      assert directive.opts == %{initial_state: %{batch_size: 100}}
      assert directive.meta == %{assigned: true}
      assert directive.restart == :permanent
    end

    test "uses empty opts when no initial_state" do
      params = %{
        agent_module: SomeWorker,
        tag: :worker_2,
        initial_state: %{},
        meta: %{},
        restart: :transient
      }

      {:ok, _result, [directive]} = Lifecycle.SpawnChild.run(params, %{})

      assert directive.opts == %{}
      assert directive.restart == :transient
    end
  end

  describe "StopSelf" do
    test "creates stop directive with normal reason" do
      params = %{reason: :normal}

      {:ok, result, [directive]} = Lifecycle.StopSelf.run(params, %{})

      assert result == %{stopping: true, reason: :normal}
      assert %Directive.Stop{} = directive
      assert directive.reason == :normal
    end

    test "supports custom stop reasons" do
      params = %{reason: :work_complete}

      {:ok, result, [directive]} = Lifecycle.StopSelf.run(params, %{})

      assert result == %{stopping: true, reason: :work_complete}
      assert directive.reason == :work_complete
    end
  end

  describe "StopChild" do
    test "creates stop_child directive" do
      params = %{tag: :worker_1, reason: :normal}

      {:ok, result, [directive]} = Lifecycle.StopChild.run(params, %{})

      assert result == %{stopping_child: :worker_1, reason: :normal}
      assert %Directive.StopChild{} = directive
      assert directive.tag == :worker_1
      assert directive.reason == :normal
    end

    test "supports custom stop reasons" do
      params = %{tag: :processor, reason: :shutdown}

      {:ok, _result, [directive]} = Lifecycle.StopChild.run(params, %{})

      assert directive.reason == :shutdown
    end
  end
end
