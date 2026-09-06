defmodule Jido.Examples.TurnObservation.EventProbe do
  @moduledoc """
  A short-lived, external collector for the observation diagnostics.

  Attach before Agent startup and detach after shutdown. The collector copies
  SDK events without deriving Outcomes from command replies or Agent state.
  ETS belongs to the caller. This finite test probe is not an export service or
  an OBS-03 consumer with a queue/backpressure contract.
  """

  # Existing event names plus the semantic names already proposed in
  # docs/design/observability.md. Attaching does not create any of these events.
  @prefixes [
    [:jido, :agent_server, :signal],
    [:jido, :agent_server, :directive],
    [:jido, :agent, :lifecycle],
    [:jido, :agent, :turn],
    [:jido, :agent, :commit],
    [:jido, :agent, :directive]
  ]
  @events for(prefix <- @prefixes, ending <- [:start, :stop, :exception], do: prefix ++ [ending]) ++
            [[:jido, :agent, :turn, :settled], [:jido, :agent, :admission, :rejected]]

  def attach(agent_ids) do
    table = :ets.new(__MODULE__, [:ordered_set, :public])
    handler = {__MODULE__, make_ref()}
    ids = agent_ids |> List.wrap() |> MapSet.new()
    :ok = :telemetry.attach_many(handler, @events, &__MODULE__.capture/4, {table, ids})
    %{table: table, handler: handler}
  end

  def events(probe), do: Enum.map(:ets.tab2list(probe.table), &elem(&1, 1))

  def detach(probe) do
    :telemetry.detach(probe.handler)
    if :ets.info(probe.table) != :undefined, do: :ets.delete(probe.table)
    :ok
  end

  @doc false
  def capture(event, measurements, %{agent_id: agent_id} = metadata, {table, ids}) do
    if MapSet.member?(ids, agent_id) do
      :ets.insert(table, {
        System.unique_integer([:positive, :monotonic]),
        %{event: event, measurements: measurements, metadata: metadata}
      })
    end

    :ok
  end

  def capture(_event, _measurements, _metadata, _config), do: :ok
end
