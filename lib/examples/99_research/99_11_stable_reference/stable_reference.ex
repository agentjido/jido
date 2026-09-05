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
  An application reference resolved through public lookup on each call.
  Bindings map a stable namespace to a current Jido instance. The example
  supplies this reference; core does not yet supply Jido.Agent.Ref.
  """
  @schema Zoi.struct(__MODULE__, %{
            namespace: Zoi.string(),
            partition: Zoi.string(),
            id: Zoi.string()
          })
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema

  def append(ref, bindings, text) do
    instance = Map.fetch!(bindings, ref.namespace)

    case Jido.whereis_agent(instance, ref.id, partition: ref.partition) do
      nil -> {:error, :not_found}
      pid -> __MODULE__.Conversation.append(pid, text)
    end
  end
end
