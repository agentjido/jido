defmodule Jido.Agent.Contract do
  @moduledoc """
  Normalizes Agent emission requests.

  `directives/2` builds Signal envelopes for runtime emission requests.
  No function in this module dispatches a Signal or invokes a handler.
  """
  alias Jido.Agent.{Data, Error}

  @doc false
  def directives(definition, directives) do
    Data.list(directives, fn
      %{kind: :emit} = request ->
        with {:ok, request} <- emission(request, definition),
             {:ok, signal} <- envelope(request, definition) do
          {:ok, Jido.Agent.Directive.emit(signal)}
        end

      directive ->
        {:ok, directive}
    end)
  end

  defp envelope(%{signal: signal}, _), do: {:ok, signal}

  defp envelope(%{type: type, data: data}, definition),
    do: Jido.Signal.new(type, data, source: definition.signal_source)

  defp emission(%{kind: :emit, signal: %Jido.Signal{} = signal} = request, _definition) do
    with {:ok, _} <- Data.fields(request, [:kind, :signal]),
         :ok <- signal(signal),
         do: {:ok, request}
  end

  defp emission(%{kind: :emit, type: type, data: data} = request, definition) do
    with {:ok, _} <- Data.fields(request, [:kind, :type, :data]),
         :ok <- Data.exact(type),
         :ok <- Data.plain_map(data),
         :ok <- Data.static(data),
         :ok <- Error.at(Data.nonempty(definition.signal_source), :signal_source),
         do: {:ok, request}
  end

  defp emission(_, _),
    do: Error.fail(:invalid_directive, [], "Expected a registered emission directive")

  defp signal(signal) do
    case Jido.Schema.validate(Jido.Signal.schema(), signal) do
      :ok ->
        Data.static(signal)

      {:error, issues} ->
        Error.fail(:invalid_signal, [], "Invalid Signal envelope", %{issues: issues})
    end
  end
end
