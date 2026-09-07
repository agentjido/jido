defmodule Jido.AgentServer.CreationCauseTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer.CreationCause
  alias Jido.Signal

  test "metadata returns an empty map for a malformed trace cause" do
    cause = %CreationCause{
      trace_id: "",
      span_id: "span-id",
      signal_id: "signal-id",
      turn_id: "turn-id"
    }

    assert CreationCause.metadata(cause) == %{}
  end

  test "put returns the original signal for a malformed trace cause" do
    signal = Signal.new!("test.creation_cause", %{}, source: "/test")

    cause = %CreationCause{
      trace_id: "trace-id",
      span_id: "",
      signal_id: "signal-id",
      turn_id: "turn-id"
    }

    assert CreationCause.put(signal, cause) == signal
  end
end
