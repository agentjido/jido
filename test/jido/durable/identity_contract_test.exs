defmodule Jido.Durable.IdentityContractTest do
  use Covenant.Case, component: "jido_action.execution", async: false

  import Jido.Test.Case, only: [signal: 2]

  alias Jido.Durable
  alias Jido.Durable.Status

  setup do
    instance = Module.concat(__MODULE__, Instance)
    persistence = {Jido.Persistence.ETS, table: instance}
    start_supervised!({Jido, name: instance, namespace: "jido/durable/identity-test", persistence: persistence})
    %{jido: instance}
  end

  @tag obligation: "jido_action.execution.I22"
  test "a direct Flow resumes its saved value after display or executable changes", c do
    module = timer_module()
    compile_timer(module, "Original", 1_000)
    flow = module.flow()

    for edited <- [%{flow | description: "New description"}, %{flow | output: %{complete: false}}] do
      input = signal("durable.request", %{request_id: "direct"})
      assert {:ok, %Status{state: :waiting, ref: ref}} = Durable.start(c.jido, flow, input, now: 100)

      assert {:error, :execution_definition_changed} =
               Durable.start(c.jido, edited, input, id: ref.id, now: 100)

      assert {:ok, %Status{state: :completed}} = Durable.resume(c.jido, ref, now: 1_100)
      assert {:ok, %{complete: true}} = Durable.result(c.jido, ref)
    end
  end

  @tag obligation: "jido_action.execution.I22"
  test "a module-backed Flow rejects display and executable edits before resume", c do
    for {description, delay} <- [{"New description", 1_000}, {"Original", 2_000}] do
      module = timer_module()
      compile_timer(module, "Original", 1_000)

      input = signal("durable.request", %{})
      assert {:ok, %Status{state: :waiting, ref: ref}} = Durable.start(c.jido, module, input, now: 100)

      unload(module)
      compile_timer(module, description, delay)
      assert {:error, :execution_definition_changed} = Durable.resume(c.jido, ref, now: 1_100)

      unload(module)
      compile_timer(module, "Original", 1_000)
      assert {:ok, %Status{state: :completed}} = Durable.resume(c.jido, ref, now: 1_100)
    end
  end

  defp timer_module do
    module = Module.concat(__MODULE__, "Timer#{System.unique_integer([:positive])}")
    on_exit(fn -> unload(module) end)
    module
  end

  defp compile_timer(module, description, delay) do
    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use Jido.Flow, name: "versioned_wait", description: unquote(description)

          flow do
            timer "timer", after_ms: unquote(delay)
            output %{complete: true, timer: result("timer")}
          end
        end
      end
    )
  end

  defp unload(module) do
    :code.purge(module)
    :code.delete(module)
  end
end
