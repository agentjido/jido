defmodule Jido.Plugin.Audit do
  @moduledoc """
  Stores bounded domain audit records in portable Agent state.

  Audit records commit with the domain state that produced them. This Plugin
  does not use a runtime and does not record every Turn automatically. Actions
  select the domain facts that must be audited. A failed Turn cannot add a
  record because it does not commit. Use the terminal summary map passed to
  the `Jido.AgentServer` error-policy callback to audit failed Turns outside
  the Agent state. The same summary is available as `status/1` `last_outcome`.

      plugins: [{Jido.Plugin.Audit, max_entries: 1_000}]
  """

  use Jido.Plugin, option_keys: [agent: [:max_entries]]

  alias Jido.Plugin.Audit.Record
  alias Jido.Signal.ID

  @typedoc "One Audit Plugin option."
  @type plugin_option :: {:max_entries, pos_integer()}

  @typedoc "One option for constructing an Audit Record."
  @type record_option ::
          {:id, String.t() | nil}
          | {:at, non_neg_integer() | nil}
          | {:metadata, map()}

  @record_option_keys [:id, :at, :metadata]

  @doc "Creates one domain audit Directive."
  @spec record(term(), atom(), [record_option()]) :: Record.t()
  def record(event, outcome, opts \\ []) do
    opts = record_options!(opts)

    %Record{
      id: Keyword.get_lazy(opts, :id, &ID.generate!/0),
      at: Keyword.get_lazy(opts, :at, fn -> System.system_time(:millisecond) end),
      event: event,
      outcome: outcome,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @default_max_entries 1_000
  @state_schema Zoi.object(%{records: Zoi.list(Zoi.struct(Record)) |> Zoi.default([])})
                |> Zoi.default(%{records: []})

  @impl true
  def state_spec(opts) do
    _max_entries = max_entries!(opts)
    {:audit, @state_schema}
  end

  @impl true
  def directives(_opts), do: [Record]

  @impl true
  def reduce(reduction, opts) do
    records = Enum.filter(reduction.directives, &match?(%Record{}, &1))
    apply_records(reduction.plugin_state, records, opts)
  end

  @doc false
  @spec apply_records(map(), [Record.t()], [plugin_option()]) :: {:ok, map()}
  def apply_records(state, [], opts) do
    max_entries = max_entries!(opts)
    count = length(state.records)

    if count <= max_entries do
      {:ok, state}
    else
      {:ok, %{state | records: Enum.drop(state.records, count - max_entries)}}
    end
  end

  def apply_records(state, records, opts) do
    max_entries = max_entries!(opts)
    incoming_count = length(records)

    records =
      if incoming_count >= max_entries do
        Enum.take(records, -max_entries)
      else
        Enum.take(state.records, -(max_entries - incoming_count)) ++ records
      end

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

  defp record_options!(opts) do
    if Keyword.keyword?(opts) do
      keys = Keyword.keys(opts)
      invalid = keys -- @record_option_keys

      case invalid do
        [] -> opts
        keys -> raise ArgumentError, "Audit record does not accept option keys: #{inspect(keys)}"
      end
    else
      raise ArgumentError, "Audit record options must be a keyword list"
    end
  end
end
