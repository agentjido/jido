defmodule Jido.Telemetry.AgentTest do
  use ExUnit.Case, async: true

  alias Jido.Telemetry.Agent, as: AgentTelemetry

  defmodule CountingError do
    defexception [:failure, type: :timeout, retryable?: true]

    @impl true
    def message(error) do
      send(self(), :error_projected)

      case error.failure do
        :throw -> throw(:projection_failed)
        :exit -> exit(:projection_failed)
        _ -> "counted error"
      end
    end
  end

  test "result metadata projects a custom error once and uses the public timeout type" do
    assert AgentTelemetry.result_metadata({:error, %CountingError{}}) ==
             %{status: :timed_out, error_type: :timeout, retryable?: true}

    assert_received :error_projected
    refute_received :error_projected
  end

  test "message projection failure retains the structured public type" do
    for failure <- [:throw, :exit] do
      error = %CountingError{failure: failure}

      assert AgentTelemetry.result_metadata({:error, error}) ==
               %{status: :timed_out, error_type: :timeout, retryable?: true}

      assert_received :error_projected
      refute_received :error_projected
    end
  end

  test "result metadata preserves special statuses and classifies public errors" do
    for {reason, status} <- [
          {:cancelled, :cancelled},
          {{:parent_down, :cancelled}, :cancelled},
          {{:child_spawn_indeterminate, :worker, :node, :id, :timeout}, :indeterminate},
          {Jido.Error.timeout_error("expired"), :timed_out},
          {Jido.Error.validation_error("invalid"), :error},
          {:other, :error}
        ] do
      assert AgentTelemetry.result_metadata({:error, reason}) ==
               Map.put(AgentTelemetry.error_metadata(reason), :status, status)
    end

    assert AgentTelemetry.result_metadata({:ok, :value}) == %{status: :ok}
  end

  test "start emits only bounded public metadata" do
    handler = {__MODULE__, make_ref()}
    event = [:jido, :agent, :metadata_contract, :start]

    :ok =
      :telemetry.attach(
        handler,
        event,
        fn event, measurements, metadata, pid ->
          send(pid, {:telemetry, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    span =
      AgentTelemetry.start(:metadata_contract, %{
        agent_id: "agent-1",
        trace_id: String.duplicate("x", 257),
        agent_module: __MODULE__,
        status: :ok,
        committed?: true,
        partition: "partition-1",
        private: "secret",
        retryable?: :not_a_boolean
      })

    assert_receive {:telemetry, ^event,
                    %{monotonic_time: monotonic_time, system_time: system_time}, metadata}

    assert is_integer(monotonic_time)
    assert is_integer(system_time)
    assert span.metadata == metadata

    assert metadata == %{
             agent_id: "agent-1",
             agent_module: __MODULE__,
             status: :ok,
             committed?: true,
             partition: "partition-1"
           }
  end

  test "finish accepts a missing span" do
    assert AgentTelemetry.finish(nil) == :ok
  end
end
