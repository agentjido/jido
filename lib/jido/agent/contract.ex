defmodule Jido.Agent.Contract do
  @moduledoc """
  Checks Agent result and emission contracts.

  `result/3` checks supplied authoring results without running a handler.
  `directives/2` builds Signal envelopes for runtime emission requests.
  No function in this module dispatches a Signal or invokes a handler.
  """
  alias Jido.Agent.{Data, Error}

  def result(_definition, _route, {:error, _} = error), do: error

  def result(definition, %{handler: %{kind: kind}} = route, {:ok, state})
      when kind in [:action, :flow],
      do: result(definition, route, {:ok, state, []})

  def result(definition, %{handler: %{kind: kind}} = route, {:ok, state, directives})
      when kind in [:action, :flow] do
    with {:ok, schema} <- Jido.Agent.Validation.state_schema(definition),
         :ok <- Error.at(Data.complete(schema, state), :state),
         {:ok, emissions} <-
           Error.at(Data.list(directives, &emission(&1, definition)), :directives),
         :ok <- allowed(route, emissions) do
      {:ok, %{state: state, emissions: emissions}}
    end
  end

  def result(_definition, %{handler: %{kind: :transform}} = route, {:ok, %Jido.Signal{} = signal}) do
    with :ok <- signal(signal),
         :ok <- allowed(route, [Jido.Agent.Directive.emit(signal)]),
         do: {:ok, %{emissions: [Jido.Agent.Directive.emit(signal)]}}
  end

  def result(_, _, _),
    do: Error.fail(:invalid_result, [], "Result does not match the selected handler contract")

  def pass_through(%{handler: %{kind: :pass_through}} = route, %Jido.Signal{} = input) do
    with :ok <- signal(input),
         :ok <- allowed(route, [Jido.Agent.Directive.emit(input)]),
         do: {:ok, %{emissions: [Jido.Agent.Directive.emit(input)]}}
  end

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

  @doc false
  def check_emissions(nil, _directives), do: :ok

  def check_emissions(route, directives) do
    emissions =
      Enum.filter(directives, fn
        %Jido.Agent.Directive.Emit{} -> true
        %Jido.AgentServer.Directive.OwnerSend{} -> true
        %Jido.AgentServer.Directive.AgentSend{} -> true
        _ -> false
      end)

    allowed(route, emissions)
  end

  defp emission(%Jido.Agent.Directive.Emit{} = request, _definition),
    do: Jido.Agent.Directive.validate(request)

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

  defp allowed(%{emits: nil}, _), do: :ok

  defp allowed(route, emissions) do
    with {:ok, _} <-
           Data.list(emissions, fn emission ->
             type =
               case emission do
                 %{signal: signal} -> signal.type
                 %{type: type} -> type
               end

             if type in route.emits,
               do: {:ok, emission},
               else:
                 Error.fail(
                   :undeclared_emission,
                   [:emits],
                   "Signal type is outside the route contract",
                   %{type: type, route: route.path}
                 )
           end),
         do: :ok
  end
end
