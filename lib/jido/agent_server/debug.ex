defmodule Jido.AgentServer.Debug do
  @moduledoc false

  alias Jido.AgentServer.State
  alias Jido.Error

  @doc false
  @spec recent(State.t(), keyword()) :: {:ok, [map()]} | {:error, :debug_not_enabled}
  def recent(%State{debug: true} = data, opts) do
    limit = opts |> Keyword.get(:limit, data.debug_max_events) |> normalize_limit()
    {:ok, Enum.take(data.debug_events, limit)}
  end

  def recent(%State{debug: false}, _opts), do: {:error, :debug_not_enabled}

  @doc false
  @spec record(State.t(), atom(), map()) :: State.t()
  def record(%State{debug: false} = data, _event, _metadata), do: data

  def record(%State{} = data, event, metadata) do
    entry = %{event: event, at: System.system_time(:millisecond), metadata: metadata}
    events = Enum.take([entry | data.debug_events], data.debug_max_events)
    %{data | debug_events: events}
  end

  @doc false
  @spec public_error(term()) :: map()
  def public_error(reason), do: Error.to_map(reason)

  defp normalize_limit(limit) when is_integer(limit) and limit >= 0, do: limit
  defp normalize_limit(_limit), do: 0
end
