defmodule JidoTest.Actions.ControlTest do
  use ExUnit.Case, async: true

  alias Jido.Actions.Control
  alias Jido.Agent.Directive

  describe "Cancel" do
    test "sets status to failed with cancelled error" do
      {:ok, result} = Control.Cancel.run(%{reason: :cancelled}, %{})
      assert result == %{status: :failed, error: {:cancelled, :cancelled}}
    end

    test "includes custom cancellation reason" do
      {:ok, result} = Control.Cancel.run(%{reason: :user_requested}, %{})
      assert result == %{status: :failed, error: {:cancelled, :user_requested}}
    end
  end

  describe "Noop" do
    test "returns empty state change" do
      {:ok, result} = Control.Noop.run(%{}, %{})
      assert result == %{}
    end
  end

  describe "Forward" do
    test "creates emit directive to target pid" do
      target = self()
      params = %{target_pid: target, signal_type: nil, payload: nil, source: nil}

      {:ok, result, [directive]} = Control.Forward.run(params, %{})

      assert result == %{forwarded_to: target}
      assert %Directive.Emit{} = directive
      assert {:pid, opts} = directive.dispatch
      assert Keyword.get(opts, :target) == target
    end

    test "uses custom signal type when provided" do
      target = self()
      params = %{target_pid: target, signal_type: "custom.signal", payload: nil, source: nil}

      {:ok, _result, [directive]} = Control.Forward.run(params, %{})

      assert directive.signal.type == "custom.signal"
    end

    test "uses custom payload when provided" do
      target = self()
      params = %{target_pid: target, signal_type: "test", payload: %{key: "value"}, source: nil}

      {:ok, _result, [directive]} = Control.Forward.run(params, %{})

      assert directive.signal.data == %{key: "value"}
    end

    test "returns an error for invalid target pid" do
      params = %{target_pid: "not-a-pid", signal_type: nil, payload: nil, source: nil}

      assert {:error, {:invalid_target_pid, "not-a-pid"}} = Control.Forward.run(params, %{})
    end
  end

  describe "Broadcast" do
    test "creates emit directive with pubsub dispatch" do
      params = %{
        topic: "workers",
        signal_type: "work.available",
        payload: %{},
        source: "/broadcast"
      }

      {:ok, result, [directive]} = Control.Broadcast.run(params, %{})

      assert result == %{broadcast_to: "workers"}
      assert %Directive.Emit{} = directive
      assert directive.dispatch == {:pubsub, topic: "workers"}
      assert directive.signal.type == "work.available"
    end
  end

  describe "Reply" do
    test "replies to signal with reply_to pid" do
      reply_pid = self()
      signal = %{data: %{reply_to: reply_pid}}
      params = %{signal_type: "response", payload: %{answer: 42}}

      {:ok, result, [directive]} = Control.Reply.run(params, %{signal: signal})

      assert result == %{replied_to: reply_pid}
      assert %Directive.Emit{} = directive
      assert directive.signal.type == "response"
      assert directive.signal.data == %{answer: 42}
    end

    test "returns warning when no reply_to found" do
      params = %{signal_type: "response", payload: %{}}

      {:ok, result} = Control.Reply.run(params, %{signal: %{data: %{}}})

      assert result == %{replied_to: nil, warning: "No reply_to found in signal"}
    end

    test "returns warning when no signal in context" do
      params = %{signal_type: "response", payload: %{}}

      {:ok, result} = Control.Reply.run(params, %{})

      assert result == %{replied_to: nil, warning: "No reply_to found in signal"}
    end
  end
end
