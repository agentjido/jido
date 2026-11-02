defmodule JidoActionTest.Fixtures.Execution.SessionOwner do
  @moduledoc false
  use GenServer, restart: :temporary

  # Example adapter code, not a Jido API. The service accepts a client-generated
  # session ID and idempotent release. Each request has its own finite bound.
  @request_timeout 1_000

  def open(supervisor, service, observer) do
    opts = [borrower: self(), service: service, observer: observer]

    with {:ok, owner} <- DynamicSupervisor.start_child(supervisor, {__MODULE__, opts}),
         {:ok, id} <- GenServer.call(owner, :open, :infinity) do
      {:ok, owner, id}
    end
  end

  def close(owner), do: GenServer.cast(owner, :close)

  @impl true
  def handle_cast(:close, state) do
    cleanup(state)
    {:stop, :normal, state}
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    state = Map.new(opts)
    {:ok, Map.merge(state, %{monitor: Process.monitor(state.borrower), id: make_ref()})}
  end

  @impl true
  def handle_call(:open, {borrower, _tag}, %{borrower: borrower} = state) do
    case request(state.service, {:open, state.id}) do
      {:ok, id} ->
        {:reply, {:ok, id}, state}

      {:error, _reason} = error ->
        cleanup(state)
        {:stop, :normal, error, state}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, monitor, :process, borrower, _reason},
        %{monitor: monitor, borrower: borrower} = state
      ) do
    cleanup(state)
    {:stop, :normal, state}
  end

  defp cleanup(state) do
    # Release even if acquisition had an uncertain result. The service's
    # client-generated ID makes that possible; many external APIs lack this.
    result = request(state.service, {:release, state.id})
    send(state.observer, {:session_cleanup, state.id, result})
  end

  defp request(service, message) do
    GenServer.call(service, message, @request_timeout)
  catch
    :exit, reason -> {:error, reason}
  end
end
