defmodule Jido.Examples.AI.RequestModes.Agent do
  @moduledoc "A complete AI Agent used with AgentServer call, cast, and submit modes."

  use Jido.AI.Agent, name: "request_modes_example"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Answer in one short sentence."
    end
  end
end

defmodule Jido.Examples.AI.RequestModes do
  @moduledoc "Starts the request-mode Agent in a Jido instance."

  alias Jido.Examples.AI.RequestModes.Agent

  @doc "Starts one supervised request-mode Agent."
  def start(jido, opts \\ []), do: Jido.start_agent(jido, Agent, opts)
end
