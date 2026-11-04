Code.require_file("../support/result.exs", __DIR__)

defmodule Jido.Test.Perf.AI.ReActSupport.Echo do
  use Jido.Action,
    id: "jido/bench/ai/tools/echo",
    vsn: 1,
    name: "ai_bench_echo",
    description: "Return one deterministic benchmark result",
    schema: Jido.Joi.object(%{}),
    output_schema: Jido.Joi.object(%{text: Jido.Joi.string()})

  @impl true
  def run(_params, _context), do: {:ok, %{text: "ok"}}
end

defmodule Jido.Test.Perf.AI.ReActSupport.Agent do
  use Jido.AI.Agent,
    id: "jido/bench/ai/agents/react",
    vsn: 1,
    name: "ai_react_bench_agent",
    description: "Run deterministic ReAct benchmark requests"

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action Jido.Test.Perf.AI.ReActSupport.Echo
    end
  end
end

defmodule Jido.Test.Perf.AI.ReActSupport.Client do
  @behaviour Jido.AI.InferenceClient

  @unsupported_callbacks [
    stream_text: 3,
    generate_object: 4,
    generate_image: 3,
    stream_image: 3,
    generate_video: 3,
    query_video: 3,
    wait_video: 3,
    retrieve_video_file: 3,
    upload_video_file: 3,
    stream_object: 4,
    embed: 3,
    rerank: 2,
    compact_context: 3,
    evaluate: 4,
    ocr: 3,
    ocr_file: 3,
    transcribe: 3,
    transcribe_detailed: 3,
    speak: 3,
    speak_detailed: 3
  ]

  @impl true
  def generate_text(model, context, _options) do
    current_request =
      context
      |> ReqLLM.Context.to_list()
      |> Enum.reverse()
      |> Enum.take_while(&(&1.role != :user))

    completed_tool_rounds =
      Enum.count(current_request, fn message ->
        message.role == :assistant and (message.tool_calls || []) != []
      end)

    response =
      if completed_tool_rounds == 0 do
        call =
          ReqLLM.ToolCall.new(
            "bench-#{System.unique_integer([:positive])}",
            "ai_bench_echo",
            "{}"
          )

        %ReqLLM.Response{
          id: "bench-tool",
          model: model,
          context: context,
          finish_reason: :tool_calls,
          message: ReqLLM.Context.assistant("", tool_calls: [call])
        }
      else
        %ReqLLM.Response{
          id: "bench-final",
          model: model,
          context: context,
          finish_reason: :stop,
          message: ReqLLM.Context.assistant("done")
        }
      end

    {:ok, response}
  end

  @impl true
  def evaluation_models, do: []

  for {name, arity} <- @unsupported_callbacks do
    arguments = Macro.generate_arguments(arity, __MODULE__)

    @impl true
    def unquote(name)(unquote_splicing(arguments)), do: {:error, :unsupported_offline_benchmark}
  end
end

