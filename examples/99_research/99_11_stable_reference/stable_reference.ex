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
  Resolves a stable Agent Ref through public lookup on each call.

  Application bindings map the Ref namespace to a current Jido instance.
  Runtime lookup still uses the current ID and partition API.
  """

  alias Jido.Agent.Ref

  @spec append(Ref.t(), %{required(String.t()) => atom()}, String.t()) ::
          {:ok, Jido.Agent.t()} | {:error, term()}
  def append(%Ref{} = ref, bindings, text) do
    instance = Map.fetch!(bindings, ref.namespace)

    case Jido.whereis_agent(instance, ref.id, partition: ref.partition) do
      nil -> {:error, :not_found}
      pid -> __MODULE__.Conversation.append(pid, text)
    end
  end
end
