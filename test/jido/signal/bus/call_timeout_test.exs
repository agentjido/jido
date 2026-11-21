defmodule Jido.Signal.Bus.CallTimeoutTest do
  use Jido.Test.Signal.Case, async: false

  alias Jido.Signal.Bus
  alias Jido.Signal.Bus.Store.Memory

  defmodule BlockingStore do
    @behaviour Jido.Signal.Bus.Store

    @impl true
    def init(opts) do
      with owner when is_pid(owner) <- Keyword.get(opts, :owner),
           {:ok, memory} <- Memory.init([]) do
        {:ok, %{owner: owner, memory: memory}}
      else
        _invalid -> {:error, :missing_owner}
      end
    end

    @impl true
    def append(records, state) do
      send(state.owner, {:store_blocked, self()})

      receive do
        :release_store ->
          case Memory.append(records, state.memory) do
            {:ok, memory} -> {:ok, %{state | memory: memory}}
            {:error, reason} -> {:error, reason}
          end
      end
    end

    @impl true
    def read(opts, state), do: Memory.read(opts, state.memory)

    @impl true
    def latest_cursor(state), do: Memory.latest_cursor(state.memory)

    @impl true
    def list_subscriptions(state), do: Memory.list_subscriptions(state.memory)

    @impl true
    def put_subscription(subscription, state) do
      case Memory.put_subscription(subscription, state.memory) do
        {:ok, memory} -> {:ok, %{state | memory: memory}}
        {:error, reason} -> {:error, reason}
      end
    end

    @impl true
    def delete_subscription(id, state) do
      {:ok, memory} = Memory.delete_subscription(id, state.memory)
      {:ok, %{state | memory: memory}}
    end
  end

  setup do
    previous = Application.fetch_env(:jido, Bus)
    Application.put_env(:jido, Bus, call_timeout: 20)

    on_exit(fn ->
      case previous do
        {:ok, config} -> Application.put_env(:jido, Bus, config)
        :error -> Application.delete_env(:jido, Bus)
      end
    end)

    :ok
  end

  test "returns a timeout when a Store callback does not return" do
    name = "timeout-#{System.unique_integer([:positive])}"

    bus =
      start_supervised!(
        {Bus, name: name, store: BlockingStore, store_opts: [owner: self()]},
        id: {Bus, name}
      )

    task = Task.async(fn -> Bus.publish(bus, [signal("timeout.event")]) end)
    assert_receive {:store_blocked, ^bus}
    assert Task.await(task) == {:error, :timeout}

    send(bus, :release_store)
    assert {:ok, [_record]} = Bus.replay(bus)
  end
end
