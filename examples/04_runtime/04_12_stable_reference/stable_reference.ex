defmodule Jido.Examples.StableReference do
  @moduledoc """
  A conversation Agent addressed through a stable `Jido.Agent.Ref`.

  Each operation resolves the current Agent Server process. Application code
  keeps the Ref and does not keep a process identifier.
  """
  use Jido.Agent, name: "runtime_stable_reference"

  alias Jido.Agent.Ref
  alias Jido.Signal

  agent do
    schema Zoi.object(%{messages: Zoi.list(Zoi.string()) |> Zoi.default([])})
  end

  routes do
    signal_source "/examples/runtime/stable_reference"

    route "examples.runtime.stable_reference.append", as: :append do
      action %{text: text},
        schema: Zoi.object(%{text: Zoi.string()}),
        context: context do
        {:ok, %{context.agent_state | messages: context.agent_state.messages ++ [text]}}
      end
    end
  end

  @spec append(Ref.t(), atom(), String.t()) :: {:ok, Jido.Agent.t()} | {:error, term()}
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
