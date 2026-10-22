defmodule JidoTest.Contract.PluginHeartbeatTest do
  use Covenant.Case, component: "jido.plugin.heartbeat", async: true

  alias Jido.Plugin.Heartbeat
  alias Jido.Plugin.Heartbeat.Runtime
  alias Jido.Plugin.Heartbeat.Signal.Tick
  alias Jido.Plugin.Init
  alias Jido.Plugin.Normalizer

  defp init(options) do
    %Init{
      agent_server: self(),
      agent_id: "heartbeat-contract",
      module: Heartbeat,
      options: options
    }
  end

  defp receive_tick(timeout \\ 500) do
    assert_receive {:"$gen_cast", {:turn, _token, %Jido.Signal{} = signal, %{}, :infinity}},
                   timeout

    signal
  end

  @tag obligation: "jido.plugin.heartbeat.I1"
  test "configuration applies defaults and accepts all custom values" do
    assert %{
             option_keys: %{
               agent_server: [:interval, :signal_type, :signal_data, :source]
             }
           } = Heartbeat.__jido_plugin__()

    assert Heartbeat.sections() == []

    assert {:ok,
            %{
              interval: 5_000,
              signal_type: "jido.agent.heartbeat",
              signal_data: %{},
              source: "/plugin/heartbeat"
            }} = Heartbeat.configuration([])

    options = [
      interval: 1,
      signal_type: "system.heartbeat",
      signal_data: %{source: :clock},
      source: "urn:jido:clock"
    ]

    assert {:ok,
            %{
              interval: 1,
              signal_type: "system.heartbeat",
              signal_data: %{source: :clock},
              source: "urn:jido:clock"
            }} = Heartbeat.configuration(options)

    assert :ok = Heartbeat.validate_options(options)
    assert {:ok, [_spec]} = Normalizer.normalize_all([{Heartbeat, options}])
  end

  @tag obligation: "jido.plugin.heartbeat.I2"
  test "configuration and runtime startup reject each invalid option" do
    invalid_cases = [
      {[interval: 0], {:invalid_heartbeat_interval, 0}},
      {[interval: -1], {:invalid_heartbeat_interval, -1}},
      {[interval: 1.0], {:invalid_heartbeat_interval, 1.0}},
      {[signal_type: ""], {:invalid_heartbeat_signal_type, ""}},
      {[signal_type: 42], {:invalid_heartbeat_signal_type, 42}},
      {[signal_type: <<255>>], {:invalid_heartbeat_signal_type, <<255>>}},
      {[signal_data: []], {:invalid_heartbeat_signal_data, []}},
      {[signal_data: %URI{}], {:invalid_heartbeat_signal_data, %URI{}}},
      {[source: ""], {:invalid_heartbeat_source, ""}},
      {[source: 42], {:invalid_heartbeat_source, 42}},
      {[source: "not a URI reference"], {:invalid_heartbeat_source, "not a URI reference"}},
      {%{}, {:invalid_heartbeat_options, %{}}}
    ]

    for {options, reason} <- invalid_cases do
      assert {:error, ^reason} = Heartbeat.configuration(options)

      assert {:error,
              %Jido.Error.ValidationError{
                message: "Heartbeat Plugin options are invalid",
                details: %{reason: ^reason}
              }} = Heartbeat.validate_options(options)

      assert {:error, ^reason} = Runtime.start_link(init(options))
    end

    for options <- [[unknown: true], [interval: 1, interval: 2]] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Normalizer.normalize_all([{Heartbeat, options}])
    end
  end

  @tag obligation: "jido.plugin.heartbeat.I3"
  test "the Plugin declares and starts one linked runtime child" do
    init = init(interval: 60_000)
    spec = Heartbeat.child_spec(init)

    assert spec.id == Heartbeat
    assert spec.start == {Runtime, :start_link, [init]}

    assert {:ok, runtime} = Runtime.start_link(init)
    assert is_pid(runtime)
    assert runtime in elem(Process.info(self(), :links), 1)
    assert :ok = GenServer.stop(runtime)
  end

  @tag obligation: "jido.plugin.heartbeat.I4"
  test "automatic default ticks keep data and source and use fresh IDs" do
    data = %{source: :clock, count: 1}

    start_supervised!(
      {Runtime, init(interval: 10, signal_data: data, source: "/contract/heartbeat")}
    )

    first = receive_tick()
    second = receive_tick()

    assert %Jido.Signal{
             type: "jido.agent.heartbeat",
             source: "/contract/heartbeat",
             data: ^data
           } = first

    assert second.type == Tick.type()
    assert second.source == "/contract/heartbeat"
    assert second.data == data
    refute second.id == first.id
  end

  @tag obligation: "jido.plugin.heartbeat.I5"
  test "custom ticks keep type, data, and source and use fresh IDs" do
    data = %{source: :clock}

    runtime =
      start_supervised!(
        {Runtime,
         init(
           interval: 60_000,
           signal_type: "system.heartbeat",
           signal_data: data,
           source: "urn:jido:clock"
         )}
      )

    send(runtime, :tick)
    first = receive_tick()
    send(runtime, :tick)
    second = receive_tick()

    assert %Jido.Signal{
             type: "system.heartbeat",
             source: "urn:jido:clock",
             data: ^data
           } = first

    assert second.type == "system.heartbeat"
    assert second.source == "urn:jido:clock"
    assert second.data == data
    refute second.id == first.id
  end
end
