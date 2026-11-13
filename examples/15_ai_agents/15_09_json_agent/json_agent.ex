unless Code.ensure_loaded?(Jido.Examples.AI.Tools.Add) do
  Code.require_file("../../support/arithmetic_tools.ex", __DIR__)
end

defmodule Jido.Examples.AI.JSONSimpleAgent do
  @moduledoc false

  use Jido.AI.Agent,
    name: "jido_ai_simple_agent",
    description: "Answer one request with guardrails and multiple tools",
    id: "jido.ai/agents/simple",
    vsn: 3

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action Jido.Examples.AI.Tools.Add
      action Jido.Examples.AI.Tools.Multiply
    end
  end
end

defmodule Jido.Examples.AI.JSONAgent do
  @moduledoc """
  Stores and loads the graph-first SimpleAgent with `Jido.Catalog` and `Jido.Codec`.

  The AI DSL lowers through the AI Agent Plugin. The normal Agent codec
  stores the Plugin data and trusted executable references.
  """

  alias Jido.AI.Reasoning.ReAct
  alias Jido.Catalog
  alias Jido.Examples.AI.JSONSimpleAgent, as: SimpleAgent

  @request_type "jido.ai.request"
  @fixture Path.join(__DIR__, "fixtures/agent.json")

  @doc "Returns the compiled graph-first Agent definition."
  def definition, do: SimpleAgent.definition()

  @doc "Returns the allowlist used to encode and decode the Agent document."
  def registry do
    Catalog.from_targets!(__MODULE__, :jido, %{
      {"jido.ai/agents/simple", 3} => SimpleAgent,
      {"jido.ai/agent", 1} => Jido.AI.Agent.Plugin,
      {"jido.ai/reasoning/react", 1} => ReAct,
      {"jido.ai/examples/tools/add", 1} => Jido.Examples.AI.Tools.Add,
      {"jido.ai/examples/tools/multiply", 1} => Jido.Examples.AI.Tools.Multiply,
      {"jido.ai/schemas/simple-agent-state", 1} => definition().schema
    })
  end

  @doc "Encodes the SimpleAgent definition with the normal Agent codec."
  def encode_json do
    Jido.Codec.encode_json(definition(), catalog: registry())
  end

  @doc "Reads the stored SimpleAgent document."
  def fixture_json, do: File.read!(@fixture)

  @doc "Decodes and validates the stored SimpleAgent definition."
  def import do
    {:ok, codec} = Jido.Codec.Encoder.codec(definition())
    Jido.Codec.decode_json(fixture_json(), catalog: registry(), codec: codec)
  end

  @doc "Builds the standard AI request Signal for an imported definition."
  def request_signal!(definition, params) do
    Jido.Signal.new!(@request_type, params, source: definition.signal_source)
  end
end
