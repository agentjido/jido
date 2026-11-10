defmodule Jido.Exec.ContextRefTest do
  use ExUnit.Case, async: true

  defmodule Echo do
    use Jido.Action, name: "context_ref_echo", schema: Jido.Joi.map()

    def run(params, _context), do: {:ok, params}
  end

  defmodule BindingFlow do
    use Jido.Flow, name: "context_ref_binding"

    flow do
      step "a", ctx <- context() do
        {:ok, %{context: ctx}}
      end

      output result("a")
    end
  end

  defmodule ParamsAndOutputFlow do
    use Jido.Flow, name: "context_ref_params_output"

    flow do
      step "a", action: Echo, params: %{context: context()}
      output %{params: result("a", :context), output: context(), tenant: context(:tenant)}
    end
  end

  defmodule MapFlow do
    use Jido.Flow, name: "context_ref_map"

    flow do
      map "m", collection: input(:items), action: Echo, params: %{context: context()}
      output %{items: result("m")}
    end
  end

  @context %{tenant: "one"}

  test "a context binding exposes only caller keys" do
    assert {:ok, %{context: context}} = Jido.Exec.run(BindingFlow, %{}, @context)
    assert context == @context
  end

  test "context references in params and output expose only caller keys" do
    assert {:ok, %{params: params, output: output, tenant: "one"}} =
             Jido.Exec.run(ParamsAndOutputFlow, %{}, @context)

    assert params == @context
    assert output == @context
  end

  test "context references in Map params expose only caller keys" do
    assert {:ok, %{items: [%{context: context}]}} =
             Jido.Exec.run(MapFlow, %{items: [1]}, @context, max_concurrency: 2)

    assert context == @context
  end

  test "a managed run exposes only caller keys" do
    runner = :"context_ref_runner_#{System.unique_integer([:positive])}"
    start_supervised!({Runic.Runner, name: runner})

    assert {:ok, _pid} = Jido.Exec.start(runner, "run", ParamsAndOutputFlow, %{}, @context)
    assert {:ok, %{params: params, output: output}} = await_result(runner, "run", 200)
    assert params == @context
    assert output == @context
  end

  defp await_result(runner, id, attempts) do
    case Jido.Exec.result(runner, id) do
      {:error, %{details: %{reason: :execution_active}}} when attempts > 0 ->
        Process.sleep(10)
        await_result(runner, id, attempts - 1)

      result ->
        result
    end
  end
end
