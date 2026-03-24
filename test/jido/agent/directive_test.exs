defmodule JidoTest.Agent.DirectiveTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer.ParentRef

  describe "emit/2" do
    test "creates Emit directive without dispatch" do
      signal = %{type: "test"}
      directive = Directive.emit(signal)
      assert %Directive.Emit{signal: ^signal, dispatch: nil} = directive
    end

    test "creates Emit directive with dispatch config" do
      signal = %{type: "test"}
      directive = Directive.emit(signal, {:pubsub, topic: "events"})
      assert directive.signal == signal
      assert directive.dispatch == {:pubsub, topic: "events"}
    end
  end

  describe "error/2" do
    test "creates Error directive without context" do
      error = %{message: "test error"}
      directive = Directive.error(error)
      assert %Directive.Error{error: ^error, context: nil} = directive
    end

    test "creates Error directive with context" do
      error = %{message: "test error"}
      directive = Directive.error(error, :normalize)
      assert directive.error == error
      assert directive.context == :normalize
    end
  end

  describe "spawn/2" do
    test "creates Spawn directive without tag" do
      child_spec = {MyWorker, arg: :value}
      directive = Directive.spawn(child_spec)
      assert %Directive.Spawn{child_spec: ^child_spec, tag: nil} = directive
    end

    test "creates Spawn directive with tag" do
      child_spec = {MyWorker, arg: :value}
      directive = Directive.spawn(child_spec, :worker_1)
      assert directive.child_spec == child_spec
      assert directive.tag == :worker_1
    end
  end

  describe "spawn_agent/3" do
    test "creates SpawnAgent directive with defaults" do
      directive = Directive.spawn_agent(MyAgent, :worker_1)
      assert %Directive.SpawnAgent{} = directive
      assert directive.agent == MyAgent
      assert directive.tag == :worker_1
      assert directive.opts == %{}
      assert directive.meta == %{}
      assert directive.restart == :transient
    end

    test "creates SpawnAgent directive with opts" do
      directive =
        Directive.spawn_agent(MyAgent, :processor, opts: %{initial_state: %{batch: 100}})

      assert directive.opts == %{initial_state: %{batch: 100}}
      assert directive.meta == %{}
      assert directive.restart == :transient
    end

    test "creates SpawnAgent directive with meta" do
      directive = Directive.spawn_agent(MyAgent, :handler, meta: %{topic: "events"})
      assert directive.opts == %{}
      assert directive.meta == %{topic: "events"}
      assert directive.restart == :transient
    end

    test "creates SpawnAgent directive with both opts and meta" do
      directive =
        Directive.spawn_agent(MyAgent, :worker,
          opts: %{id: "custom"},
          meta: %{assigned: true}
        )

      assert directive.opts == %{id: "custom"}
      assert directive.meta == %{assigned: true}
      assert directive.restart == :transient
    end

    test "creates SpawnAgent directive with explicit restart policy" do
      directive = Directive.spawn_agent(MyAgent, :durable, restart: :permanent)

      assert directive.restart == :permanent
    end

    test "raises validation error for unsupported lifecycle opts" do
      assert_raise Jido.Error.ValidationError,
                   ~r/SpawnAgent does not support lifecycle\/persistence opts/,
                   fn ->
                     Directive.spawn_agent(MyAgent, :worker,
                       opts: %{storage: Jido.Storage.ETS, idle_timeout: 5_000}
                     )
                   end
    end
  end

  describe "adopt_child/3" do
    test "creates AdoptChild directive for pid" do
      directive = Directive.adopt_child(self(), :worker_1)
      assert %Directive.AdoptChild{child: child, tag: :worker_1, meta: %{}} = directive
      assert child == self()
    end

    test "creates AdoptChild directive for child id with meta" do
      directive = Directive.adopt_child("child-123", :worker_1, meta: %{restored: true})

      assert directive.child == "child-123"
      assert directive.tag == :worker_1
      assert directive.meta == %{restored: true}
    end

    test "raises validation error for unsupported child reference" do
      assert_raise Jido.Error.ValidationError, fn ->
        Directive.adopt_child(:not_a_pid_or_id, :worker_1)
      end
    end
  end

  describe "stop_child/2" do
    test "creates StopChild directive with default reason" do
      directive = Directive.stop_child(:worker_1)
      assert %Directive.StopChild{tag: :worker_1, reason: :normal} = directive
    end

    test "creates StopChild directive with custom reason" do
      directive = Directive.stop_child(:processor, :shutdown)
      assert directive.tag == :processor
      assert directive.reason == :shutdown
    end
  end

  describe "schedule/2" do
    test "creates Schedule directive" do
      directive = Directive.schedule(5000, :timeout)
      assert %Directive.Schedule{delay_ms: 5000, message: :timeout} = directive
    end

    test "creates Schedule directive with complex message" do
      directive = Directive.schedule(1000, {:check, ref: "abc123"})
      assert directive.delay_ms == 1000
      assert directive.message == {:check, ref: "abc123"}
    end
  end

  describe "stop/1" do
    test "creates Stop directive with default reason" do
      directive = Directive.stop()
      assert %Directive.Stop{reason: :normal} = directive
    end

    test "creates Stop directive with custom reason" do
      directive = Directive.stop(:shutdown)
      assert directive.reason == :shutdown
    end
  end

  describe "emit_to_pid/3" do
    test "creates Emit directive targeting a pid" do
      signal = %{type: "test"}
      pid = self()
      directive = Directive.emit_to_pid(signal, pid)
      assert %Directive.Emit{signal: ^signal, dispatch: {:pid, opts}} = directive
      assert opts[:target] == pid
    end

    test "merges extra options" do
      signal = %{type: "test"}
      pid = self()
      directive = Directive.emit_to_pid(signal, pid, delivery_mode: :sync, timeout: 10_000)
      {:pid, opts} = directive.dispatch
      assert opts[:target] == pid
      assert opts[:delivery_mode] == :sync
      assert opts[:timeout] == 10_000
    end
  end

  describe "emit_to_parent/3" do
    test "returns nil when agent has no parent" do
      agent = %{state: %{}}
      assert Directive.emit_to_parent(agent, %{type: "test"}) == nil
    end

    test "returns nil when parent ref is missing pid" do
      agent = %{state: %{__parent__: %{}}}
      assert Directive.emit_to_parent(agent, %{type: "test"}) == nil
    end

    test "returns nil when the agent is orphaned" do
      agent = %{state: %{__orphaned_from__: %{id: "former-parent"}}}
      assert Directive.emit_to_parent(agent, %{type: "test"}) == nil
    end

    test "creates Emit directive when parent is present" do
      parent_pid = self()

      parent_ref =
        ParentRef.new!(%{pid: parent_pid, id: "parent-123", tag: :child})

      agent = %{state: %{__parent__: parent_ref}}
      signal = %{type: "child.result"}

      directive = Directive.emit_to_parent(agent, signal)

      assert %Directive.Emit{signal: ^signal, dispatch: {:pid, opts}} = directive
      assert opts[:target] == parent_pid
    end

    test "passes extra options to emit_to_pid" do
      parent_pid = self()

      parent_ref =
        ParentRef.new!(%{pid: parent_pid, id: "parent-123", tag: :child})

      agent = %{state: %{__parent__: parent_ref}}

      directive = Directive.emit_to_parent(agent, %{type: "test"}, delivery_mode: :sync)

      {:pid, opts} = directive.dispatch
      assert opts[:delivery_mode] == :sync
    end
  end

  describe "cron/3" do
    test "creates Cron directive with defaults" do
      directive = Directive.cron("* * * * *", :tick)
      assert %Directive.Cron{} = directive
      assert directive.cron == "* * * * *"
      assert directive.message == :tick
      assert directive.job_id == nil
      assert directive.timezone == nil
    end

    test "creates Cron directive with job_id" do
      directive = Directive.cron("@daily", :cleanup, job_id: :daily_cleanup)
      assert directive.cron == "@daily"
      assert directive.message == :cleanup
      assert directive.job_id == :daily_cleanup
    end

    test "creates Cron directive with timezone" do
      directive = Directive.cron("0 9 * * MON", :weekly, timezone: "America/New_York")
      assert directive.timezone == "America/New_York"
    end

    test "creates Cron directive with all options" do
      directive = Directive.cron("*/5 * * * *", :check, job_id: :health, timezone: "UTC")
      assert directive.job_id == :health
      assert directive.timezone == "UTC"
    end
  end

  describe "cron_cancel/1" do
    test "creates CronCancel directive" do
      directive = Directive.cron_cancel(:heartbeat)
      assert %Directive.CronCancel{} = directive
      assert directive.job_id == :heartbeat
    end
  end

  describe "schema functions" do
    @schema_modules [
      Directive.Emit,
      Directive.Error,
      Directive.Spawn,
      Directive.SpawnAgent,
      Directive.AdoptChild,
      Directive.StopChild,
      Directive.Schedule,
      Directive.Stop,
      Directive.Cron,
      Directive.CronCancel
    ]

    for module <- @schema_modules do
      @module module
      test "#{inspect(@module)}.schema/0 returns Zoi schema" do
        schema = @module.schema()
        assert is_struct(schema)
      end
    end
  end
end
