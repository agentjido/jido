defmodule Jido.Examples.Signals.DispatchAdapters.Capture do
  @behaviour Jido.Signal.Dispatch.Adapter

  @impl true
  def options_schema do
    Jido.Joi.keyword(
      [target: Jido.Joi.any() |> Jido.Joi.required()],
      unrecognized_keys: :error
    )
  end

  @impl true
  def deliver(signal, opts) do
    send(Keyword.fetch!(opts, :target), {:captured_signal, signal})
    :ok
  end
end

defmodule Jido.Examples.Signals.DispatchAdapters do
  alias Jido.Signal.Dispatch

  def local_targets(target) do
    [
      {:pid, target: target, delivery_mode: :async},
      {Jido.Examples.Signals.DispatchAdapters.Capture, target: target},
      {:noop, []}
    ]
  end

  def validate_http_target do
    Dispatch.validate_opts({:http, url: "https://example.test/events", timeout: 100})
  end
end
