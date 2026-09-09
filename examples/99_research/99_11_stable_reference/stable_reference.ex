defmodule Jido.Examples.StableReference.Conversation do
  @moduledoc false
  use Jido.Agent, name: "research_stable_conversation"

  agent do
    schema Zoi.object(%{messages: Zoi.list(Zoi.string()) |> Zoi.default([])})
  end

  routes do
    signal_source "/examples/stable-reference"

    route "conversation.append" do
      action %{text: text},
        name: "research_append",
        schema: Zoi.object(%{text: Zoi.string()}),
        context: context do
        {:ok, %{context.agent_state | messages: context.agent_state.messages ++ [text]}}
      end

      define :append, args: [:text]
    end
  end
end

defmodule Jido.Examples.StableReference do
  @moduledoc """
  Resolves a stable Agent Ref through the public Jido instance facade.

  The selected local Jido instance must bind the exact Ref namespace. Each
  operation resolves the current Agent Server PID and does not save that PID.
  """

  alias Jido.Agent.Ref
  alias Jido.Signal

  @spec append(Ref.t(), atom(), String.t()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def append(%Ref{} = ref, instance, text) when is_atom(instance) do
    signal =
      Signal.new!("conversation.append", %{text: text}, source: "/examples/stable-reference")

    Jido.call(instance, ref, signal)
  end
end
