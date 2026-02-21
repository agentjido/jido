defmodule Jido.Actions.Control do
  @moduledoc """
  Base actions for control flow and signal handling.

  These actions provide common patterns for:
  - Cancellation handling
  - Signal forwarding
  - No-op acknowledgment

  ## Usage

      use Jido.Agent,
        name: "my_agent",
        signal_routes: [
          {"jido.agent.cancel", Jido.Actions.Control.Cancel},
          {"proxy.forward", Jido.Actions.Control.Forward}
        ]
  """

  alias Jido.Agent.Directive
  alias Jido.Signal

  defmodule Cancel do
    @moduledoc """
    Handle cancellation requests.

    Sets the agent status to `:failed` with a cancellation error.
    This is the standard handler for the `jido.agent.cancel` signal.

    ## Schema

    - `reason` - Cancellation reason (default: :cancelled)

    ## Example

        # Standard cancellation route
        {"jido.agent.cancel", Jido.Actions.Control.Cancel}
    """
    use Jido.Action,
      name: "cancel",
      description: "Handle cancellation requests",
      schema: [
        reason: [type: :any, default: :cancelled, doc: "Cancellation reason"]
      ]

    def run(%{reason: reason}, _context) do
      {:ok, %{status: :failed, error: {:cancelled, reason}}}
    end
  end

  defmodule Noop do
    @moduledoc """
    No-operation action that acknowledges a signal without changes.

    Useful for:
    - Explicitly handling signals that need no action
    - Testing and debugging signal routing
    - Placeholder routes during development

    ## Example

        # Acknowledge but ignore certain signals
        {"system.ping", Jido.Actions.Control.Noop}
    """
    use Jido.Action,
      name: "noop",
      description: "No-operation, acknowledges signal without changes",
      schema: []

    def run(_params, _context) do
      {:ok, %{}}
    end
  end

  defmodule Forward do
    @moduledoc """
    Forward a signal to another agent.

    Re-emits the current signal (or a transformed version) to a target process.

    ## Schema

    - `target_pid` - PID to forward signal to (required)
    - `signal_type` - Optional new signal type (uses original if nil)
    - `payload` - Optional new payload (uses original if nil)
    - `source` - Optional new source (appends "/forwarded" if nil)

    ## Example

        # Forward to a worker pool
        {Jido.Actions.Control.Forward, %{target_pid: worker_pid}}

        # Transform and forward
        {Jido.Actions.Control.Forward, %{
          target_pid: processor_pid,
          signal_type: "process.request"
        }}
    """
    use Jido.Action,
      name: "forward",
      description: "Forward a signal to another agent",
      schema: [
        target_pid: [type: :any, required: true, doc: "Target process PID"],
        signal_type: [type: :string, default: nil, doc: "New signal type (optional)"],
        payload: [type: :map, default: nil, doc: "New payload (optional)"],
        source: [type: :string, default: nil, doc: "New source (optional)"]
      ]

    def run(%{target_pid: pid, signal_type: type, payload: payload, source: source}, context) do
      original = context[:signal]

      final_type = resolve_type(type, original)
      final_payload = resolve_payload(payload, original)
      final_source = resolve_source(source, original)

      signal = Signal.new!(final_type, final_payload, source: final_source)
      directive = Directive.emit_to_pid(signal, pid)
      {:ok, %{forwarded_to: pid}, [directive]}
    end

    defp resolve_type(type, _original) when is_binary(type), do: type
    defp resolve_type(nil, %{type: type}) when is_binary(type), do: type
    defp resolve_type(nil, _original), do: "forwarded"

    defp resolve_payload(payload, _original) when is_map(payload), do: payload
    defp resolve_payload(nil, %{data: data}) when is_map(data), do: data
    defp resolve_payload(nil, _original), do: %{}

    defp resolve_source(source, _original) when is_binary(source), do: source

    defp resolve_source(nil, %{source: original_source}) when is_binary(original_source),
      do: original_source <> "/forwarded"

    defp resolve_source(nil, _original), do: "/forwarded"
  end

  defmodule Broadcast do
    @moduledoc """
    Broadcast a signal to multiple targets via PubSub.

    ## Schema

    - `topic` - PubSub topic to broadcast to (required)
    - `signal_type` - Signal type to broadcast (required)
    - `payload` - Signal payload data (default: %{})
    - `source` - Signal source path (default: "/broadcast")

    ## Example

        {Jido.Actions.Control.Broadcast, %{
          topic: "workers",
          signal_type: "work.available",
          payload: %{task_id: "123"}
        }}
    """
    use Jido.Action,
      name: "broadcast",
      description: "Broadcast a signal via PubSub",
      schema: [
        topic: [type: :string, required: true, doc: "PubSub topic"],
        signal_type: [type: :string, required: true, doc: "Signal type to broadcast"],
        payload: [type: :map, default: %{}, doc: "Signal payload"],
        source: [type: :string, default: "/broadcast", doc: "Signal source"]
      ]

    def run(%{topic: topic, signal_type: type, payload: payload, source: source}, _context) do
      signal = Signal.new!(type, payload, source: source)
      directive = Directive.emit(signal, {:pubsub, topic: topic})
      {:ok, %{broadcast_to: topic}, [directive]}
    end
  end

  defmodule Reply do
    @moduledoc """
    Reply to the source of the current signal.

    Extracts the source PID from the incoming signal and sends a reply.
    Requires the original signal to have a `reply_to` field in its data
    or a parseable source containing a PID reference.

    ## Schema

    - `signal_type` - Reply signal type (required)
    - `payload` - Reply payload data (default: %{})

    ## Example

        # Handle a request and reply
        use Jido.Agent,
          name: "query_agent",
          signal_routes: [{"query.request", MyQueryHandler}]

        # In handler, use Reply action
        {Jido.Actions.Control.Reply, %{
          signal_type: "query.response",
          payload: %{result: data}
        }}
    """
    use Jido.Action,
      name: "reply",
      description: "Reply to the signal source",
      schema: [
        signal_type: [type: :string, required: true, doc: "Reply signal type"],
        payload: [type: :map, default: %{}, doc: "Reply payload"]
      ]

    def run(%{signal_type: type, payload: payload}, context) do
      case extract_reply_to(context[:signal]) do
        {:ok, pid} ->
          signal = Signal.new!(type, payload, source: "/reply")
          directive = Directive.emit_to_pid(signal, pid)
          {:ok, %{replied_to: pid}, [directive]}

        :error ->
          {:ok, %{replied_to: nil, warning: "No reply_to found in signal"}}
      end
    end

    defp extract_reply_to(nil), do: :error

    defp extract_reply_to(%{data: %{reply_to: pid}}) when is_pid(pid), do: {:ok, pid}

    defp extract_reply_to(_), do: :error
  end
end
