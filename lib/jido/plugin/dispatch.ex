defmodule Jido.Plugin.Dispatch do
  @moduledoc """
  Delivers Signals through `Jido.Signal.Dispatch` after an Agent commit.

  The Agent Server waits for the real adapter result without blocking its OTP
  mailbox. A delivery error becomes a post-commit Directive failure.

  A dispatch timeout is indeterminate. The adapter can complete after the
  caller receives the timeout. External receivers must support idempotency when
  a caller can retry the operation.

  This Plugin is not a durable outbox. For durable local delivery, dispatch to
  a `Jido.Signal.Bus` and use a durable Bus consumer.
  """

  use Jido.Plugin,
    agent: Jido.Plugin.Dispatch.Agent,
    agent_server: Jido.Plugin.Dispatch.Server

  alias Jido.Plugin.Dispatch.Send
  alias Jido.Signal

  @doc "Creates one post-commit Signal delivery Directive."
  @spec send(Signal.t(), Jido.Signal.Dispatch.dispatch_configs()) :: Send.t()
  def send(signal, target), do: %Send{signal: signal, target: target}
end
