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

  use Jido.Plugin, agent: Jido.Plugin.Audit.Agent

  alias Jido.Plugin.Audit.Record
  alias Jido.Signal.ID

  @doc "Creates one domain audit Directive."
  @spec record(term(), atom(), keyword()) :: Record.t()
  def record(event, outcome, opts \\ []) do
    %Record{
      id: Keyword.get_lazy(opts, :id, &ID.generate!/0),
      at: Keyword.get_lazy(opts, :at, fn -> System.system_time(:millisecond) end),
      event: event,
      outcome: outcome,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
