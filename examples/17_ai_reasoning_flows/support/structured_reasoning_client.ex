defmodule Jido.Examples.AI.Reasoning.StructuredReasoningClient do
  @moduledoc """
  Returns deterministic structured objects for the reasoning comparison lessons.

  The client selects a fixture from the application-owned `:offline_strategy`
  request option and the public output schema for the current model call.
  """

  @behaviour Jido.AI.InferenceClient

  alias Jido.Examples.Support.OfflineInferenceClient, as: Offline

  @impl true
  def generate_text(model, context, options) do
    case Keyword.fetch(options, :offline_strategy) do
      {:ok, strategy} ->
        schema = options |> Keyword.fetch!(:output) |> Map.fetch!(:schema)
        object = fixture(strategy, properties(schema))
        Offline.generate_text(model, context, Keyword.put(options, :offline_object, object))

      :error ->
        Offline.generate_text(model, context, options)
    end
  end

  @impl true
  defdelegate stream_text(model, context, options), to: Offline

  @impl true
  def generate_object(model, context, schema, options) do
    strategy = Keyword.fetch!(options, :offline_strategy)
    object = fixture(strategy, properties(schema))
    Offline.generate_object(model, context, schema, Keyword.put(options, :offline_object, object))
  end

  @impl true
  defdelegate stream_object(model, context, schema, options), to: Offline

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

  defp fixture(:tree, %{"thoughts" => %{"items" => %{"properties" => item_properties}}}) do
    thoughts = [
      %{"content" => "weak"},
      %{"content" => "strong"},
      %{"content" => "medium"}
    ]

    if Map.has_key?(item_properties, "score") do
      %{
        "thoughts" => [
          %{"content" => "weak", "score" => 0.1},
          %{"content" => "strong", "score" => 0.9},
          %{"content" => "medium", "score" => 0.6}
        ]
      }
    else
      %{"thoughts" => thoughts}
    end
  end

  defp fixture(:tree, %{"answer" => _schema}), do: %{"answer" => "selected answer"}

  defp fixture(:graph, %{"nodes" => _nodes, "edges" => _edges}) do
    %{
      "nodes" => [
        %{"id" => "facts", "content" => "collect facts"},
        %{"id" => "answer", "content" => "form answer"}
      ],
      "edges" => [
        %{"from" => "facts", "to" => "answer", "relationship" => "supports"}
      ]
    }
  end

  defp fixture(:graph, %{"answer" => _schema}), do: %{"answer" => "graph answer"}
  defp fixture(:trm, %{"draft" => _schema}), do: %{"draft" => "initial answer"}
  defp fixture(:trm, %{"critique" => _schema}), do: %{"critique" => "add evidence"}
  defp fixture(:trm, %{"answer" => _schema}), do: %{"answer" => "revised answer"}

  defp fixture(:adaptive, %{"drafts" => _drafts, "answer" => _answer}) do
    %{"drafts" => ["identify", "check"], "answer" => "adaptive answer"}
  end

  defp properties(schema), do: Map.fetch!(schema, "properties")
end
