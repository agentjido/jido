defmodule Jido.Examples.AI.BrowserReleaseNotes do
  @moduledoc "Reads release notes through a browser tool configured by the host."

  use Jido.AI.Agent, name: "example_browser_release_notes"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "offline:release-notes"
      instructions "Read the requested release note. Include its source URL in your answer."

      limits do
        model_calls 2
        tool_rounds 1
        retries 0
        elapsed_ms(5_000)
      end
    end

    tools do
      browser do
        allow("docs.example", path_prefix: "/jido/")
        expose([:fetch])
      end
    end
  end

  @doc "Reads one requested page with the inference client supplied by the caller."
  def read(url, client) do
    agent = instantiate!(id: "release-note-reader")
    signal = request_signal!(%{input: url})

    with {:ok, _agent, [%Jido.Agent.Directive.Reply{signal: %{data: answer}}]} <-
           cmd(agent, signal, context: %{jido_ai_inference_client: client}) do
      {:ok, answer}
    end
  end
end
