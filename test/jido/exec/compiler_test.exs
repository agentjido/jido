defmodule Jido.Exec.CompilerTest do
  use ExUnit.Case, async: true

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Test.Action.Fixtures.Actions.EchoParamsAction
  alias Runic.Workflow

  defmodule CountedLeaf do
    @behaviour Jido.Flow

    @impl true
    def flow do
      send(self(), {:materialized, __MODULE__})

      Jido.Flow.new!(%{
        name: "counted_leaf",
        components: [
          %{kind: :step, name: "pass", action: EchoParamsAction, params: %{value: 1}}
        ],
        output: Ref.result("pass")
      })
    end

    @impl true
    def validate_params(params), do: {:ok, params}

    @impl true
    def validate_output(output), do: {:ok, output}
  end

  defmodule CountedChild do
    @behaviour Jido.Flow

    @impl true
    def flow do
      send(self(), {:materialized, __MODULE__})

      Jido.Flow.new!(%{
        name: "counted_child",
        components: [%{kind: :subflow, name: "leaf", flow: CountedLeaf, params: %{}}],
        output: Ref.result("leaf")
      })
    end

    @impl true
    def validate_params(params), do: {:ok, params}

    @impl true
    def validate_output(output), do: {:ok, output}
  end

  defmodule RecursiveChild do
    @behaviour Jido.Flow

    @impl true
    def flow do
      Flow.new!(%{
        name: "recursive_child",
        components: [%{kind: :subflow, name: "child", flow: __MODULE__}],
        output: Ref.result("child")
      })
    end

    @impl true
    def validate_params(params), do: {:ok, params}

    @impl true
    def validate_output(output), do: {:ok, output}
  end

  test "one compile materializes each shared child module once at every nesting depth" do
    flow =
      flow!(
        "shared_children",
        [
          %{kind: :subflow, name: "left", flow: CountedChild, params: %{}},
          %{kind: :subflow, name: "right", flow: CountedChild, params: %{}}
        ],
        Ref.result("right")
      )

    for _operation <- 1..2 do
      assert {:ok, %Workflow{}} = Exec.compile(flow, [])
      assert_received {:materialized, CountedChild}
      assert_received {:materialized, CountedLeaf}
      refute_received {:materialized, _module}
    end
  end

  test "root and child Flow definitions share one compile operation" do
    assert {:ok, %Workflow{}} = Exec.compile(CountedChild, [])
    assert_received {:materialized, CountedChild}
    assert_received {:materialized, CountedLeaf}
    refute_received {:materialized, _module}
  end

  test "definition reuse preserves recursive child rejection" do
    assert {:error, error} = Exec.compile(RecursiveChild, [])
    assert error.message == "recursive nested Flow cycle"
    assert error.details.module_stack == [RecursiveChild, RecursiveChild]
  end

  defp flow!(name, components, output) do
    Flow.new!(%{name: name, components: components, output: output})
  end
end
