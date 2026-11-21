defmodule Jido.Examples.Operations.ConfiguredProviderAgent do
  @moduledoc "Runs one AI request with an inference client supplied by runtime context."

  use Jido.AI.Agent, name: "operations_configured_provider_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "offline:configured-provider"
      instructions "Return one short offline answer."

      limits do
        model_calls 2
        retries 0
        elapsed_ms(5_000)
      end
    end
  end
end

defmodule Jido.Examples.Operations.ProviderConfiguration do
  @moduledoc "Keeps inference-client configuration outside Agent state and request data."

  alias Jido.Examples.Operations.ConfiguredProviderAgent

  @doc "Runs one pure Turn with the application-selected inference client."
  def ask(client, input) when is_atom(client) and is_binary(input) do
    agent =
      ConfiguredProviderAgent.instantiate!(id: "configured-provider-#{System.unique_integer([:positive])}")

    request = ConfiguredProviderAgent.request_signal!(%{input: input})

    ConfiguredProviderAgent.cmd(agent, request, context: %{jido_ai_inference_client: client})
  end
end
