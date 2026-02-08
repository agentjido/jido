defmodule JidoTest.AgentServer.LifecycleContractTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer
  alias Jido.AgentServer.State
  alias Jido.AgentServer.State.Lifecycle, as: LifecycleState
  alias JidoTest.TestAgents.Minimal

  defmodule InitTrackingLifecycle do
    @moduledoc false
    @behaviour Jido.AgentServer.Lifecycle

    @impl true
    def init(%LifecycleState{} = lifecycle, %State{} = state) do
      if is_list(lifecycle.storage) do
        case Keyword.get(lifecycle.storage, :test_pid) do
          pid when is_pid(pid) ->
            send(pid, {:lifecycle_init_args, lifecycle, state.id})

          _ ->
            :ok
        end
      end

      state
    end

    @impl true
    def handle_event(_event, state), do: {:cont, state}

    @impl true
    def terminate(_reason, _state), do: :ok
  end

  test "lifecycle init receives lifecycle struct as single source of truth", %{jido: jido} do
    id = "lifecycle-contract-#{System.unique_integer([:positive])}"

    {:ok, pid} =
      AgentServer.start_link(
        agent: Minimal,
        id: id,
        jido: jido,
        lifecycle_mod: InitTrackingLifecycle,
        pool: :sessions,
        pool_key: "session-1",
        idle_timeout: 1_234,
        storage: [test_pid: self()]
      )

    assert_receive {:lifecycle_init_args, lifecycle, ^id}, 500
    assert lifecycle.mod == InitTrackingLifecycle
    assert lifecycle.pool == :sessions
    assert lifecycle.pool_key == "session-1"
    assert lifecycle.idle_timeout == 1_234

    GenServer.stop(pid)
  end
end
