defmodule Jido.Bench.ReActMemory.Tool do
  use Jido.Action,
    id: "jido/bench/react-memory/tools/record-round",
    name: "record_round",
    description: "Return one small result for a ReAct tool round.",
    schema: Jido.Joi.object(%{round: Jido.Joi.integer(gte: 1)}),
    output_schema: Jido.Joi.object(%{text: Jido.Joi.string(), round: Jido.Joi.integer(gte: 1)})

  @impl Jido.Action
  def run(%{round: round}, _context), do: {:ok, %{text: "ok", round: round}}
end

defmodule Jido.Bench.ReActMemory.Agent do
  use Jido.AI.Agent,
    id: "jido/bench/react-memory/agent",
    vsn: 1,
    name: "react_memory_bench_agent",
    description: "Run the canonical ReAct graph with a deterministic model"

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action Jido.Bench.ReActMemory.Tool
    end
  end
end

defmodule Jido.Bench.ReActMemory.Client do
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

  @impl Jido.AI.InferenceClient
  def generate_text(model, context, _options) do
    completed_rounds =
      context
      |> ReqLLM.Context.to_list()
      |> Enum.count(&(&1.role == :tool))

    target_rounds = Application.fetch_env!(:jido, :react_memory_bench_rounds)

    response =
      if completed_rounds < target_rounds do
        round = completed_rounds + 1

        tool_call =
          ReqLLM.ToolCall.new(
            "round-#{round}",
            "record_round",
            Jason.encode!(%{round: round})
          )

        %ReqLLM.Response{
          id: "tool-round-#{round}",
          model: model,
          context: context,
          finish_reason: :tool_calls,
          message: ReqLLM.Context.assistant("", tool_calls: [tool_call])
        }
      else
        %ReqLLM.Response{
          id: "final-answer",
          model: model,
          context: context,
          finish_reason: :stop,
          message: ReqLLM.Context.assistant("Completed #{completed_rounds} tool rounds.")
        }
      end

    {:ok, response}
  end

  @impl Jido.AI.InferenceClient
  def evaluation_models, do: []

  for {name, arity} <- @unsupported_callbacks do
    arguments = Macro.generate_arguments(arity, __MODULE__)

    @impl Jido.AI.InferenceClient
    def unquote(name)(unquote_splicing(arguments)), do: {:error, :unsupported_in_memory_bench}
  end
end

