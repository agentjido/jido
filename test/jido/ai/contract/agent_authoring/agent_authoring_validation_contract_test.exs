defmodule Jido.AI.Contract.AgentAuthoringValidationTest do
  use Covenant.Case, component: "jido_ai.agent_authoring", async: true

  @tag obligation: "jido_ai.agent_authoring.I2"
  test "the AI DSL rejects invalid block shapes and dynamic configuration" do
    assert_compile_error(~r/An Agent can define only one ai block/, """
    ai do
      reasoning Jido.AI.Reasoning.ReAct
    end

    ai do
      reasoning Jido.AI.Reasoning.ReAct
    end
    """)

    assert_compile_error(~r/An Agent can define at most one tools block/, """
    ai do
      reasoning Jido.AI.Reasoning.ReAct
      tools do
      end
      tools do
      end
    end
    """)

    assert_compile_error(~r/ai accepts only reasoning and tools declarations/, """
    ai do
      reasoning Jido.AI.Reasoning.ReAct
      unexpected true
    end
    """)

    assert_compile_error(~r/tools accepts only action or flow declarations/, """
    ai do
      reasoning Jido.AI.Reasoning.ReAct
      tools do
        unexpected Jido.AITest.Tools.Add
      end
    end
    """)

    assert_compile_error(~r/reasoning input cannot be a default/, """
    ai do
      reasoning Jido.AI.Reasoning.ReAct do
        input "reserved"
      end
    end
    """)

    assert_compile_error(~r/reasoning defines model more than once/, """
    ai do
      reasoning Jido.AI.Reasoning.ReAct do
        model "first:model"
        model "second:model"
      end
    end
    """)

    assert_compile_error(~r/model requires a compile-time literal value/, """
    value = "runtime:model"

    ai do
      reasoning Jido.AI.Reasoning.ReAct do
        model value
      end
    end
    """)

    assert_compile_error(~r/reasoning must reference a compiled Jido Flow module/, """
    ai do
      reasoning String
    end
    """)
  end

  defp assert_compile_error(pattern, body) do
    module = Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")

    source = """
    defmodule #{inspect(module)} do
      use Jido.AI.Agent, name: "#{module |> Module.split() |> List.last() |> Macro.underscore()}"
      #{body}
    end
    """

    assert_raise CompileError, pattern, fn -> Code.compile_string(source) end
  end
end
