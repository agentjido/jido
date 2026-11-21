defmodule Jido.Examples.AI.OfflineTesting.Agent do
  @moduledoc "Runs the same deterministic AI behavior in pure and hosted modes."

  use Jido.AI.Agent, name: "examples_ai_offline_testing_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "offline:scripted"
      instructions "Return the scripted result."

      limits do
        model_calls 1
        retries 0
        elapsed_ms(5_000)
      end
    end
  end
end

defmodule Jido.Examples.AI.OfflineTesting.ScriptedClient do
  @moduledoc "Returns one scripted response or one scripted error without global mocks."

  @behaviour Jido.AI.InferenceClient

  alias Jido.Examples.Support.OfflineInferenceClient, as: Offline

  @impl true
  def generate_text(model, context, options) do
    case Keyword.get(options, :offline_error) do
      nil -> Offline.generate_text(model, context, options)
      reason -> {:error, reason}
    end
  end

  @impl true
  defdelegate stream_text(model, context, options), to: Offline

  @impl true
  defdelegate generate_object(model, context, schema, options), to: Offline

  @impl true
  defdelegate generate_image(model, prompt, options), to: Offline

  @impl true
  defdelegate stream_image(model, prompt, options), to: Offline

  @impl true
  defdelegate generate_video(model, content, options), to: Offline

  @impl true
  defdelegate query_video(model, task_id, options), to: Offline

  @impl true
  defdelegate wait_video(model, task_id, options), to: Offline

  @impl true
  defdelegate retrieve_video_file(model, file_id, options), to: Offline

  @impl true
  defdelegate upload_video_file(model, file, options), to: Offline

  @impl true
  defdelegate stream_object(model, context, schema, options), to: Offline

  @impl true
  defdelegate embed(model, input, options), to: Offline

  @impl true
  defdelegate rerank(model, options), to: Offline

  @impl true
  defdelegate compact_context(model, context, options), to: Offline

  @impl true
  defdelegate evaluate(model, state, questions, options), to: Offline

  @impl true
  defdelegate evaluation_models(), to: Offline

  @impl true
  defdelegate ocr(model, document, options), to: Offline

  @impl true
  defdelegate ocr_file(model, path, options), to: Offline

  @impl true
  defdelegate transcribe(model, audio, options), to: Offline

  @impl true
  defdelegate transcribe_detailed(model, audio, options), to: Offline

  @impl true
  defdelegate speak(model, text, options), to: Offline

  @impl true
  defdelegate speak_detailed(model, text, options), to: Offline
end
