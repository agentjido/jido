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

  use Jido.Plugin

  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Plugin.Dispatch.{Runtime, Send}
  alias Jido.Signal
  alias Jido.Signal.Dispatch, as: SignalDispatch
  alias Jido.Dispatch.Preparation, as: DispatchPreparation

  @doc "Creates one post-commit Signal delivery Directive."
  @spec send(Signal.t(), SignalDispatch.dispatch_configs()) :: Send.t()
  def send(signal, target), do: %Send{signal: signal, target: target}

  @impl Jido.Plugin
  def directives(_opts), do: [Send]

  @impl Jido.Plugin
  def validate_directive(%Send{} = directive, _opts) do
    with {:ok, directive} <- Zoi.parse(Send.schema(), Map.from_struct(directive)),
         {:ok, target} <- SignalDispatch.validate_opts(directive.target) do
      {:ok, %{directive | target: target}}
    end
  end

  @impl Jido.Plugin
  def dispatch(runtime, %Send{} = directive, %DirectiveContext{} = context, opts) do
    signal = DispatchPreparation.propagate(directive.signal, context.effective_signal)
    target = DispatchPreparation.inherit_bus_scope(directive.target, context.jido)

    GenServer.call(
      runtime,
      {:deliver, signal, target},
      Keyword.get(opts, :timeout, 5_000)
    )
  catch
    :exit, reason -> {:error, {:dispatch_runtime_unavailable, reason}}
  end

  @doc false
  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  end
end
