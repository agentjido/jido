defmodule Jido.Quality.Report do
  @moduledoc false

  @suite_targets %{
    "authoring" => "test/authoring",
    "examples" => "test/examples",
    "property" => "test/property",
    "fuzz" => "test/property",
    "system" => "test/system",
    "load" => "test/load",
    "peer" => "test",
    "benchmark_smoke" => "test/bench"
  }

  def evaluate(contract, evidence, metadata) do
    suite_results = map_at(evidence, "suite_results")

    findings =
      []
      |> suite_findings(contract["suites"], suite_results)
      |> covenant_findings(evidence["covenant"], contract)
      |> proof_findings(list_at(evidence, "component_proof_errors"))
      |> coverage_findings(evidence["coverage"], metadata)
      |> stability_findings(list_at(contract, "stability_findings"))
      |> apply_waivers(list_at(contract, "waivers"))
      |> Enum.sort_by(& &1["id"])

    open = Enum.count(findings, &(&1["status"] == "open"))

    %{
      "version" => 1,
      "outcome" => if(open == 0, do: "pass", else: "fail"),
      "metadata" => metadata,
      "thresholds" => contract["thresholds"],
      "suites" => suite_results,
      "covenant" => covenant_summary(evidence["covenant"]),
      "component_proof" => %{
        "status" => if(list_at(evidence, "component_proof_errors") == [], do: "pass", else: "fail"),
        "errors" => list_at(evidence, "component_proof_errors")
      },
      "coverage" => evidence["coverage"],
      "stability_findings" => list_at(contract, "stability_findings"),
      "waivers" => list_at(contract, "waivers"),
      "findings" => findings,
      "open_finding_count" => open
    }
  end

  def text(report) do
    metadata = map_at(report, "metadata")
    covenant = map_at(report, "covenant")
    coverage = map_at(report, "coverage")
    package = map_at(coverage, "package")

    suites =
      report
      |> map_at("suites")
      |> Enum.sort()
      |> Enum.map(fn {id, result} ->
        "#{id}: #{String.upcase(result["outcome"] || "missing")} (#{result["owner"] || "unowned"})"
      end)

    findings =
      report
      |> list_at("findings")
      |> Enum.map(fn finding ->
        waiver = if finding["waiver_id"], do: " [waiver #{finding["waiver_id"]}]", else: ""
        "#{String.upcase(finding["status"])} #{finding["id"]}: #{finding["message"]}#{waiver}"
      end)

    waivers =
      report
      |> list_at("waivers")
      |> Enum.map(&"#{&1["id"]}: #{&1["finding_id"]} expires #{&1["expires_on"]}")

    ([
       "Jido quality report",
       "Outcome: #{String.upcase(report["outcome"])}",
       "Revision: #{metadata["revision"]}",
       "Dirty: #{metadata["dirty"]}",
       "Runtime: Elixir #{metadata["elixir"]}, OTP #{metadata["otp"]}",
       "Covenant: #{covenant["covered"] || 0}/#{covenant["active"] || 0}",
       "Line coverage: #{package["percent"] || 0}%",
       "",
       "Suites"
     ] ++ suites ++ ["", "Findings"] ++ empty_message(findings) ++ ["", "Waivers"] ++ empty_message(waivers))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  def run!(root, args \\ []) do
    contract_path = Path.join(root, "test/quality/quality_contract.yml")
    contract = Jido.Quality.Contract.load!(contract_path)
    Jido.Quality.Contract.validate!(contract, root)

    suite_results =
      if "--no-run" in args do
        load_suite_results(contract, root)
      else
        run_suites(contract, root)
      end

    proof_path = Path.join(root, contract["registries"]["component_proof"])
    proof = Jido.Quality.ComponentProof.load!(proof_path)
    proof_errors = Jido.Quality.ComponentProof.validate(proof, root)
    coverage = read_json(Path.join(root, "tmp/quality/coverage/coverage.json"))
    covenant = read_json(Path.join(root, "test/contracts/coverage.json"))
    metadata = metadata(root)

    evidence = %{
      "suite_results" => suite_results,
      "component_proof_errors" => proof_errors,
      "coverage" => coverage,
      "covenant" => covenant
    }

    report = evaluate(contract, evidence, metadata)
    json_path = Path.join(root, contract["reports"]["json"])
    text_path = Path.join(root, contract["reports"]["text"])
    write_json(json_path, report)
    File.write!(text_path, text(report))
    Mix.shell().info(text(report))

    if report["outcome"] != "pass" do
      open = for finding <- report["findings"], finding["status"] == "open", do: finding["message"]
      raise "quality report failed:\n- #{Enum.join(open, "\n- ")}"
    end

    report
  end

  defp run_suites(contract, root) do
    output_root = Path.join(root, "tmp/quality/suites")
    File.rm_rf!(output_root)
    File.mkdir_p!(Path.join(output_root, "logs"))

    contract["suites"]
    |> Enum.filter(&(&1["state"] == "required"))
    |> Map.new(fn suite ->
      id = suite["id"]
      started_at = DateTime.utc_now() |> DateTime.to_iso8601()
      available = target_available?(root, id)

      {output, exit_status} =
        if available do
          mix = System.find_executable("mix") || raise "mix executable is not available"

          System.cmd(mix, suite_command(suite),
            cd: root,
            env: [{"MIX_ENV", "test"}],
            stderr_to_stdout: true
          )
        else
          {"No applicable #{id} target exists.\n", 0}
        end

      log_path = Path.join([output_root, "logs", "#{id}.log"])
      File.write!(log_path, output)

      result = %{
        "suite" => id,
        "alias" => suite["alias"],
        "owner" => suite["owner"],
        "outcome" => if(exit_status == 0, do: "pass", else: "fail"),
        "exit_status" => exit_status,
        "selection" => if(available, do: "executed", else: "not_applicable"),
        "seed" => suite["seed"],
        "started_at" => started_at,
        "finished_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "revision" => git(root, ["rev-parse", "HEAD"]),
        "log" => Path.relative_to(log_path, root)
      }

      result_path = suite_result_path(root, suite)
      write_json(result_path, result)

      artifacts =
        Enum.map(suite["evidence_artifacts"], fn path ->
          %{"path" => path, "exists" => File.regular?(Path.join(root, path))}
        end)

      result = Map.put(result, "artifacts", artifacts)
      write_json(result_path, result)
      {id, result}
    end)
  end

  defp load_suite_results(contract, root) do
    contract["suites"]
    |> Enum.filter(&(&1["state"] == "required"))
    |> Map.new(fn suite ->
      {suite["id"], read_json(suite_result_path(root, suite))}
    end)
  end

  defp suite_result_path(root, suite) do
    suite["evidence_artifacts"]
    |> Enum.find(&String.starts_with?(&1, "tmp/quality/suites/"))
    |> case do
      nil -> Path.join([root, "tmp/quality/suites/results", "#{suite["id"]}.json"])
      path -> Path.join(root, path)
    end
  end

  defp suite_command(%{"alias" => "test", "seed" => seed}),
    do: ["test", "--seed", to_string(seed)]

  defp suite_command(suite), do: [suite["alias"]]

  defp target_available?(_root, id) when id in ["unit", "covenant"], do: true

  defp target_available?(root, id) do
    case @suite_targets[id] do
      nil -> true
      path -> File.exists?(Path.join(root, path))
    end
  end

  defp suite_findings(findings, suites, results) do
    suites
    |> Enum.filter(&(&1["state"] == "required"))
    |> Enum.reduce(findings, fn suite, current ->
      id = suite["id"]
      owner = suite["owner"]

      case results[id] do
        nil ->
          [finding("suite:#{id}:missing", owner, "required suite #{id} has no result", suite: id) | current]

        result ->
          current =
            if result["outcome"] == "pass" do
              current
            else
              [finding("suite:#{id}:failed", owner, "required suite #{id} failed", suite: id) | current]
            end

          result
          |> list_at("artifacts")
          |> Enum.reject(& &1["exists"])
          |> Enum.reduce(current, fn artifact, artifact_findings ->
            message = "required suite #{id} is missing artifact #{artifact["path"]}"
            [finding("suite:#{id}:artifact:#{artifact["path"]}", owner, message, suite: id) | artifact_findings]
          end)
      end
    end)
  end

  defp covenant_findings(findings, nil, _contract) do
    [finding("covenant:missing", "jido.contracts", "Covenant coverage evidence is missing") | findings]
  end

  defp covenant_findings(findings, covenant, contract) do
    totals = map_at(covenant, "totals")
    required = contract["thresholds"]["covenant"]["obligation_coverage_percent"]
    percent = number(totals["coverage"]) * 100

    component_findings =
      for {id, component} <- map_at(covenant, "components"), number(component["coverage"]) < 1.0 do
        finding("covenant:component:#{id}", id, "Covenant component #{id} has an obligation gap", component: id)
      end

    if percent < required or totals["active"] != totals["covered"] do
      [
        finding("covenant:coverage", "jido.contracts", "Covenant obligation coverage is #{percent}%")
        | component_findings ++ findings
      ]
    else
      component_findings ++ findings
    end
  end

  defp proof_findings(findings, errors) do
    Enum.with_index(errors, 1)
    |> Enum.reduce(findings, fn {error, index}, current ->
      [finding("component-proof:#{index}", "jido.components", "component proof gap: #{error}") | current]
    end)
  end

  defp coverage_findings(findings, nil, _metadata) do
    [finding("coverage:missing", "jido.coverage", "line coverage evidence is missing") | findings]
  end

  defp coverage_findings(findings, coverage, metadata) do
    coverage_metadata = map_at(coverage, "metadata")

    findings =
      if coverage_metadata["revision"] == metadata["revision"] and
           coverage_metadata["dirty"] == metadata["dirty"] do
        findings
      else
        [
          finding(
            "coverage:stale",
            "jido.coverage",
            "line coverage evidence does not match the current revision and dirty state"
          )
          | findings
        ]
      end

    coverage
    |> list_at("errors")
    |> Enum.with_index(1)
    |> Enum.reduce(findings, fn {error, index}, current ->
      component = component_from_error(error)
      owner = component || "jido.coverage"
      [finding("coverage:#{index}", owner, "coverage gap: #{error}", component: component) | current]
    end)
  end

  defp stability_findings(findings, stability) do
    stability
    |> Enum.filter(&(&1["status"] == "unresolved"))
    |> Enum.reduce(findings, fn record, current ->
      item =
        finding(record["id"], record["owner"], record["reason"],
          component: record["component"],
          suite: record["suite_id"],
          source: "stability"
        )

      [item | current]
    end)
  end

  defp apply_waivers(findings, waivers) do
    by_finding = Map.new(waivers, &{&1["finding_id"], &1})

    Enum.map(findings, fn finding ->
      case by_finding[finding["id"]] do
        nil -> finding
        waiver -> Map.merge(finding, %{"status" => "waived", "waiver_id" => waiver["id"]})
      end
    end)
  end

  defp finding(id, owner, message, options \\ []) do
    %{
      "id" => id,
      "owner" => owner,
      "message" => message,
      "status" => "open",
      "component" => Keyword.get(options, :component),
      "suite" => Keyword.get(options, :suite),
      "source" => Keyword.get(options, :source, "evidence")
    }
  end

  defp covenant_summary(nil), do: %{"status" => "missing"}

  defp covenant_summary(covenant) do
    totals = map_at(covenant, "totals")

    %{
      "status" => if(totals["active"] == totals["covered"], do: "pass", else: "fail"),
      "active" => totals["active"],
      "covered" => totals["covered"],
      "percent" => number(totals["coverage"]) * 100
    }
  end

  defp metadata(root) do
    %{
      "revision" => git(root, ["rev-parse", "HEAD"]),
      "dirty" => git(root, ["status", "--porcelain"]) != "",
      "elixir" => System.version(),
      "otp" => System.otp_release()
    }
  end

  defp read_json(path) do
    if File.regular?(path), do: path |> File.read!() |> Jason.decode!(), else: nil
  end

  defp write_json(path, value) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode_to_iodata!(value, pretty: true))
  end

  defp git(root, args) do
    case System.cmd("git", args, cd: root, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {_output, _status} -> "unknown"
    end
  end

  defp component_from_error(error) do
    case Regex.run(~r/^component ([^ ]+)/, error) do
      [_, component] -> component
      _other -> nil
    end
  end

  defp empty_message([]), do: ["None"]
  defp empty_message(values), do: values
  defp number(value) when is_number(value), do: value * 1.0
  defp number(_value), do: 0.0
  defp list_at(map, key) when is_map(map), do: Map.get(map, key, [])
  defp list_at(_map, _key), do: []
  defp map_at(map, key) when is_map(map), do: Map.get(map, key, %{})
  defp map_at(_map, _key), do: %{}
end
