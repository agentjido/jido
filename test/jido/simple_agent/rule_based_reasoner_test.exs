defmodule JidoTest.SimpleAgent.RuleBasedReasonerTest do
  use ExUnit.Case, async: true

  alias Jido.SimpleAgent.RuleBasedReasoner
  alias Jido.Skills.Arithmetic.Actions.Eval

  describe "math detection" do
    test "detects 'what is' mathematical expressions" do
      assert {:tool_call, Eval, %{expression: "2 + 3"}} =
               RuleBasedReasoner.reason("what is 2 + 3", %{})

      assert {:tool_call, Eval, %{expression: "5 * 7"}} =
               RuleBasedReasoner.reason("What is 5 * 7?", %{})

      assert {:tool_call, Eval, %{expression: "10 - 4"}} =
               RuleBasedReasoner.reason("WHAT IS 10 - 4", %{})
    end

    test "detects 'calculate' expressions" do
      assert {:tool_call, Eval, %{expression: "15 / 3"}} =
               RuleBasedReasoner.reason("calculate 15 / 3", %{})

      assert {:tool_call, Eval, %{expression: "2^8"}} =
               RuleBasedReasoner.reason("Calculate 2^8", %{})
    end

    test "detects 'compute' expressions" do
      assert {:tool_call, Eval, %{expression: "sqrt(16)"}} =
               RuleBasedReasoner.reason("compute sqrt(16)", %{})

      assert {:tool_call, Eval, %{expression: "abs(-5)"}} =
               RuleBasedReasoner.reason("Compute abs(-5)", %{})
    end

    test "detects 'solve' expressions" do
      assert {:tool_call, Eval, %{expression: "3 * (2 + 4)"}} =
               RuleBasedReasoner.reason("solve 3 * (2 + 4)", %{})

      assert {:tool_call, Eval, %{expression: "log(100)"}} =
               RuleBasedReasoner.reason("Solve log(100)?", %{})
    end

    test "trims whitespace from expressions" do
      assert {:tool_call, Eval, %{expression: "1 + 1"}} =
               RuleBasedReasoner.reason("what is   1 + 1   ?", %{})
    end

    test "handles complex mathematical expressions" do
      assert {:tool_call, Eval, %{expression: "(2 + 3) * (4 - 1) / 5"}} =
               RuleBasedReasoner.reason("what is (2 + 3) * (4 - 1) / 5", %{})
    end
  end

  describe "text response patterns" do
    test "responds to greetings" do
      assert {:respond, "Hello! How can I help you?"} =
               RuleBasedReasoner.reason("hi", %{})

      assert {:respond, "Hello! How can I help you?"} =
               RuleBasedReasoner.reason("Hello", %{})

      assert {:respond, "Hello! How can I help you?"} =
               RuleBasedReasoner.reason("Hey!", %{})

      assert {:respond, "Hello! How can I help you?"} =
               RuleBasedReasoner.reason("HI.", %{})
    end

    test "responds to help requests" do
      assert {:respond, "I can help with math calculations and answer basic questions."} =
               RuleBasedReasoner.reason("help", %{})

      assert {:respond, "I can help with math calculations and answer basic questions."} =
               RuleBasedReasoner.reason("I need help", %{})

      assert {:respond, "I can help with math calculations and answer basic questions."} =
               RuleBasedReasoner.reason("Can you help me?", %{})
    end

    test "responds to thanks" do
      assert {:respond, "You're welcome!"} =
               RuleBasedReasoner.reason("thank you", %{})

      assert {:respond, "You're welcome!"} =
               RuleBasedReasoner.reason("thanks", %{})

      assert {:respond, "You're welcome!"} =
               RuleBasedReasoner.reason("thx", %{})
    end

    test "responds to goodbye" do
      assert {:respond, "Goodbye! Have a great day!"} =
               RuleBasedReasoner.reason("bye", %{})

      assert {:respond, "Goodbye! Have a great day!"} =
               RuleBasedReasoner.reason("goodbye", %{})

      assert {:respond, "Goodbye! Have a great day!"} =
               RuleBasedReasoner.reason("see you later", %{})
    end

    test "responds to name questions" do
      assert {:respond, "I'm a Jido SimpleAgent!"} =
               RuleBasedReasoner.reason("what is your name", %{})

      assert {:respond, "I'm a Jido SimpleAgent!"} =
               RuleBasedReasoner.reason("what's your name?", %{})

      assert {:respond, "I'm a Jido SimpleAgent!"} =
               RuleBasedReasoner.reason("What name", %{})
    end

    test "responds to time questions" do
      assert {:respond,
              "I don't have access to the current time, but I can help with calculations!"} =
               RuleBasedReasoner.reason("what time is it", %{})

      assert {:respond,
              "I don't have access to the current time, but I can help with calculations!"} =
               RuleBasedReasoner.reason("What time?", %{})
    end

    test "responds to weather questions" do
      assert {:respond, "I can't check the weather, but I'm great with math!"} =
               RuleBasedReasoner.reason("weather", %{})

      assert {:respond, "I can't check the weather, but I'm great with math!"} =
               RuleBasedReasoner.reason("What's the weather like?", %{})
    end

    test "responds to status questions" do
      assert {:respond, "I'm running smoothly and ready to help!"} =
               RuleBasedReasoner.reason("how are you", %{})

      assert {:respond, "I'm running smoothly and ready to help!"} =
               RuleBasedReasoner.reason("status", %{})

      assert {:respond, "I'm running smoothly and ready to help!"} =
               RuleBasedReasoner.reason("How are you doing?", %{})
    end

    test "responds to capability questions" do
      assert {:respond, "I can perform mathematical calculations and have basic conversations."} =
               RuleBasedReasoner.reason("what can you do", %{})

      assert {:respond, "I can perform mathematical calculations and have basic conversations."} =
               RuleBasedReasoner.reason("what you do", %{})
    end

    test "provides default fallback response" do
      assert {:respond, "I'm not sure about that, but I can help with math calculations!"} =
               RuleBasedReasoner.reason("random question", %{})

      assert {:respond, "I'm not sure about that, but I can help with math calculations!"} =
               RuleBasedReasoner.reason("tell me about quantum physics", %{})

      assert {:respond, "I'm not sure about that, but I can help with math calculations!"} =
               RuleBasedReasoner.reason("", %{})
    end
  end

  describe "edge cases" do
    test "handles empty and whitespace-only messages" do
      assert {:respond, "I'm not sure about that, but I can help with math calculations!"} =
               RuleBasedReasoner.reason("", %{})

      assert {:respond, "I'm not sure about that, but I can help with math calculations!"} =
               RuleBasedReasoner.reason("   ", %{})

      assert {:respond, "I'm not sure about that, but I can help with math calculations!"} =
               RuleBasedReasoner.reason("\n\t", %{})
    end

    test "handles mixed case consistently" do
      assert {:respond, "Hello! How can I help you?"} =
               RuleBasedReasoner.reason("HeLLo", %{})

      assert {:tool_call, Eval, %{expression: "2+2"}} =
               RuleBasedReasoner.reason("WHAT IS 2+2", %{})
    end

    test "prioritizes math detection over text patterns" do
      # Even if message contains greeting words, math detection takes precedence
      assert {:tool_call, Eval, %{expression: "hello + world"}} =
               RuleBasedReasoner.reason("what is hello + world", %{})
    end

    test "math detection handles expressions with no spaces" do
      assert {:tool_call, Eval, %{expression: "2+3*4"}} =
               RuleBasedReasoner.reason("calculate 2+3*4", %{})
    end

    test "ignores memory parameter" do
      memory = %{messages: ["old", "messages"], tool_results: %{}}

      assert {:respond, "Hello! How can I help you?"} =
               RuleBasedReasoner.reason("hi", memory)

      assert {:tool_call, Eval, %{expression: "5+5"}} =
               RuleBasedReasoner.reason("what is 5+5", memory)
    end
  end
end
