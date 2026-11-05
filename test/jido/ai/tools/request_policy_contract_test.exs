defmodule Jido.AI.Tools.RequestPolicyContractTest do
  use Covenant.Case, component: "jido_ai.tools", async: true

  alias Jido.AI.{RequestPolicy, Toolset}
  alias Jido.Test.AI.Tools

  defmodule ToolThenAnswer do
    @moduledoc false
    @behaviour Jido.AI.InferenceClient

    @handled [generate_text: 3]

    @impl true
    def generate_text(model, context, _options) do
      called? = Enum.any?(ReqLLM.Context.to_list(context), &(&1.role == :tool))

      message =
        if called? do
          ReqLLM.Context.assistant("Done.")
        else
          call = ReqLLM.ToolCall.new("call-1", "add", ~s({"left":1,"right":2}))
          ReqLLM.Context.assistant("", tool_calls: [call])
        end

      {:ok,
       %ReqLLM.Response{
         id: "response-#{System.unique_integer([:positive])}",
         model: model,
         context: ReqLLM.Context.append(context, message),
         message: message,
         stream?: false
       }}
    end

    for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks),
        {name, arity} not in @handled do
      @impl true
      def unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))),
        do: {:error, :not_supported}
    end
  end

  defmodule ReviewedAgent do
    @moduledoc false
    use Jido.AI.Agent, name: "request_policy_reviewed"

    ai do
      reasoning Jido.AI.Reasoning.ReAct do
        tool_policy do
          review(["add"])
        end
      end

      tools do
        action Tools.Add
        action Tools.Multiply
      end
    end
  end

  defmodule ReviewAllAgent do
    @moduledoc false
    use Jido.AI.Agent, name: "request_policy_review_all"

    ai do
      reasoning Jido.AI.Reasoning.ReAct do
        review_tools(true)
      end

      tools do
        action Tools.Add
      end
    end
  end

  defmodule BoundedAgent do
    @moduledoc false
    use Jido.AI.Agent, name: "request_policy_bounded"

    ai do
      reasoning Jido.AI.Reasoning.ReAct do
        instructions "Agent instructions."

        limits do
          model_calls 6
          tool_rounds 6
          elapsed_ms(30_000)
          total_tokens(100)
        end
      end
    end
  end

  defmodule OpenAgent do
    @moduledoc false
    use Jido.AI.Agent, name: "request_policy_open"

    ai do
      reasoning Jido.AI.Reasoning.ReAct
    end
  end

  defp ask(module, data) do
    agent = module.instantiate!(id: "request-policy-#{System.unique_integer([:positive])}")

    {:ok, _agent, [%{signal: reply}]} =
      module.cmd(agent, module.request_signal!(data), context: %{jido_ai_inference_client: ToolThenAnswer})

    reply.data
  end

  describe "a request against Agent review" do
    @tag obligation: "jido_ai.tools.I3"
    test "keeps review through an empty or unrelated tool_policy" do
      assert %{status: :blocked, reason_code: :review, tool_rounds: 0} = ask(ReviewedAgent, %{input: "go"})

      for tool_policy <- [%{}, %{review: []}, %{visible: ["add"]}, %{reason: "skip it"}] do
        assert %{status: :blocked, reason_code: :review, tool_rounds: 0} =
                 ask(ReviewedAgent, %{input: "go", tool_policy: tool_policy})
      end
    end

    @tag obligation: "jido_ai.tools.I3"
    test "cannot use string keys to get around the policy" do
      assert {:error, %{details: %{phase: :flow_input}}} =
               ReviewedAgent.cmd(
                 ReviewedAgent.instantiate!(id: "request-policy-string-keys"),
                 ReviewedAgent.request_signal!(%{:input => "go", "tool_policy" => %{}}),
                 context: %{jido_ai_inference_client: ToolThenAnswer}
               )

      assert {:error, %{details: %{phase: :flow_input}}} =
               BoundedAgent.cmd(
                 BoundedAgent.instantiate!(id: "request-policy-string-limits"),
                 BoundedAgent.request_signal!(%{input: "go", limits: %{"model_calls" => 16}}),
                 context: %{jido_ai_inference_client: ToolThenAnswer}
               )
    end

    @tag obligation: "jido_ai.tools.I3"
    test "keeps review_tools set on the Agent" do
      assert %{status: :blocked, reason_code: :review} =
               ask(ReviewAllAgent, %{input: "go", review_tools: false})
    end

    @tag obligation: "jido_ai.tools.I3"
    test "can hide a reviewed tool" do
      assert {:ok, %{params: %{tool_policy: policy}}} =
               ReviewedAgent.preflight(%{input: "go", tool_policy: %{hidden: ["add"]}})

      assert policy.review == []
      assert policy.hidden == ["add"]
    end

    @tag obligation: "jido_ai.tools.I3"
    test "can add review, and preflight reports the result" do
      assert {:ok, %{params: %{tool_policy: policy}}} =
               ReviewedAgent.preflight(%{input: "go", tool_policy: %{review: ["multiply"]}})

      assert policy.review == ["add", "multiply"]
    end
  end

  describe "a request against Agent limits" do
    @tag obligation: "jido_ai.tools.I3"
    test "keeps limits it leaves out" do
      assert {:ok, %{params: %{limits: limits}}} =
               BoundedAgent.preflight(%{input: "go", limits: %{model_calls: 2}})

      assert %{model_calls: 2, tool_rounds: 6, elapsed_ms: 30_000, total_tokens: 100} = limits
    end

    @tag obligation: "jido_ai.tools.I3"
    test "cannot raise or remove a limit" do
      assert {:ok, %{params: %{limits: limits}}} =
               BoundedAgent.preflight(%{
                 input: "go",
                 limits: %{model_calls: 16, tool_rounds: 8, total_tokens: nil}
               })

      assert %{model_calls: 6, tool_rounds: 6, total_tokens: 100} = limits
    end

    @tag obligation: "jido_ai.tools.I3"
    test "reaches the running request" do
      reply = ask(BoundedAgent, %{input: "go", limits: %{model_calls: 16, total_tokens: nil}})

      assert %{model_calls: 6, tool_rounds: 6, elapsed_ms: 30_000, total_tokens: 100} = reply.budget.limits

      reply = ask(BoundedAgent, %{input: "go", limits: %{model_calls: 2}})

      assert %{model_calls: 2, tool_rounds: 6, elapsed_ms: 30_000} = reply.budget.limits
    end

    @tag obligation: "jido_ai.tools.I3"
    test "stays free when the Agent sets none" do
      assert {:ok, %{params: %{limits: %{model_calls: 16, tool_rounds: 8}}}} =
               OpenAgent.preflight(%{input: "go", limits: %{model_calls: 16, tool_rounds: 8}})
    end
  end

  describe "a request against Agent instructions" do
    @tag obligation: "jido_ai.tools.I3"
    test "cannot replace them" do
      assert {:ok, %{params: %{instructions: "Agent instructions."}}} =
               BoundedAgent.preflight(%{input: "go", instructions: "Request instructions."})

      assert RequestPolicy.narrow(
               %{instructions: "Request instructions."},
               %{instructions: "Agent instructions."},
               %{instructions: "Request instructions."}
             ) == %{instructions: "Agent instructions."}
    end

    @tag obligation: "jido_ai.tools.I3"
    test "can set them when the Agent sets none" do
      assert {:ok, %{params: %{instructions: "Request instructions."}}} =
               OpenAgent.preflight(%{input: "go", instructions: "Request instructions."})
    end
  end

  describe "requirement values" do
    @tag obligation: "jido_ai.tools.I3"
    test "reject :per_turn with the normal invalid-option error" do
      assert {:error, error} = OpenAgent.preflight(%{input: "go", tool_policy: %{requirement: :per_turn}})

      assert Exception.message(error) =~ "invalid enum value"
      assert Exception.message(error) =~ "tool_policy.requirement"
      assert {:error, {:invalid_tool_requirement, :per_turn}} = Toolset.select([Tools.Add], %{requirement: :per_turn})
    end
  end

  describe "narrow_policy/2" do
    @tag obligation: "jido_ai.tools.I3"
    test "is unchanged by narrowing a policy with itself" do
      policy = %{visible: ["add"], hidden: ["multiply"], review: ["add"], requirement: :required, reason: "why"}

      assert Toolset.narrow_policy(policy, policy) == policy
    end

    @tag obligation: "jido_ai.tools.I3"
    test "never widens visibility" do
      tools = [Tools.Add, Tools.Multiply]

      agent = %{visible: ["add"]}
      assert {:ok, %{visible: ["add"]}} = Toolset.select(tools, Toolset.narrow_policy(agent, %{}))

      assert {:ok, %{visible: ["add"]}} =
               Toolset.select(tools, Toolset.narrow_policy(agent, %{visible: ["add", "multiply"]}))

      assert {:ok, %{visible: []}} =
               Toolset.select(tools, Toolset.narrow_policy(agent, %{visible: ["multiply"]}))

      assert {:ok, %{visible: ["add"]}} =
               Toolset.select(tools, Toolset.narrow_policy(%{hidden: ["multiply"]}, %{hidden: []}))
    end

    @tag obligation: "jido_ai.tools.I3"
    test "keeps a requirement that the Agent sets" do
      assert %{requirement: :required} = Toolset.narrow_policy(%{requirement: :required}, %{requirement: :optional})
      assert %{requirement: :required} = Toolset.narrow_policy(%{requirement: :required}, %{requirement: :disabled})
      assert %{requirement: :disabled} = Toolset.narrow_policy(%{requirement: :disabled}, %{requirement: :required})
      assert %{requirement: :disabled} = Toolset.narrow_policy(%{requirement: :optional}, %{requirement: :disabled})
    end
  end
end
