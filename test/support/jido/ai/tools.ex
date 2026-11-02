defmodule Jido.AITest.Tools.Add do
  use Jido.Action,
    id: "jido.ai/examples/tools/add",
    name: "add",
    description: "Add two numbers.",
    schema: Zoi.object(%{left: Zoi.number(), right: Zoi.number()}),
    output_schema: Zoi.object(%{value: Zoi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left + right}}
end

defmodule Jido.AITest.Tools.AddFlow do
  use Jido.Flow,
    id: "jido.ai/examples/tools/add-flow",
    vsn: 1,
    name: "add_flow",
    description: "Add two numbers through a Flow.",
    schema: Zoi.object(%{left: Zoi.number(), right: Zoi.number()}),
    output_schema: Zoi.object(%{value: Zoi.number()})

  flow do
    step "add", action: Jido.AITest.Tools.Add, params: input([])
    output result("add")
  end
end

defmodule Jido.AITest.Tools.Multiply do
  use Jido.Action,
    id: "jido.ai/examples/tools/multiply",
    name: "multiply",
    description: "Multiply two numbers.",
    schema: Zoi.object(%{left: Zoi.number(), right: Zoi.number()}),
    output_schema: Zoi.object(%{value: Zoi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left * right}}
end

defmodule Jido.AITest.Tools.LargeOutput do
  use Jido.Action,
    id: "jido.ai/examples/tools/large-output",
    name: "large_output",
    description: "Return a large local value.",
    schema: Zoi.object(%{}),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(_params, _context), do: {:ok, %{content: String.duplicate("local-only-", 1_000)}}
end

defmodule Jido.AITest.Tools.ImageResult do
  use Jido.Action,
    id: "jido.ai/examples/tools/image-result",
    name: "image_result",
    description: "Return an image as model content.",
    schema: Zoi.object(%{}),
    output_schema: ReqLLM.ToolResult.schema()

  @impl Jido.Action
  def run(_params, _context) do
    {:ok,
     Jido.Action.Output.preserve(%ReqLLM.ToolResult{
       output: %{asset_id: "asset-123"},
       content: [
         ReqLLM.Message.ContentPart.text("The generated chart is attached."),
         ReqLLM.Message.ContentPart.image_url("https://example.com/chart.png")
       ],
       metadata: %{source: "chart-service"}
     })}
  end
end

defmodule Jido.AITest.DynamicToolSource do
  @behaviour Jido.AI.ToolSource

  @impl Jido.AI.ToolSource
  def list_tools(_config, _context) do
    {:ok,
     [
       %{
         name: "dynamic_echo",
         description: "Echo text through a runtime tool source.",
         parameter_schema: %{
           "type" => "object",
           "properties" => %{"text" => %{"type" => "string"}},
           "required" => ["text"],
           "additionalProperties" => false
         }
       }
     ]}
  end

  @impl Jido.AI.ToolSource
  def run_tool(%{name: "dynamic_echo", arguments: arguments}, config, _context) do
    prefix = Map.get(config, :prefix, Map.get(config, "prefix", "dynamic"))
    text = Map.get(arguments, :text, Map.get(arguments, "text"))
    {:ok, %{echo: "#{prefix}:#{text}"}}
  end

  def run_tool(call, _config, _context), do: {:error, {:unknown_dynamic_tool, call.name}}
end

defmodule Jido.AITest.SimpleAgent do
  use Jido.AI.Agent,
    name: "jido_ai_simple_agent",
    description: "Answer one request with guardrails and multiple tools",
    id: "jido.ai/agents/simple",
    vsn: 3

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action Jido.AITest.Tools.Add
      action Jido.AITest.Tools.Multiply
    end
  end
end

defmodule Jido.AITest.FlowToolAgent do
  use Jido.AI.Agent,
    name: "jido_ai_flow_tool_agent",
    description: "Execute one Flow as a model tool",
    id: "jido.ai/agents/flow-tool",
    vsn: 1

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      flow Jido.AITest.Tools.AddFlow
    end
  end
end

defmodule Jido.AITest.ConfiguredAgent do
  use Jido.AI.Agent,
    name: "jido_ai_configured_agent",
    description: "Use compile-time defaults for the canonical ReAct graph",
    id: "jido.ai/agents/configured",
    vsn: 1

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      instructions "Answer as a careful support specialist."
      model "anthropic:claude-sonnet-4-5"
      fallback_models ["openai:gpt-5-mini"]

      limits do
        model_calls 6
        tool_rounds 3
        tool_calls 6
        retries 1
      end

      context do
        max_messages 32
        max_bytes 100_000
      end

      prompt_cache do
        enabled true
        ttl "5m"
      end
    end

    tools do
      action Jido.AITest.Tools.Add
      action Jido.AITest.Tools.Multiply
    end
  end
end

defmodule Jido.AITest.ChainOfThoughtAgent do
  use Jido.AI.Agent,
    name: "jido_ai_chain_of_thought_agent",
    description: "Solve one request with a variable-length numbered reasoning chain",
    id: "jido.ai/agents/chain-of-thought",
    vsn: 1

  ai do
    reasoning Jido.AI.Reasoning.ChainOfThought
  end
end

defmodule Jido.AITest.LargeOutputAgent do
  use Jido.AI.Agent,
    name: "jido_ai_large_output_agent",
    description: "Test bounded tool result projection",
    id: "jido.ai/agents/large-output",
    vsn: 1

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action Jido.AITest.Tools.LargeOutput
    end
  end
end

defmodule Jido.AITest.ContentPartAgent do
  use Jido.AI.Agent,
    name: "jido_ai_content_part_agent",
    description: "Test model-visible tool content parts",
    id: "jido.ai/agents/content-part",
    vsn: 1

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action Jido.AITest.Tools.ImageResult
    end
  end
end
