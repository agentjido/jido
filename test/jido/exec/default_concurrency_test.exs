defmodule Jido.Exec.DefaultConcurrencyTest do
  use Covenant.Case, component: "jido_action.boundary", async: false

  alias Jido.Exec
  alias JidoActionTest.Fixtures.Actions.Add
  alias JidoActionTest.Fixtures.ConcurrencyProbeAction

  setup do
    previous = Application.fetch_env(:jido, :max_concurrency)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido, :max_concurrency, value)
        :error -> Application.delete_env(:jido, :max_concurrency)
      end
    end)

    :ok
  end

  @tag obligation: "jido_action.boundary.I6"
  test "run/4 caps the fallback concurrency at ten schedulers" do
    Application.delete_env(:jido, :max_concurrency)

    assert_concurrency_limit(min(System.schedulers_online(), 10))
  end

  @tag obligation: "jido_action.boundary.I6"
  test "run/4 uses the package configuration and an explicit option overrides it" do
    Application.put_env(:jido, :max_concurrency, 2)
    assert_concurrency_limit(2)
    assert_concurrency_limit(1, max_concurrency: 1)
  end

  @tag obligation: "jido_action.boundary.I6"
  test "run/4 rejects an invalid package concurrency configuration" do
    Application.put_env(:jido, :max_concurrency, 0)

    assert {:error, %Jido.Action.Error.ConfigurationError{details: details}} =
             Exec.run(Add, %{value: 1, amount: 1})

    assert details == %{option: :max_concurrency, value: 0}

    assert Exec.run(Add, %{value: 1, amount: 1}, %{}, max_concurrency: 1) ==
             {:ok, %{value: 2}}
  end

  defp assert_concurrency_limit(limit, opts \\ []) do
    node_count = limit + 1
    test_pid = self()

    probe =
      start_supervised!({Agent, fn -> %{max: 0, running: 0} end}, id: make_ref())

    names = Enum.map(1..node_count, &"probe_#{limit}_#{&1}")

    components =
      Enum.map(names, fn name ->
        %{
          kind: :step,
          name: name,
          action: ConcurrencyProbeAction,
          params: %{
            probe: Jido.Flow.Ref.context(:probe),
            side: name,
            test_pid: Jido.Flow.Ref.context(:test_pid)
          }
        }
      end)

    output = Map.new(names, &{&1, Jido.Flow.Ref.result(&1)})

    flow =
      Jido.Flow.new!(%{
        name: "exec_default_concurrency_#{limit}",
        components: components,
        output: output
      })

    caller =
      Task.async(fn ->
        Exec.run(flow, %{}, %{probe: probe, test_pid: test_pid}, opts)
      end)

    started =
      for _index <- 1..limit do
        assert_receive {ConcurrencyProbeAction, :started, ^probe, _side, pid}, 1_000
        pid
      end

    refute_receive {ConcurrencyProbeAction, :started, ^probe, _side, _pid}, 100
    assert Agent.get(probe, & &1.max) == limit

    Enum.each(started, &send(&1, {:release, probe}))
    assert_receive {ConcurrencyProbeAction, :started, ^probe, _side, final_pid}, 1_000
    send(final_pid, {:release, probe})

    assert {:ok, results} = Task.await(caller, 2_000)
    assert map_size(results) == node_count
  end
end
