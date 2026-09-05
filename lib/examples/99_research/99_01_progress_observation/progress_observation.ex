defmodule Jido.Examples.ProgressObservation.Buffer do
  @moduledoc """
  A bounded, demand-read progress buffer for one producer.
  ETS slots replace old events. Consumers have no pushed message queue.
  Loss of the buffer does not fail the producer. Terminal state belongs to
  the Agent and can be queried after the buffer is lost.
  """
  use GenServer
  def start_link(capacity), do: GenServer.start_link(__MODULE__, capacity)
  def table(pid), do: GenServer.call(pid, :table)

  @impl true
  def init(capacity) when is_integer(capacity) and capacity > 0 do
    table = :ets.new(__MODULE__, [:set, :public])
    :ets.insert(table, [{:sequence, 0}, {:capacity, capacity}])
    {:ok, table}
  end

  @impl true
  def handle_call(:table, _, table), do: {:reply, table, table}

  def publish(table, progress) do
    capacity = :ets.lookup_element(table, :capacity, 2)
    sequence = :ets.update_counter(table, :sequence, 1)
    :ets.insert(table, {rem(sequence, capacity), sequence, progress})
    :ok
  rescue
    ArgumentError -> :ok
  end

  def read(table, cursor) do
    events =
      for {slot, sequence, value} <- :ets.tab2list(table), is_integer(slot), sequence > cursor do
        {sequence, value}
      end
      |> Enum.sort()

    missed =
      case events do
        [{first, _} | _] -> max(first - cursor - 1, 0)
        [] -> 0
      end

    %{
      events: events,
      missed: missed,
      cursor:
        case List.last(events) do
          nil -> cursor
          {last, _} -> last
        end
    }
  rescue
    ArgumentError -> %{events: [], missed: :buffer_lost, cursor: cursor}
  end
end

defmodule Jido.Examples.ProgressObservation do
  @moduledoc "Application progress and explicit waiting reasons through public Agent commands."
  use Jido.Agent, name: "research_progress_observation"

  agent do
    schema Zoi.object(%{
             waiting:
               Zoi.enum([:none, :approval, :child, :retry, :delivery]) |> Zoi.default(:none),
             status: Zoi.enum([:idle, :waiting, :completed, :cancelled]) |> Zoi.default(:idle),
             result: Zoi.string() |> Zoi.default("")
           })
  end

  routes do
    signal_source "/examples/progress"

    route "progress.wait" do
      action %{reason: reason},
        name: "research_wait",
        schema: Zoi.object(%{reason: Zoi.enum([:approval, :child, :retry, :delivery])}),
        context: context do
        {:ok, %{context.agent_state | waiting: reason, status: :waiting}}
      end

      define :wait_for, args: [:reason]
    end

    route "progress.work" do
      action _input, name: "research_progress_work", schema: Zoi.object(%{}), context: context do
        for step <- 1..10, do: context.report.(%{step: step, total: 10})
        context.barrier.()
        {:ok, %{context.agent_state | waiting: :none, status: :completed, result: "report"}}
      end

      define :work
    end

    route "progress.cancel" do
      action _input,
        name: "research_progress_cancel",
        schema: Zoi.object(%{}),
        context: context do
        {:ok, %{context.agent_state | waiting: :none, status: :cancelled}}
      end

      define :cancel_wait
    end
  end

  def view(server, table, cursor \\ 0) do
    %{
      committed: Jido.AgentServer.snapshot(server).agent.state,
      progress: __MODULE__.Buffer.read(table, cursor)
    }
  end
end
