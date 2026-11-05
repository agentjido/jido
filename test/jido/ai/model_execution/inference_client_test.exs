defmodule Jido.AI.ModelExecution.InferenceClientTest do
  use ExUnit.Case, async: false

  alias Jido.AI.InferenceClient
  alias Jido.AI.InferenceClient.Selection
  alias Jido.Test.AI.{ChainOfThoughtAgent, SimpleAgent}

  defmodule CompleteClient do
    @behaviour InferenceClient

    @impl true
    def generate_text(_model, _messages, _opts), do: {:ok, :text}

    @impl true
    def stream_text(_model, _messages, _opts), do: {:ok, :stream}

    @impl true
    def generate_object(_model, _messages, _schema, _opts), do: {:ok, :object}

    @impl true
    def generate_image(_model, _prompt, _opts), do: {:ok, :image}

    @impl true
    def stream_image(_model, _prompt, _opts), do: {:ok, :image_stream}

    @impl true
    def generate_video(_model, _content, _opts), do: {:ok, :video}

    @impl true
    def query_video(_model, _task_id, _opts), do: {:ok, :video_status}

    @impl true
    def wait_video(_model, _task_id, _opts), do: {:ok, :video}

    @impl true
    def retrieve_video_file(_model, _file_id, _opts), do: {:ok, :video_file}

    @impl true
    def upload_video_file(_model, _file, _opts), do: {:ok, :uploaded_file}

    @impl true
    def stream_object(_model, _messages, _schema, _opts), do: {:ok, :object_stream}

    @impl true
    def embed(_model, _input, _opts), do: {:ok, :embedding}

    @impl true
    def rerank(_model, _opts), do: {:ok, :reranked}

    @impl true
    def compact_context(_model, _messages, _opts), do: {:ok, :compacted}

    @impl true
    def evaluate(_model, _state, _questions, _opts), do: {:ok, :evaluation}

    @impl true
    def evaluation_models, do: []

    @impl true
    def ocr(_model, _document, _opts), do: {:ok, :ocr}

    @impl true
    def ocr_file(_model, _path, _opts), do: {:ok, :ocr}

    @impl true
    def transcribe(_model, _audio, _opts), do: {:ok, :transcript}

    @impl true
    def transcribe_detailed(_model, _audio, _opts), do: {:ok, :transcript}

    @impl true
    def speak(_model, _text, _opts), do: {:ok, :speech}

    @impl true
    def speak_detailed(_model, _text, _opts), do: {:ok, :speech}
  end

  defmodule IncompleteClient do
    def generate_text(_model, _messages, _opts), do: {:ok, :text}
  end

  setup do
    original = Application.get_env(:jido, :ai_inference_client)

    on_exit(fn ->
      if original,
        do: Application.put_env(:jido, :ai_inference_client, original),
        else: Application.delete_env(:jido, :ai_inference_client)
    end)
  end

  test "uses the default ReqLLM client" do
    Application.delete_env(:jido, :ai_inference_client)
    assert Selection.client!() == Jido.AI.InferenceClient.ReqLLM
  end

  test "uses configured and per-action clients" do
    Application.put_env(:jido, :ai_inference_client, CompleteClient)

    assert Selection.client!() == CompleteClient

    assert Selection.client!(%{jido_ai_inference_client: Jido.AI.InferenceClient.ReqLLM}) ==
             Jido.AI.InferenceClient.ReqLLM
  end

  test "rejects an incomplete client" do
    assert_raise ArgumentError, ~r/invalid Jido AI inference client/, fn ->
      Selection.client!(%{jido_ai_inference_client: IncompleteClient})
    end
  end

  describe "an invalid client inside an Agent turn" do
    defmodule FailingClient do
      @behaviour InferenceClient

      for {name, arity} <- InferenceClient.behaviour_info(:callbacks) do
        @impl true
        def unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))),
          do: {:error, :provider_down}
      end
    end

    defp reply(agent_module, data, client) do
      agent = agent_module.instantiate!(id: "invalid-client-#{System.unique_integer([:positive])}")
      request = agent_module.request_signal!(data)

      assert {:ok, _agent, [%{signal: reply}]} =
               agent_module.cmd(agent, request, context: %{jido_ai_inference_client: client})

      reply.data
    end

    test "gives the same failed reply as a model error" do
      for {agent, data} <- [
            {SimpleAgent, %{input: "Hello"}},
            {SimpleAgent, %{input: "Hello", stream: true}},
            {ChainOfThoughtAgent, %{input: "Hello"}}
          ] do
        invalid = reply(agent, data, IncompleteClient)
        model_error = reply(agent, data, FailingClient)

        assert %{status: :failed, reason: reason} = invalid
        assert reason == "invalid Jido AI inference client: #{inspect(IncompleteClient)}"
        assert model_error.status == :failed
        assert Map.keys(invalid) == Map.keys(model_error)
      end
    end
  end

  test "keeps ReqLLM execution calls in the default client" do
    root = Path.expand("../..", __DIR__)
    allowed = Path.join(root, "lib/jido_ai/inference_client/req_llm.ex")

    call_pattern =
      ~r/ReqLLM\.(?:generate_text|stream_text|generate_object|generate_image|stream_image|generate_video|query_video|wait_video|retrieve_video_file|upload_video_file|stream_object|embed|rerank|compact_context|evaluate|evaluation_models|ocr|ocr_file|transcribe|transcribe_detailed|speak|speak_detailed)\s*\(/

    violations =
      root
      |> Path.join("lib/**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&(&1 == allowed))
      |> Enum.filter(&(File.read!(&1) =~ call_pattern))

    assert violations == []
  end
end
