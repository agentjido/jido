# Shared Runic ReAct memory reproduction.
#
# Run from the Jido project root with:
#
#     mix bench
#
# The base profile runs direct, serial ReAct turns with one empty tool result
# per round. It uses isolated BEAM VMs for 1, 3, and 5 rounds. It does not use
# a model provider or make a network call. Runic 0.1.0-alpha.13 completes the
# first two cases and reaches its canonical identity item limit in the
# five-round case.
#
# Use JIDO_MEMORY_BENCH_PROFILE=expanded to run the larger comparison matrix.

defmodule Jido.Bench.ReActMemory.Tool do
  use Jido.Action,
    id: "jido/bench/react-memory/tools/record-round",
    name: "record_round",
    description: "Return one deterministic payload for a ReAct tool round.",
    schema:
      Jido.Joi.object(%{
        round: Jido.Joi.integer(gte: 1),
        item: Jido.Joi.integer(gte: 1),
        payload_bytes: Jido.Joi.integer(gte: 0)
      }),
    output_schema:
      Jido.Joi.object(%{
        text: Jido.Joi.string(),
        round: Jido.Joi.integer(gte: 1),
        item: Jido.Joi.integer(gte: 1)
      })

  @impl Jido.Action
  def run(%{round: round, item: item, payload_bytes: payload_bytes}, _context) do
    {:ok, %{text: String.duplicate("x", payload_bytes), round: round, item: item}}
  end
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
      |> Enum.count(fn message -> message.role == :assistant and (message.tool_calls || []) != [] end)

    target_rounds = Application.fetch_env!(:jido, :react_memory_bench_rounds)
    tools_per_round = Application.fetch_env!(:jido, :react_memory_bench_tools_per_round)
    payload_bytes = Application.fetch_env!(:jido, :react_memory_bench_payload_bytes)

    response =
      if completed_rounds < target_rounds do
        round = completed_rounds + 1

        tool_calls =
          Enum.map(1..tools_per_round, fn item ->
            ReqLLM.ToolCall.new(
              "round-#{round}-item-#{item}",
              "record_round",
              JSON.encode!(%{round: round, item: item, payload_bytes: payload_bytes})
            )
          end)

        %ReqLLM.Response{
          id: "tool-round-#{round}",
          model: model,
          context: context,
          finish_reason: :tool_calls,
          message: ReqLLM.Context.assistant("", tool_calls: tool_calls)
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
  alias Jido.AgentServer
  alias Jido.Bench.ReActMemory.Agent, as: BenchAgent
  alias Jido.Bench.ReActMemory.Client

  @memory_keys [:total, :processes_used, :binary, :ets]
  @workloads %{
    "serial" => %{tools_per_round: 1, max_concurrency: 1},
    "constrained" => %{tools_per_round: 4, max_concurrency: 1},
    "parallel" => %{tools_per_round: 4, max_concurrency: 4}
  }
  @base_defaults %{
    modes: [:direct],
    rounds: [1, 3, 5],
    workloads: ["serial"],
    payload_bytes: 0
  }
  @expanded_defaults %{
    modes: [:direct, :managed],
    rounds: [1, 3, 5],
    workloads: ["serial", "constrained", "parallel"],
    payload_bytes: 256
  }
  @default_repeats 1
  @default_sample_ms 5
  @result_prefix "JIDO_REACT_MEMORY_CASE="

  def main([
        "--case",
        mode,
        workload,
        rounds,
        tools_per_round,
        max_concurrency,
        payload_bytes,
        sample_ms,
        iteration
      ]) do
    result =
      run_case(%{
        mode: mode!(mode),
        workload: workload,
        rounds: integer!(rounds),
        tools_per_round: integer!(tools_per_round),
        max_concurrency: integer!(max_concurrency),
        payload_bytes: integer!(payload_bytes),
        sample_ms: integer!(sample_ms),
        iteration: integer!(iteration)
      })

    IO.puts(@result_prefix <> Jason.encode!(result))
  end

  def main([]) do
    profile = System.get_env("JIDO_MEMORY_BENCH_PROFILE", "base") |> profile!()
    defaults = profile_defaults(profile)

    modes = csv_values("JIDO_MEMORY_BENCH_MODES", defaults.modes, &mode!/1)
    rounds = csv_integers("JIDO_MEMORY_BENCH_ROUNDS", defaults.rounds)
    workloads = csv_values("JIDO_MEMORY_BENCH_WORKLOADS", defaults.workloads, &workload!/1)

    payload_bytes =
      "JIDO_MEMORY_BENCH_PAYLOAD_BYTES"
      |> env_integer(defaults.payload_bytes)
      |> integer_in!(0..1_000_000, "payload bytes")

    repeats =
      "JIDO_MEMORY_BENCH_REPEATS"
      |> env_integer(@default_repeats)
      |> integer_in!(1..100, "repeats")

    sample_ms =
      "JIDO_MEMORY_BENCH_SAMPLE_MS"
      |> env_integer(@default_sample_ms)
      |> integer_in!(1..60_000, "sample interval")

    results =
      for mode <- modes,
          round_count <- rounds,
          workload_name <- workloads,
          iteration <- 1..repeats do
        workload = Map.fetch!(@workloads, workload_name)

        run_isolated_case(%{
          mode: mode,
          workload: workload_name,
          rounds: round_count,
          tools_per_round: workload.tools_per_round,
          max_concurrency: workload.max_concurrency,
          payload_bytes: payload_bytes,
          sample_ms: sample_ms,
          iteration: iteration
        })
      end

    report(results, sample_ms, profile)
  end

  def main(arguments) do
    raise "unknown arguments: #{inspect(arguments)}"
  end

  defp run_case(
         %{
           mode: mode,
           rounds: rounds,
           tools_per_round: tools_per_round,
           max_concurrency: max_concurrency,
           payload_bytes: payload_bytes,
           sample_ms: sample_ms,
           iteration: iteration
         } = scenario
       )
       when mode in [:direct, :managed] and rounds in 1..16 and tools_per_round in 1..32 and
              max_concurrency > 0 and payload_bytes in 0..1_000_000 and sample_ms > 0 and
              iteration > 0 do
    :erlang.system_flag(:backtrace_depth, 32)
    Application.put_env(:jido, :ai_inference_client, Client)
    Application.put_env(:jido, :react_memory_bench_rounds, rounds)
    Application.put_env(:jido, :react_memory_bench_tools_per_round, tools_per_round)
    Application.put_env(:jido, :react_memory_bench_payload_bytes, payload_bytes)

    runic = runic_metrics()

    collect_garbage()
    baseline = memory_snapshot()
    sampler = start_sampler(baseline, sample_ms)
    started_at = System.monotonic_time()

    request =
      BenchAgent.request_signal!(%{
        input: "Run #{rounds} tool rounds with #{tools_per_round} tool calls per round, then finish.",
        model: "bench:deterministic",
        limits: %{
          model_calls: rounds + 1,
          tool_rounds: rounds,
          tool_calls: rounds * tools_per_round,
          retries: 0,
          elapsed_ms: 600_000
        }
      })

    outcome = execute(mode, scenario, request)

    elapsed_ms = elapsed_ms(started_at)
    {peak, samples} = stop_sampler(sampler)
    final = memory_snapshot()

    common =
      scenario
      |> Map.delete(:sample_ms)
      |> Map.merge(runic)
      |> Map.merge(%{
        elapsed_ms: elapsed_ms,
        samples: samples,
        peak_process_delta_bytes: delta(peak.processes_used, baseline.processes_used),
        peak_total_delta_bytes: delta(peak.total, baseline.total),
        peak_binary_delta_bytes: delta(peak.binary, baseline.binary),
        peak_ets_delta_bytes: delta(peak.ets, baseline.ets),
        final_process_delta_bytes: final.processes_used - baseline.processes_used,
        expected_model_calls: rounds + 1,
        expected_tool_rounds: rounds,
        expected_tool_calls: rounds * tools_per_round
      })

    case outcome do
      {:ok, next_agent, [%Reply{signal: reply}]} ->
        data = reply.data
        retained = term_sizes(next_agent)
        session = get_in(next_agent.state, [:session])
        session_metrics = session_metrics(session)

        valid_counts? =
          data.model_calls == rounds + 1 and data.tool_rounds == rounds and
            data.tool_calls == rounds * tools_per_round

        common
        |> Map.merge(session_metrics)
        |> Map.merge(%{
          outcome: if(valid_counts?, do: data.status, else: :invalid_counts),
          failure: if(valid_counts?, do: nil, else: %{kind: :invalid_counts}),
          model_calls: data.model_calls,
          tool_rounds: data.tool_rounds,
          tool_calls: data.tool_calls,
          retained_agent_shared_bytes: retained.shared,
          retained_agent_flat_bytes: retained.flat
        })

      {:error, error} ->
        Map.merge(common, %{
          outcome: :error,
          failure: failure_summary(error),
          model_calls: nil,
          tool_rounds: nil,
          tool_calls: nil,
          retained_agent_shared_bytes: nil,
          retained_agent_flat_bytes: nil,
          retained_session_shared_bytes: nil,
          retained_session_flat_bytes: nil,
          thread_entries: nil
        })

      other ->
        Map.merge(common, %{
          outcome: :unexpected_return,
          failure: %{kind: :unexpected_return, value: inspect(other, limit: 10)},
          model_calls: nil,
          tool_rounds: nil,
          tool_calls: nil,
          retained_agent_shared_bytes: nil,
          retained_agent_flat_bytes: nil,
          retained_session_shared_bytes: nil,
          retained_session_flat_bytes: nil,
          thread_entries: nil
        })
    end
  end

  defp run_case(scenario), do: raise("invalid benchmark case: #{inspect(scenario)}")

  defp execute(:direct, scenario, request) do
    agent = BenchAgent.instantiate!(id: scenario_id(scenario))
    BenchAgent.cmd(agent, request, max_concurrency: scenario.max_concurrency)
  end

  defp execute(:managed, scenario, request) do
    namespace = "jido/bench/react-memory/#{scenario_id(scenario)}"
    {:ok, _jido} = Jido.start(namespace: namespace)

    {:ok, server} =
      Jido.start_agent(Jido.Default, BenchAgent,
        id: scenario_id(scenario),
        turn_timeout: :infinity,
        exec_opts: [max_concurrency: scenario.max_concurrency]
      )

    :ok = AgentServer.await_ready(server)

    AgentServer.call(server, request,
      timeout: :infinity,
      admission_timeout: :infinity
    )
  end

  defp scenario_id(scenario) do
    Enum.join(
      [
        "react-memory",
        scenario.mode,
        scenario.workload,
        scenario.rounds,
        scenario.iteration
      ],
      "-"
    )
  end

  defp runic_metrics do
    started_at = System.monotonic_time()
    workflow = Jido.Exec.compile!(Jido.AI.Reasoning.ReAct)
    compile_us = elapsed_us(started_at)
    sizes = term_sizes(workflow)

    %{
      runic_compile_us: compile_us,
      runic_components: map_size(workflow.components),
      runic_build_log_entries: workflow |> Runic.Workflow.build_log() |> length(),
      runic_workflow_shared_bytes: sizes.shared,
      runic_workflow_flat_bytes: sizes.flat
    }
  end

  defp session_metrics(%Jido.Session{} = session) do
    sizes = term_sizes(session)

    %{
      retained_session_shared_bytes: sizes.shared,
      retained_session_flat_bytes: sizes.flat,
      thread_entries: length(session.thread.entries)
    }
  end

  defp session_metrics(_session) do
    %{
      retained_session_shared_bytes: nil,
      retained_session_flat_bytes: nil,
      thread_entries: nil
    }
  end

  defp run_isolated_case(scenario) do
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
          Atom.to_string(scenario.mode),
          scenario.workload,
          Integer.to_string(scenario.rounds),
          Integer.to_string(scenario.tools_per_round),
          Integer.to_string(scenario.max_concurrency),
          Integer.to_string(scenario.payload_bytes),
          Integer.to_string(scenario.sample_ms),
          Integer.to_string(scenario.iteration)
        ],
        env: [{"MIX_ENV", Atom.to_string(Mix.env())}],
        stderr_to_stdout: true
      )

    if status != 0 do
      raise "isolated case failed for #{inspect(scenario)}:\n#{output}"
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

  defp elapsed_us(started_at) do
    System.monotonic_time()
    |> Kernel.-(started_at)
    |> System.convert_time_unit(:native, :microsecond)
  end

  defp report(results, sample_ms, profile) do
    metadata = metadata(sample_ms, profile)

    case System.get_env("JIDO_MEMORY_BENCH_OUTPUT", "markdown") do
      "markdown" -> print_report(results, metadata)
      "json" -> IO.puts(Jason.encode!(%{metadata: metadata, results: results}, pretty: true))
      output -> raise "unsupported JIDO_MEMORY_BENCH_OUTPUT: #{inspect(output)}"
    end
  end

  defp metadata(sample_ms, profile) do
    %{
      elixir: System.version(),
      jido_revision: git_revision(),
      otp: System.otp_release(),
      profile: profile,
      runic: Application.spec(:runic, :vsn) |> to_string(),
      schedulers: :erlang.system_info(:schedulers_online),
      sample_ms: sample_ms,
      system_architecture: :erlang.system_info(:system_architecture) |> List.to_string()
    }
  end

  defp print_report(results, metadata) do
    first = List.first(results) || raise "benchmark suite returned no results"

    IO.puts("Runic ReAct memory benchmark")

    IO.puts(
      "Runic #{metadata.runic}; Elixir #{metadata.elixir}; OTP #{metadata.otp}; " <>
        "#{metadata.schedulers} schedulers; sample interval #{metadata.sample_ms} ms"
    )

    IO.puts("Jido #{metadata.jido_revision}; #{metadata.system_architecture}")
    IO.puts("Profile: #{metadata.profile}")
    IO.puts("Each case runs in a new BEAM VM with a local deterministic model and tool.\n")

    IO.puts("Compiled canonical ReAct workflow:")

    IO.puts(
      "  #{first.runic_components} components; #{first.runic_build_log_entries} build-log entries; " <>
        "#{kib(first.runic_workflow_shared_bytes)} shared; " <>
        "#{kib(first.runic_workflow_flat_bytes)} flat"
    )

    IO.puts("\nRuntime cases:")

    IO.puts(
      "| mode | workload | run | rounds | tools/round | max conc. | payload | outcome | elapsed | peak process | peak total | retained agent | retained session | entries |"
    )

    IO.puts("| :--- | :--- | ---: | ---: | ---: | ---: | ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: |")

    Enum.each(results, fn result ->
      IO.puts(
        "| #{result.mode} | #{result.workload} | #{result.iteration} | #{result.rounds} | " <>
          "#{result.tools_per_round} | #{result.max_concurrency} | #{kib(result.payload_bytes)} | " <>
          "#{result.outcome} | #{result.elapsed_ms} ms | #{mib(result.peak_process_delta_bytes)} | " <>
          "#{mib(result.peak_total_delta_bytes)} | #{maybe_mib(result.retained_agent_shared_bytes)} | " <>
          "#{maybe_mib(result.retained_session_shared_bytes)} | #{result.thread_entries || "n/a"} |"
      )
    end)

    IO.puts("\nAllocator details:")
    IO.puts("| mode | workload | run | rounds | peak binary | peak ETS | final process | samples | compile |")
    IO.puts("| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")

    Enum.each(results, fn result ->
      IO.puts(
        "| #{result.mode} | #{result.workload} | #{result.iteration} | #{result.rounds} | " <>
          "#{mib(result.peak_binary_delta_bytes)} | #{mib(result.peak_ets_delta_bytes)} | " <>
          "#{signed_mib(result.final_process_delta_bytes)} | #{result.samples} | " <>
          "#{result.runic_compile_us} us |"
      )
    end)

    print_failures(results)
    print_round_growth(results)
    print_ratios(results)
  end

  defp print_failures(results) do
    failures = Enum.reject(results, &is_nil(&1.failure))

    if failures != [] do
      IO.puts("\nExecution errors captured as benchmark results:")

      Enum.each(failures, fn result ->
        IO.puts(
          "  #{result.mode}/#{result.workload}, run #{result.iteration}, #{result.rounds} rounds: " <>
            failure_line(result.failure)
        )

        if stacktrace = result.failure[:stacktrace], do: IO.puts(stacktrace)
      end)
    end
  end

  defp print_round_growth(results) do
    lines =
      results
      |> Enum.group_by(&{&1.mode, &1.workload, &1.iteration})
      |> Enum.sort()
      |> Enum.flat_map(fn {{mode, workload, iteration}, cases} ->
        case Enum.find(cases, &(&1.rounds == 1)) do
          nil ->
            []

          baseline ->
            cases
            |> Enum.reject(&(&1.rounds == 1))
            |> Enum.sort_by(& &1.rounds)
            |> Enum.map(fn result ->
              "  #{mode}/#{workload}, run #{iteration}, #{result.rounds} rounds / 1 round: " <>
                ratio(result.peak_process_delta_bytes, baseline.peak_process_delta_bytes)
            end)
        end
      end)

    if lines != [] do
      IO.puts("\nPeak process growth from the one-round case:")
      Enum.each(lines, &IO.puts/1)
    end
  end

  defp print_ratios(results) do
    lines =
      results
      |> Enum.group_by(&{&1.mode, &1.rounds, &1.iteration})
      |> Enum.sort()
      |> Enum.flat_map(fn {{mode, rounds, iteration}, cases} ->
        serial = Enum.find(cases, &(&1.workload == "serial"))
        constrained = Enum.find(cases, &(&1.workload == "constrained"))
        parallel = Enum.find(cases, &(&1.workload == "parallel"))

        []
        |> maybe_add_ratio(
          not is_nil(serial) and not is_nil(constrained) and serial.outcome == "completed" and
            constrained.outcome == "completed",
          fn ->
            "  #{mode}, #{rounds} rounds, run #{iteration}, four calls / one call: " <>
              ratio(constrained.peak_process_delta_bytes, serial.peak_process_delta_bytes)
          end
        )
        |> maybe_add_ratio(
          not is_nil(constrained) and not is_nil(parallel) and
            constrained.outcome == "completed" and parallel.outcome == "completed",
          fn ->
            "  #{mode}, #{rounds} rounds, run #{iteration}, parallel / constrained: " <>
              ratio(parallel.peak_process_delta_bytes, constrained.peak_process_delta_bytes)
          end
        )
      end)

    if lines != [] do
      IO.puts("\nPeak process workload ratios:")
      Enum.each(lines, &IO.puts/1)
    end
  end

  defp maybe_add_ratio(lines, true, line), do: lines ++ [line.()]
  defp maybe_add_ratio(lines, false, _line), do: lines

  defp mib(bytes), do: :erlang.float_to_binary(bytes / 1_048_576, decimals: 2) <> " MiB"
  defp kib(bytes), do: :erlang.float_to_binary(bytes / 1_024, decimals: 2) <> " KiB"

  defp signed_mib(bytes) do
    sign = if bytes >= 0, do: "+", else: ""
    sign <> mib(bytes)
  end

  defp maybe_mib(nil), do: "n/a"
  defp maybe_mib(bytes), do: mib(bytes)

  defp ratio(_numerator, 0), do: "n/a"
  defp ratio(numerator, denominator), do: :erlang.float_to_binary(numerator / denominator, decimals: 2) <> "x"

  defp csv_values(name, default, parser) do
    case System.get_env(name) do
      nil -> default
      value -> value |> String.split(",", trim: true) |> Enum.map(parser)
    end
  end

  defp csv_integers(name, default) do
    csv_values(name, default, &integer!/1)
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

  defp integer_in!(value, %Range{first: first, last: last}, _label)
       when is_integer(value) and value >= first and value <= last,
       do: value

  defp integer_in!(value, range, label),
    do: raise("#{label} must be in #{inspect(range)}, got: #{inspect(value)}")

  defp mode!("direct"), do: :direct
  defp mode!("managed"), do: :managed
  defp mode!(mode), do: raise("expected direct or managed mode, got: #{inspect(mode)}")

  defp workload!(name) do
    if Map.has_key?(@workloads, name),
      do: name,
      else: raise("unknown workload #{inspect(name)}; expected one of #{inspect(Map.keys(@workloads))}")
  end

  defp profile!("base"), do: :base
  defp profile!("expanded"), do: :expanded

  defp profile!(profile),
    do: raise("expected base or expanded benchmark profile, got: #{inspect(profile)}")

  defp profile_defaults(:base), do: @base_defaults
  defp profile_defaults(:expanded), do: @expanded_defaults

  defp git_revision do
    with git when is_binary(git) <- System.find_executable("git"),
         {revision, 0} <- System.cmd(git, ["rev-parse", "--short=12", "HEAD"], stderr_to_stdout: true),
         {status, 0} <- System.cmd(git, ["status", "--porcelain", "--untracked-files=no"]) do
      String.trim(revision) <> if(status == "", do: "", else: "-dirty")
    else
      _error -> "unknown"
    end
  end

  defp failure_summary(%Jido.Error.ExecutionError{
         details: %{
           reason:
             {%Runic.Identity.CanonicalError{reason: {:limit, :item_count, item_count}, path: path} = error,
              stacktrace}
         }
       }) do
    %{
      kind: :canonical_identity_item_limit,
      item_count: item_count,
      message: Exception.message(error),
      operation: "Runic.Workflow.Join.finalize/3 -> Runic.Workflow.Fact.new/1",
      path: inspect(path, limit: 20),
      stacktrace: stacktrace |> Enum.take(24) |> Exception.format_stacktrace()
    }
  end

  defp failure_summary(%{message: message}), do: %{kind: :execution_error, message: message}
  defp failure_summary(error), do: %{kind: :execution_error, message: inspect(error, limit: 10)}

  defp failure_line(%{kind: "canonical_identity_item_limit"} = failure) do
    "Runic join result exceeded the canonical identity item limit; " <>
      "#{failure.item_count} items at #{failure.path}"
  end

  defp failure_line(failure), do: inspect(failure)
end

Jido.Bench.ReActMemory.main(System.argv())
