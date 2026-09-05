defmodule Jido.Examples.AuditOutbox do
  @moduledoc "Business state and ordered audit intent committed in one Turn."

  use Jido.Agent,
    name: "examples_audit_outbox",
    description: "Commits audit intent only with successful business work"

  agent do
    schema Zoi.object(%{
             balance: Zoi.integer() |> Zoi.default(0),
             audit_outbox: Zoi.list(Zoi.map()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/audit_outbox"

    route "examples.audit.change", Jido.Examples.AuditOutbox.Change do
      define :adjust_balance
    end
  end

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.AuditOutbox.MemorySink

  def dispatch(server, sink) do
    server
    |> Server.agent()
    |> Map.fetch!(:state)
    |> Map.fetch!(:audit_outbox)
    |> Enum.each(&MemorySink.deliver(sink, &1))

    :ok
  end
end

defmodule Jido.Examples.AuditOutbox.MemorySink do
  @moduledoc "A local idempotent audit sink."
  use Elixir.Agent

  def start_link(_opts \\ []), do: Elixir.Agent.start_link(fn -> %{} end)
  def deliver(sink, record), do: Elixir.Agent.update(sink, &Map.put_new(&1, record.id, record))

  def records(sink),
    do: Elixir.Agent.get(sink, &(&1 |> Map.values() |> Enum.sort_by(fn r -> r.sequence end)))
end

defmodule Jido.Examples.AuditOutbox.Change do
  @moduledoc false
  use Jido.Action,
    name: "examples_audit_outbox_change",
    schema: Zoi.object(%{command_id: Zoi.string() |> Zoi.min(1), amount: Zoi.integer()})

  alias Jido.Action.Error

  @impl Jido.Action
  def run(%{command_id: command_id, amount: amount}, %{agent_state: state})
      when is_integer(amount) do
    next_balance = state.balance + amount

    cond do
      Enum.any?(state.audit_outbox, &(&1.id == command_id)) ->
        {:error, Error.validation_error("audit command is already committed")}

      next_balance >= 0 ->
        record = %{
          id: command_id,
          sequence: length(state.audit_outbox) + 1,
          type: :balance_changed,
          amount: amount,
          resulting_balance: next_balance
        }

        {:ok, %{state | balance: next_balance, audit_outbox: state.audit_outbox ++ [record]}}

      true ->
        {:error, Error.validation_error("balance cannot become negative")}
    end
  end
end
