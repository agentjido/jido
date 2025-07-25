defmodule Jido.Sensors.HeartbeatTest do
  use JidoTest.Case, async: true
  alias Jido.Sensors.Heartbeat

  @moduletag :capture_log

  describe "Heartbeat" do
    test "initializes with correct default values" do
      opts = [
        id: "test_heartbeat",
        target: {:pid, target: self()}
      ]

      {:ok, pid} = Heartbeat.start_link(opts)
      state = :sys.get_state(pid)

      assert state.config.interval == 5000
      assert state.config.message == "heartbeat"
      assert %DateTime{} = state.last_beat
    end

    test "initializes with custom config" do
      opts = [
        id: "test_heartbeat",
        target: {:pid, target: self()},
        interval: 1000,
        message: "custom heartbeat"
      ]

      {:ok, pid} = Heartbeat.start_link(opts)
      state = :sys.get_state(pid)

      assert state.config.interval == 1000
      assert state.config.message == "custom heartbeat"
    end

    test "emits heartbeat signals at specified interval" do
      opts = [
        id: "test_heartbeat",
        target: {:pid, target: self()},
        interval: 100,
        message: "test heartbeat"
      ]

      {:ok, _pid} = Heartbeat.start_link(opts)

      # Wait for and verify two heartbeats
      assert_receive {:signal, signal}, 200
      assert signal.type == "heartbeat"
      assert signal.data.message == "test heartbeat"

      assert_receive {:signal, signal}, 200
      assert signal.type == "heartbeat"
      assert signal.data.message == "test heartbeat"
    end

    test "includes correct data in heartbeat signal" do
      opts = [
        id: "test_heartbeat",
        target: {:pid, target: self()},
        interval: 100,
        message: "test heartbeat"
      ]

      {:ok, _pid} = Heartbeat.start_link(opts)

      assert_receive {:signal, signal}, 200

      assert signal.type == "heartbeat"
      assert signal.source =~ "heartbeat_sensor:"

      assert %{
               message: "test heartbeat",
               timestamp: %DateTime{},
               last_beat: %DateTime{}
             } = signal.data
    end
  end
end
