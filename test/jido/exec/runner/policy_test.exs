defmodule Jido.Exec.Runner.PolicyTest do
  use Covenant.Case, component: "jido_action.execution", async: false
  @moduletag obligation: "jido_action.execution.I18"

  alias Jido.Error
  alias Jido.Exec

  defmodule TimeoutAction do
    use Jido.Action, name: "exec_v2_timeout"

    @impl true
    def run(_params, _context) do
      receive do
        :release -> {:ok, %{released: true}}
      end
    end
  end

  defmodule RetryAction do
    use Jido.Action, name: "exec_v2_retry"

    @impl true
    def run(params, %{counter: counter}) do
      attempt = Agent.get_and_update(counter, fn count -> {count + 1, count + 1} end)

      if attempt < params.succeed_on do
        {:error, Error.execution_error("retry", %{retry: true, attempt: attempt})}
      else
        {:ok, %{attempt: attempt}}
      end
    end
  end

  defmodule UnsafeAction do
    use Jido.Action, name: "exec_v2_unsafe"

    @impl true
    def run(_params, %{counter: counter}) do
      Agent.update(counter, &(&1 + 1))
      {:error, Error.execution_error("unsafe", %{retry: false})}
    end
  end

  defmodule RetryEffectAction do
    use Jido.Action, name: "exec_v2_retry_effect"

    @impl true
    def run(%{succeed_on: succeed_on}, %{counter: counter}) do
      attempt = Agent.get_and_update(counter, fn count -> {count + 1, count + 1} end)

      if attempt < succeed_on do
        {:error, Error.execution_error("retry", %{retry: true, attempt: attempt})}
      else
        {:ok, %{attempt: attempt}, [:notify]}
      end
    end
  end

  defmodule FailFastMapAction do
    use Jido.Action, name: "exec_fail_fast_map"

    @impl true
    def run(%{item: item, owner: owner}, _context) do
      send(owner, {:map_item_started, item})

      if item == 0,
        do: {:error, Error.execution_error("stop", %{retry: false})},
        else: {:ok, %{item: item}}
    end
  end

  test "Runic PolicyDriver owns timeouts" do
    assert {:error, %Error.TimeoutError{timeout: 10}} =
             Exec.run(TimeoutAction, %{}, %{}, timeout: 10)
  end

  test "Runic PolicyDriver owns retry and backoff policy" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    assert Exec.run(RetryAction, %{succeed_on: 3}, %{counter: counter},
             max_attempts: 3,
             backoff: :linear,
             base_delay_ms: 0,
             max_delay_ms: 0
           ) == {:ok, %{attempt: 3}}

    assert Agent.get(counter, & &1) == 3
  end

  test "max_attempts retries only errors marked retryable" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    assert {:error, %Error.ExecutionError{message: "unsafe"}} =
             Exec.run(UnsafeAction, %{}, %{counter: counter}, max_attempts: 3)

    assert Agent.get(counter, & &1) == 1

    assert {:error, %Error.TimeoutError{}} =
             Exec.run(TimeoutAction, %{}, %{}, timeout: 5, max_attempts: 3)
  end

  test "a serial fail-fast Map does not start later items" do
    flow =
      Jido.Flow.new!(%{
        name: "exec_serial_fail_fast_map",
        components: [
          %{
            kind: :map,
            name: "items",
            collection: [0, 1],
            action: FailFastMapAction,
            params: %{item: Jido.Flow.Ref.item(), owner: Jido.Flow.Ref.context(:owner)},
            on_error: :fail_fast
          }
        ],
        output: Jido.Flow.Ref.result("items")
      })

    assert {:error, %Error.ExecutionError{message: "stop"}} =
             Exec.run(flow, %{}, %{owner: self()}, max_concurrency: 1)

    assert_received {:map_item_started, 0}
    refute_received {:map_item_started, 1}
  end

  @tag obligation: "jido_action.execution.I18"
  test "retry attempts keep one activation and one logical effect identity" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    instruction =
      Jido.Instruction.new!(
        target: RetryEffectAction,
        params: %{succeed_on: 3},
        context: %{counter: counter}
      )

    workflow =
      instruction
      |> Jido.Exec.Compiler.compile!()
      |> Runic.Workflow.enable_event_emission()
      |> Runic.Workflow.put_run_context(%{_global: instruction.context})
      |> Runic.Workflow.react_until_satisfied(instruction.params,
        scheduler_policies: [
          {:default,
           %{
             max_retries: 2,
             backoff: :none,
             base_delay_ms: 0,
             max_delay_ms: 0,
             on_failure: :halt
           }}
        ]
      )

    dispatched =
      Enum.filter(workflow.runnable_events, fn
        %Runic.Workflow.RunnableDispatched{node_name: "action"} -> true
        _event -> false
      end)

    assert [first, second, third] = dispatched
    assert first.activation_id == second.activation_id
    assert second.activation_id == third.activation_id
    assert Enum.uniq(Enum.map(dispatched, & &1.attempt_id)) |> length() == 3

    assert [%Runic.Workflow.RunnableCompleted{} = completed] =
             Enum.filter(
               workflow.runnable_events,
               &match?(
                 %Runic.Workflow.RunnableCompleted{
                   result_fact: %{meta: %{jido: %{effects: [:notify]}}}
                 },
                 &1
               )
             )

    assert completed.result_fact.meta.jido.effects == [:notify]
  end
end
