defmodule Jido.Plugin.Audit do
  @moduledoc """
  Stores bounded domain audit records in portable Agent state.

  Audit records commit with the domain state that produced them. This Plugin
  does not use a runtime and does not record every Turn automatically. Actions
  select the domain facts that must be audited. A failed Turn cannot add a
  record because it does not commit. Use `Jido.Agent.Turn.Outcome` at the Server
  error-policy boundary to audit failed Turns.

      plugins: [{Jido.Plugin.Audit, max_entries: 1_000}]
  """

  use Jido.Plugin

  alias Jido.Plugin.Audit.Record
  alias Jido.Signal.ID

  @default_max_entries 1_000
  @state_schema Zoi.object(%{
                  records: Zoi.list(Zoi.struct(Record)) |> Zoi.default([])
                })
                |> Zoi.default(%{records: []})

  @doc "Creates one domain audit Directive."
  @spec record(term(), atom(), keyword()) :: Record.t()
  def record(event, outcome, opts \\ []) do
    %Record{
      id: Keyword.get_lazy(opts, :id, &ID.generate!/0),
      at: Keyword.get(opts, :at, System.system_time(:millisecond)),
      event: event,
      outcome: outcome,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @impl Jido.Plugin
  def state_spec(opts) do
    _max_entries = max_entries!(opts)
    {:audit, @state_schema}
  end

  @impl Jido.Plugin
  def directives(_opts), do: [Record]

  @impl Jido.Plugin
  def validate_directive(%Record{} = record, _opts) do
    with {:ok, record} <- Zoi.parse(Record.schema(), Map.from_struct(record)),
         true <- ID.valid?(record.id),
         :ok <- Jido.Action.validate_static_data(record) do
      {:ok, record}
    else
      false ->
        invalid("Audit record id must be a UUID7", %{id: record.id})

      {:error, reason} when is_binary(reason) ->
        invalid("Audit record must contain portable data", %{reason: reason})

      {:error, _reason} = error ->
        error
    end
  end

  @impl Jido.Plugin
  def update_state(state, records, opts) do
    max_entries = max_entries!(opts)
    records = Enum.take(state.records ++ records, -max_entries)
    {:ok, %{state | records: records}}
  end

  defp max_entries!(opts) do
    case Keyword.get(opts, :max_entries, @default_max_entries) do
      value when is_integer(value) and value > 0 ->
        value

      value ->
        raise ArgumentError,
              "Audit max_entries must be a positive integer, got: #{inspect(value)}"
    end
  end

  defp invalid(message, details) do
    {:error, Jido.Error.validation_error(message, kind: :config, details: details)}
  end
end
