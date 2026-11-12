defmodule Jido.Examples.StableReference do
  @moduledoc """
  A conversation Agent addressed through a stable `Jido.Agent.Ref`.

  Each operation resolves the current Agent Server process. Application code
  keeps the Ref and does not keep a process identifier.
  """
  use Jido.Agent, name: "runtime_stable_reference"

  alias Jido.Agent.Ref
  alias Jido.Signal

  state do
    schema Jido.Joi.object(%{messages: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/examples/runtime/stable_reference"

    route "examples.runtime.stable_reference.append", as: :append do
      action %{text: text},
        schema: Jido.Joi.object(%{text: Jido.Joi.string()}),
        context: context do
        {:ok, %{context.agent_state | messages: context.agent_state.messages ++ [text]}}
      end
    end
  end

  @spec append(Ref.t(), atom(), String.t()) ::
          {:ok, Jido.AgentServer.TurnResult.t()} | {:error, term()}
  def append(%Ref{} = ref, instance, text) when is_atom(instance) and is_binary(text) do
    signal =
      Signal.new!(
        "examples.runtime.stable_reference.append",
        %{text: text},
        source: "/examples/runtime/stable_reference"
      )

    Jido.call(instance, ref, signal)
  end
end