defmodule Jido.Bench.ReActMemory do
  alias Jido.Agent.Directive.Reply
  alias Jido.Bench.ReActMemory.Agent, as: BenchAgent
  alias Jido.Bench.ReActMemory.Client

  @memory_keys [:total, :processes_used, :binary, :ets]
  @default_rounds [1, 3, 5]
  @default_concurrency [1, 10]
  @default_sample_ms 5
  @result_prefix "JIDO_REACT_MEMORY_CASE="

  def main(["--case", rounds, concurrency, sample_ms]) do
    result = run_case(integer!(rounds), integer!(concurrency), integer!(sample_ms))
    IO.puts(@result_prefix <> Jason.encode!(result))
  end

  def main([]) do
    rounds = csv_integers("JIDO_MEMORY_BENCH_ROUNDS", @default_rounds)
    concurrency = csv_integers("JIDO_MEMORY_BENCH_CONCURRENCY", @default_concurrency)
    sample_ms = env_integer("JIDO_MEMORY_BENCH_SAMPLE_MS", @default_sample_ms)

    results =
      for round_count <- rounds, max_concurrency <- concurrency do
        run_isolated_case(round_count, max_concurrency, sample_ms)
      end

    print_report(results, sample_ms)
  end

  def main(arguments) do
    raise "unknown arguments: #{inspect(arguments)}"
  end

  defp run_case(rounds, max_concurrency, sample_ms)
       when rounds in 1..8 and max_concurrency > 0 and sample_ms > 0 do
    Application.put_env(:jido, :ai_inference_client, Client)
    Application.put_env(:jido, :react_memory_bench_rounds, rounds)

    collect_garbage()
    baseline = memory_snapshot()
    sampler = start_sampler(baseline, sample_ms)
    started_at = System.monotonic_time()

    agent = BenchAgent.instantiate!(id: "react-memory-#{rounds}-#{max_concurrency}")

    request =
      BenchAgent.request_signal!(%{
        input: "Run #{rounds} distinct tool rounds, then give a final answer.",
        model: "bench:deterministic",
        limits: %{
          model_calls: rounds + 1,
          tool_rounds: rounds,
          tool_calls: rounds,
          retries: 0,
          elapsed_ms: 600_000
        }
      })

    outcome = BenchAgent.cmd(agent, request, max_concurrency: max_concurrency)

    elapsed_ms = elapsed_ms(started_at)
    {peak, samples} = stop_sampler(sampler)
    final = memory_snapshot()

    common = %{
      rounds: rounds,
      max_concurrency: max_concurrency,
      elapsed_ms: elapsed_ms,
      samples: samples,
      peak_process_delta_bytes: delta(peak.processes_used, baseline.processes_used),
      peak_total_delta_bytes: delta(peak.total, baseline.total),
      peak_binary_delta_bytes: delta(peak.binary, baseline.binary),
      peak_ets_delta_bytes: delta(peak.ets, baseline.ets),
      final_process_delta_bytes: final.processes_used - baseline.processes_used
    }

    case outcome do
      {:ok, next_agent, [%Reply{signal: reply}]} ->
        data = reply.data
        retained = term_sizes(next_agent)

        Map.merge(common, %{
          outcome: data.status,
          failure: nil,
          model_calls: data.model_calls,
          tool_rounds: data.tool_rounds,
          retained_agent_shared_bytes: retained.shared,
          retained_agent_flat_bytes: retained.flat
        })

      {:error, error} ->
        Map.merge(common, %{
          outcome: :error,
          failure: failure_summary(error),
          model_calls: nil,
          tool_rounds: nil,
          retained_agent_shared_bytes: nil,
          retained_agent_flat_bytes: nil
        })

      other ->
        Map.merge(common, %{
          outcome: :unexpected_return,
          failure: %{kind: :unexpected_return, value: inspect(other, limit: 10)},
          model_calls: nil,
          tool_rounds: nil,
          retained_agent_shared_bytes: nil,
          retained_agent_flat_bytes: nil
        })
    end
  end

  defp run_case(rounds, max_concurrency, sample_ms) do
    raise "invalid case: rounds=#{rounds}, max_concurrency=#{max_concurrency}, sample_ms=#{sample_ms}"
  end

  defp run_isolated_case(rounds, max_concurrency, sample_ms) do
    mix = System.find_executable("mix") || raise "mix executable was not found"
    script = Path.relative_to_cwd(__ENV__.file)

    {output, status} =
      System.cmd(
        mix,
        [
          "run",
          "--no-compile",
          "--no-deps-check",
          script,
          "--case",
          Integer.to_string(rounds),
          Integer.to_string(max_concurrency),
          Integer.to_string(sample_ms)
        ],
        env: [{"MIX_ENV", Atom.to_string(Mix.env())}],
        stderr_to_stdout: true
      )

    if status != 0 do
      raise "isolated case failed for rounds=#{rounds}, max_concurrency=#{max_concurrency}:\n#{output}"
    end

    output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case String.split(line, @result_prefix, parts: 2) do
        ["", encoded] -> Jason.decode!(encoded, keys: :atoms)
        _other -> nil
      end
    end)
    |> case do
      nil -> raise "isolated case did not return a result:\n#{output}"
      result -> result
    end
  end

  defp start_sampler(baseline, sample_ms) do
    owner = self()
    spawn_link(fn -> sample(owner, sample_ms, baseline, 0) end)
  end

  defp sample(owner, sample_ms, peak, samples) do
    receive do
      {:stop, caller} ->
        current = memory_snapshot()
        send(caller, {:memory_samples, merge_peak(peak, current), samples + 1})
    after
      sample_ms ->
        sample(owner, sample_ms, merge_peak(peak, memory_snapshot()), samples + 1)
    end
  end

  defp stop_sampler(sampler) do
    send(sampler, {:stop, self()})

    receive do
      {:memory_samples, peak, samples} -> {peak, samples}
    after
      5_000 -> raise "memory sampler did not stop"
    end
  end

  defp memory_snapshot do
    memory = Map.new(:erlang.memory())
    Map.new(@memory_keys, &{&1, Map.fetch!(memory, &1)})
  end

  defp merge_peak(left, right) do
    Map.new(@memory_keys, &{&1, max(Map.fetch!(left, &1), Map.fetch!(right, &1))})
  end

  defp delta(peak, baseline), do: max(peak - baseline, 0)

  defp term_sizes(term) do
    word_size = :erlang.system_info(:wordsize)
    %{shared: :erts_debug.size(term) * word_size, flat: :erts_debug.flat_size(term) * word_size}
  end

  defp collect_garbage do
    for process <- Process.list(), do: :erlang.garbage_collect(process)
    :ok
  end

  defp elapsed_ms(started_at) do
    System.monotonic_time()
    |> Kernel.-(started_at)
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp print_report(results, sample_ms) do
    runic_version = Application.spec(:runic, :vsn) |> to_string()

    IO.puts("ReAct memory benchmark")
    IO.puts("Runic #{runic_version}; OTP #{System.otp_release()}; sample interval #{sample_ms} ms")
    IO.puts("Each row runs in a new BEAM VM. The model and tool are local and deterministic.\n")

    IO.puts(
      "| rounds | concurrency | outcome | elapsed ms | peak process | peak total | peak binary | retained shared | retained flat |"
    )

    IO.puts("| ---: | ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: |")

    Enum.each(results, fn result ->
      IO.puts(
        "| #{result.rounds} | #{result.max_concurrency} | #{result.outcome} | #{result.elapsed_ms} | " <>
          "#{mib(result.peak_process_delta_bytes)} | #{mib(result.peak_total_delta_bytes)} | " <>
          "#{mib(result.peak_binary_delta_bytes)} | #{maybe_mib(result.retained_agent_shared_bytes)} | " <>
          "#{maybe_mib(result.retained_agent_flat_bytes)} |"
      )
    end)

    print_failures(results)
    print_ratios(results)
  end

  defp print_failures(results) do
    failures = Enum.reject(results, &is_nil(&1.failure))

    if failures != [] do
      IO.puts("\nFailures:")

      Enum.each(failures, fn result ->
        IO.puts(
          "  #{result.rounds} rounds, concurrency #{result.max_concurrency}: " <>
            inspect(result.failure)
        )
      end)
    end
  end

  defp print_ratios(results) do
    IO.puts("\nPeak process ratios for equal round counts:")

    results
    |> Enum.group_by(& &1.rounds)
    |> Enum.sort()
    |> Enum.each(fn {rounds, cases} ->
      serial = Enum.find(cases, &(&1.max_concurrency == 1))
      async = cases |> Enum.reject(&(&1.max_concurrency == 1)) |> Enum.max_by(& &1.max_concurrency, fn -> nil end)

      if serial && async && serial.outcome == "completed" && async.outcome == "completed" do
        IO.puts(
          "  #{rounds} rounds: concurrency #{async.max_concurrency} / concurrency 1 = " <>
            ratio(async.peak_process_delta_bytes, serial.peak_process_delta_bytes)
        )
      end
    end)
  end

  defp mib(bytes), do: :erlang.float_to_binary(bytes / 1_048_576, decimals: 2) <> " MiB"

  defp maybe_mib(nil), do: "n/a"
  defp maybe_mib(bytes), do: mib(bytes)

  defp ratio(_numerator, 0), do: "n/a"
  defp ratio(numerator, denominator), do: :erlang.float_to_binary(numerator / denominator, decimals: 2) <> "x"

  defp csv_integers(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> value |> String.split(",", trim: true) |> Enum.map(&integer!/1)
    end
  end

  defp env_integer(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> integer!(value)
    end
  end

  defp integer!(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> raise "expected an integer, got: #{inspect(value)}"
    end
  end

  defp failure_summary(%Jido.Error.ExecutionError{
         details: %{
           reason: {%Runic.Identity.CanonicalError{reason: {:limit, :item_count, item_count}, path: path}, _stacktrace}
         }
       }) do
    %{
      kind: :canonical_identity_item_limit,
      item_count: item_count,
      path: inspect(path, limit: 20)
    }
  end

  defp failure_summary(%{message: message}), do: %{kind: :execution_error, message: message}
  defp failure_summary(error), do: %{kind: :execution_error, message: inspect(error, limit: 10)}
end

Jido.Bench.ReActMemory.main(System.argv())
