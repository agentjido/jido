defmodule Jido.Examples.StableAddress do
  @moduledoc """
  A conversation Agent addressed through a stable `Jido.Agent.Address`.

  Each operation resolves the current Agent Server process. Application code
  keeps the Address and does not keep a process identifier.
  """
  use Jido.Agent, name: "runtime_stable_address"

  alias Jido.Agent.Address
  alias Jido.Signal

  state do
    schema Jido.Joi.object(%{messages: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/examples/runtime/stable_address"

    route "examples.runtime.stable_address.append", as: :append do
      action %{text: text},
        schema: Jido.Joi.object(%{text: Jido.Joi.string()}),
        context: context do
        {:ok, %{context.agent_state | messages: context.agent_state.messages ++ [text]}}
      end
    end
  end

  @spec append(Address.t(), atom(), String.t()) ::
          {:ok, Jido.AgentServer.TurnResult.t()} | {:error, term()}
  def append(%Address{} = address, instance, text) when is_atom(instance) and is_binary(text) do
    signal =
      Signal.new!(
        "examples.runtime.stable_address.append",
        %{text: text},
        source: "/examples/runtime/stable_address"
      )

    Jido.call(instance, address, signal)
  end
end