defmodule Jido.Test.Perf.AI.ReActSupport do
  alias Jido.Agent.Directive.Reply
  alias Jido.Test.Perf.AI.ReActSupport.{Agent, Client}
  alias Jido.Test.Perf.Result

  @profiles %{"quick" => 2, "standard" => 20, "stress" => 100}

  def run(:state_growth, requests), do: with_client(fn -> state_growth(requests) end)
  def run(:fresh_workflow, requests), do: with_client(fn -> fresh_workflows(requests) end)

  def parse!(arguments) do
    {options, rest, invalid} =
      OptionParser.parse(arguments, strict: [profile: :string, requests: :integer, output: :string])

    if rest != [] or invalid != [], do: raise("unknown benchmark arguments")
    profile = Keyword.get(options, :profile, "quick")
    requests = Keyword.get(options, :requests, Map.get(@profiles, profile))

    unless Map.has_key?(@profiles, profile), do: raise("--profile must be quick, standard, or stress")
    unless requests in 1..100, do: raise("--requests must be from 1 through 100")

    output =
      case Keyword.get(options, :output) do
        nil -> nil
        path -> output_path!(path)
      end

    %{profile: profile, requests: requests, output: output}
  end

  def report!(mode, %{profile: profile, requests: requests, output: output}) do
    benchmark_id = "jido.ai.react.#{mode}"

    report = %{
      benchmark_result_schema_version: Result.schema_version(),
      schema_version: 1,
      metadata:
        Result.metadata(benchmark_id, profile, %{
          input_size: "#{requests} requests",
          sample_count: requests
        }),
      mode: mode,
      requests: requests,
      provider: "deterministic-local",
      network: false,
      cases: run(mode, requests),
      environment: %{
        elixir: System.version(),
        otp: System.otp_release(),
        runic: Application.spec(:runic, :vsn) |> to_string()
      }
    }

    Result.validate!(report)

    encoded = JSON.encode!(report)
    IO.puts(encoded)

    if output do
      File.mkdir_p!(Path.dirname(output))
      File.write!(output, encoded <> "\n")
    end

    report
  end

  defp state_growth(requests) do
    initial = Agent.instantiate!(id: "state-growth")

    {cases, _agent} =
      Enum.map_reduce(1..requests, initial, fn request_number, current ->
        started = System.monotonic_time()
        {:ok, next, [%Reply{signal: reply}]} = Agent.cmd(current, request(request_number))
        validate_reply!(reply)
        session = next.state.session

        metric =
          sizes(next)
          |> Map.merge(%{
            id: "request/#{request_number}",
            request: request_number,
            elapsed_us: elapsed_us(started),
            thread_entries: length(session.thread.entries),
            session_external_bytes: :erlang.external_size(session),
            model_calls: reply.data.model_calls,
            tool_calls: reply.data.tool_calls,
            tool_rounds: reply.data.tool_rounds
          })

        {metric, next}
      end)

    cases
  end

  defp fresh_workflows(requests) do
    Enum.map(1..requests, fn request_number ->
      params = request_params(request_number)
      started = System.monotonic_time()
      {:ok, %{workflow: workflow}} = Agent.preflight(params)
      compile_us = elapsed_us(started)
      agent = Agent.instantiate!(id: "fresh-#{request_number}")
      started = System.monotonic_time()
      {:ok, next, [%Reply{signal: reply}]} = Agent.cmd(agent, Agent.request_signal!(params))
      validate_reply!(reply)

      sizes(next)
      |> Map.merge(%{
        id: "request/#{request_number}",
        request: request_number,
        compile_us: compile_us,
        execution_us: elapsed_us(started),
        workflow_components: map_size(workflow.components),
        workflow_external_bytes: :erlang.external_size(workflow),
        thread_entries: length(next.state.session.thread.entries),
        model_calls: reply.data.model_calls,
        tool_calls: reply.data.tool_calls,
        tool_rounds: reply.data.tool_rounds
      })
    end)
  end

  defp request(request_number), do: Agent.request_signal!(request_params(request_number))

  defp request_params(request_number) do
    %{
      input: "Request #{request_number}: call the tool once, then answer done.",
      model: "bench:deterministic",
      limits: %{model_calls: 2, tool_rounds: 1, tool_calls: 1, retries: 0, elapsed_ms: 30_000}
    }
  end

  defp validate_reply!(reply) do
    unless reply.data.status == :completed and reply.data.output == "done" and
             reply.data.model_calls == 2 and reply.data.tool_calls == 1 and
             reply.data.tool_rounds == 1 do
      raise "offline ReAct benchmark returned invalid work counts: #{inspect(reply.data)}"
    end
  end

  defp sizes(term) do
    word_size = :erlang.system_info(:wordsize)

    %{
      retained_external_bytes: :erlang.external_size(term),
      retained_shared_bytes: :erts_debug.size(term) * word_size,
      retained_flat_bytes: :erts_debug.flat_size(term) * word_size
    }
  end

  defp elapsed_us(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :microsecond)
  end

  defp output_path!(path) do
    expanded = Path.expand(path)
    root = Path.expand("tmp/bench/ai")

    unless expanded == root or String.starts_with?(expanded, root <> "/") do
      raise "benchmark output must be under tmp/bench/ai"
    end

    expanded
  end

  defp with_client(fun) do
    previous = Application.fetch_env(:jido, :ai_inference_client)
    Application.put_env(:jido, :ai_inference_client, Client)

    try do
      fun.()
    after
      case previous do
        {:ok, value} -> Application.put_env(:jido, :ai_inference_client, value)
        :error -> Application.delete_env(:jido, :ai_inference_client)
      end
    end
  end
end
