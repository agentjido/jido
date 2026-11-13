defmodule Jido.Examples.Patterns.LiveChat do
  @moduledoc "A Session-backed chat boundary for transient web clients."

  alias Jido.AgentServer
  alias Jido.Examples.Patterns.LiveChat.{Agent, OfflineClient}

  @doc "Creates or activates the durable conversation Agent."
  def ensure_conversation(instance, conversation_id) do
    with {:ok, ref} <- Jido.agent_ref(instance, conversation_id) do
      case Jido.activate_agent(instance, ref) do
        {:ok, _server} ->
          {:ok, ref}

        {:error, :not_found} ->
          with {:ok, ^ref} <- Jido.create_agent(instance, ref, Agent),
               {:ok, _server} <- Jido.activate_agent(instance, ref),
               do: {:ok, ref}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Runs one offline model Turn and dispatches stream Signals to the caller."
  def ask(instance, ref, text, opts \\ []) do
    input = multimodal_input(text, Keyword.get(opts, :attachment))

    options =
      %{
        offline_response: Keyword.get(opts, :response, "Offline assistant response")
      }
      |> maybe_put(:offline_failure, Keyword.get(opts, :fail, false))

    signal =
      Agent.request_signal!(%{
        input: input,
        model: "offline:live-chat",
        stream: Keyword.get(opts, :stream, true),
        options: options,
        limits: %{model_calls: 1, retries: 0, elapsed_ms: 5_000}
      })

    context =
      %{jido_ai_inference_client: OfflineClient}
      |> maybe_put(
        :jido_ai_dispatch,
        Keyword.get(opts, :stream_dispatch)
      )

    Jido.call(instance, ref, signal, context: context, timeout: 6_000)
  end

  @doc "Returns a small public projection of the committed conversation."
  def history(instance, ref) do
    with {:ok, server} <- Jido.activate_agent(instance, ref),
         %{agent: %{state: %{session: session}}} <- AgentServer.snapshot(server) do
      project_session(session)
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_chat_state}
    end
  end

  @doc "Maps runtime and model results to browser-facing operation states."
  def operation_state({:ok, %AgentServer.TurnResult{status: :uncertain}}), do: :uncertain
  def operation_state({:ok, %AgentServer.TurnResult{status: :cancelled}}), do: :cancelled
  def operation_state({:ok, %AgentServer.TurnResult{status: :timed_out}}), do: :timed_out
  def operation_state({:ok, %AgentServer.TurnResult{status: :failed}}), do: :failed
  def operation_state({:ok, %AgentServer.TurnResult{status: :waiting}}), do: :waiting

  def operation_state({:ok, %AgentServer.TurnResult{reply: %{data: %{status: :completed}}}}),
    do: :committed

  def operation_state({:ok, %AgentServer.TurnResult{reply: %{data: %{status: status}}}})
      when status in [:failed, :blocked],
      do: :failed

  def operation_state({:error, reason}) when reason in [:timeout, :call_timeout], do: :timed_out
  def operation_state({:error, reason}) when reason in [:cancelled, :canceled], do: :cancelled
  def operation_state({:ok, %AgentServer.TurnResult{status: :committed}}), do: :committed
  def operation_state(_result), do: :failed

  defp multimodal_input(text, nil), do: text

  defp multimodal_input(text, %{media_type: media_type, data_url: data_url}) do
    [
      %{type: :text, text: text},
      %{type: :image_url, url: data_url, media_type: media_type}
    ]
  end

  defp project_session(nil), do: {:ok, []}

  defp project_session(%Jido.Session{} = session) do
    with {:ok, messages} <- Jido.AI.Thread.Projection.messages(session) do
      {:ok, Enum.map(messages, &public_message/1)}
    end
  end

  defp public_message(%{role: role, content: content}) when is_binary(content) do
    %{role: role, text: content, attachments: []}
  end

  defp public_message(%{role: role, content: parts}) when is_list(parts) do
    text =
      parts
      |> Enum.filter(&(field(&1, :type) in [:text, "text"]))
      |> Enum.map_join("", &(field(&1, :text) || ""))

    attachments =
      parts
      |> Enum.reject(&(field(&1, :type) in [:text, "text"]))
      |> Enum.map(&%{type: field(&1, :type), attached?: true})

    %{role: role, text: text, attachments: attachments}
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp maybe_put(map, _key, false), do: map
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defmodule Jido.Examples.Patterns.LiveChat.Agent do
  @moduledoc "The durable owner of one chat Session."

  use Jido.AI.Agent, name: "example_liveview_chat_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "offline:live-chat"
      instructions "Answer in one short sentence."

      limits do
        model_calls 1
        retries 0
        elapsed_ms(5_000)
      end
    end
  end
end

defmodule Jido.Examples.Patterns.LiveChat.OfflineClient do
  @moduledoc "A deterministic streaming client for the chat application."

  @behaviour Jido.AI.InferenceClient

  alias Jido.Examples.Support.OfflineInferenceClient, as: Offline

  @impl true
  def generate_text(model, context, options) do
    if Keyword.get(options, :offline_failure, false),
      do: {:error, :offline_model_failure},
      else: Offline.generate_text(model, context, options)
  end

  @impl true
  def stream_text(model, context, options) do
    if Keyword.get(options, :offline_failure, false) do
      {:error, :offline_model_failure}
    else
      successful_stream(model, context, options)
    end
  end

  defp successful_stream(model, context, options) do
    words =
      options
      |> Keyword.get(:offline_response, "Offline assistant response")
      |> String.split(" ", trim: true)

    {:ok, metadata_handle} =
      ReqLLM.StreamResponse.MetadataHandle.start_link(fn ->
        %{
          response_id: "offline-live-chat",
          finish_reason: :stop,
          usage: %{input_tokens: 4, output_tokens: 4, total_cost: 0.0}
        }
      end)

    chunks =
      words
      |> Enum.with_index()
      |> Enum.map(fn {word, index} ->
        suffix = if index == length(words) - 1, do: "", else: " "
        ReqLLM.StreamChunk.text(word <> suffix)
      end)

    {:ok,
     %ReqLLM.StreamResponse{
       stream: chunks,
       metadata_handle: metadata_handle,
       cancel: fn -> :ok end,
       model: LLMDB.Model.new!(%{id: model, provider: :openai}),
       context: context
     }}
  end

  @impl true
  defdelegate generate_object(model, context, schema, options), to: Offline

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
end
