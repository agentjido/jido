defmodule Jido.Quality.Coverage do
  @moduledoc false

  @suite_specs %{
    "unit" => %{args: []},
    "authoring" => %{path: "test/authoring", tag: "authoring"},
    "covenant" => %{args: []},
    "examples" => %{path: "test/examples", tag: "example"},
    "property" => %{path: "test/property", tag: "property"},
    "fuzz" => %{path: "test/property", tag: "fuzz"},
    "system" => %{path: "test/system", tag: "system"},
    "load" => %{path: "test/perf", tag: "load"},
    "peer" => %{path: "test", tag: "peer"},
    "benchmark_smoke" => %{path: "test/perf", tag: "bench"}
  }

  def aggregate(suites, baseline, thresholds, options \\ []) do
    component_ids = Keyword.get(options, :components, baseline |> map_at("components") |> Map.keys())
    {lines, ownership_errors} = union_lines(suites)
    package = metric(lines)
    components = component_metrics(lines, component_ids)
    contributions = suite_contributions(suites)

    errors =
      ownership_errors ++
        threshold_errors(package, components, baseline, thresholds)

    %{
      "status" => if(errors == [], do: "pass", else: "fail"),
      "complete" => true,
      "package" => package,
      "components" => components,
      "suites" => contributions,
      "errors" => Enum.sort(errors)
    }
  end

  def normalize_export(json_path, coverdata_path, owners, coverage_owners, root, suite_id) do
    source_files = json_path |> File.read!() |> Jason.decode!() |> Map.fetch!("source_files")

    relevant =
      for source <- source_files,
          file = repository_source(source["name"], root),
          not is_nil(file),
          {count, index} <- Enum.with_index(source["coverage"], 1),
          not is_nil(count),
          into: %{} do
        {"#{file}:#{index}", %{"covered" => count > 0, "file" => file, "line" => index}}
      end

    {line_owners, file_owners, line_components, file_components} =
      cover_owners(coverdata_path, owners, coverage_owners, root)

    {lines, errors} =
      Enum.reduce(relevant, {%{}, []}, fn {identity, line}, {current, errors} ->
        candidates =
          line_owners
          |> Map.get(identity, Map.get(file_owners, line["file"], []))
          |> Enum.uniq()
          |> Enum.sort()

        case candidates do
          [component] ->
            components =
              line_components
              |> Map.get(identity, Map.get(file_components, line["file"], [component]))
              |> Enum.uniq()
              |> Enum.sort()

            value = %{
              "component" => component,
              "components" => components,
              "covered" => line["covered"]
            }

            {Map.put(current, identity, value), errors}

          [] ->
            {current, ["#{suite_id} line #{identity} has no component owner" | errors]}

          components ->
            message = "#{suite_id} line #{identity} has multiple component owners: #{Enum.join(components, ", ")}"
            {current, [message | errors]}
        end
      end)

    %{
      "suite" => suite_id,
      "status" => if(errors == [], do: "pass", else: "fail"),
      "complete" => true,
      "lines" => lines,
      "errors" => Enum.sort(errors)
    }
  end

  def empty_suite(suite_id) do
    %{"suite" => suite_id, "status" => "pass", "complete" => true, "lines" => %{}, "errors" => []}
  end

  def baseline_candidate(report, revision) do
    components =
      Map.new(report["components"], fn {id, metric} ->
        {id, %{"baseline_percent" => metric["percent"], "floor_percent" => 80.0}}
      end)

    %{
      "version" => 1,
      "revision" => revision,
      "thresholds" => %{
        "package_minimum_percent" => 90.0,
        "component_minimum_percent" => 80.0,
        "maximum_component_regression_points" => 0.5
      },
      "components" => components
    }
  end

  def validate_baseline(baseline, component_ids, thresholds) do
    expected = Enum.sort(component_ids)
    actual = baseline |> map_at("components") |> Map.keys() |> Enum.sort()
    baseline_thresholds = map_at(baseline, "thresholds")
    minimum = number(thresholds["component_minimum_percent"])

    errors =
      []
      |> add_unless(baseline["version"] == 1, "coverage baseline version must equal 1")
      |> add_unless(
        is_binary(baseline["revision"]) and Regex.match?(~r/^[0-9a-f]{40}$/, baseline["revision"]),
        "coverage baseline revision must be a full Git SHA"
      )
      |> add_unless(actual == expected, "coverage baseline component inventory does not match component proof")
      |> add_unless(
        baseline_thresholds == %{
          "package_minimum_percent" => number(thresholds["package_minimum_percent"]),
          "component_minimum_percent" => minimum,
          "maximum_component_regression_points" => number(thresholds["maximum_component_regression_points"])
        },
        "coverage baseline thresholds do not match the quality contract"
      )

    baseline
    |> map_at("components")
    |> Enum.reduce(errors, fn {id, entry}, current ->
      baseline_percent = entry["baseline_percent"]
      floor_percent = entry["floor_percent"]

      current
      |> add_unless(valid_percent?(baseline_percent), "component #{id} has an invalid baseline percent")
      |> add_unless(
        valid_percent?(floor_percent) and number(floor_percent) >= minimum,
        "component #{id} has an invalid coverage floor"
      )
    end)
    |> Enum.sort()
  end

  def run!(root, args \\ []) do
    contract_path = Path.join(root, "test/quality/quality_contract.yml")
    proof_path = Path.join(root, "test/quality/component_proof.yml")
    baseline_path = Path.join(root, "test/quality/coverage_baseline.json")
    output_root = Path.join(root, "tmp/quality/coverage")
    baseline_candidate? = "--baseline-candidate" in args

    contract = Jido.Quality.Contract.load!(contract_path)
    Jido.Quality.Contract.validate!(contract, root)
    proof = Jido.Quality.ComponentProof.load!(proof_path)
    [] = Jido.Quality.ComponentProof.validate(proof, root)
    {owners, []} = Jido.Quality.ComponentProof.ownership(proof, root)
    coverage_owners = Jido.Quality.ComponentProof.coverage_owners(proof, root)
    component_ids = proof["components"] |> Enum.map(& &1["id"]) |> Enum.sort()

    File.rm_rf!(output_root)
    File.mkdir_p!(Path.join(output_root, "suites"))
    File.mkdir_p!(Path.join(output_root, "coverdata"))

    suites =
      contract["suites"]
      |> Enum.filter(&(&1["state"] == "required" and &1["coverage"] == "included"))
      |> Enum.map(fn suite ->
        run_suite(root, output_root, suite["id"], owners, coverage_owners)
      end)

    baseline =
      if File.regular?(baseline_path) do
        baseline_path |> File.read!() |> Jason.decode!()
      else
        %{
          "components" => Map.new(component_ids, &{&1, %{"baseline_percent" => 0.0, "floor_percent" => 80.0}})
        }
      end

    if File.regular?(baseline_path) do
      case validate_baseline(baseline, component_ids, contract["thresholds"]["line_coverage"]) do
        [] -> :ok
        errors -> raise "invalid coverage baseline:\n- #{Enum.join(errors, "\n- ")}"
      end
    end

    thresholds = contract["thresholds"]["line_coverage"]
    report = aggregate(suites, baseline, thresholds, components: component_ids)
    revision = git(root, ["rev-parse", "HEAD"])

    report =
      Map.put(report, "metadata", %{
        "revision" => revision,
        "dirty" => git(root, ["status", "--porcelain"]) != "",
        "elixir" => System.version(),
        "otp" => System.otp_release()
      })

    write_json(Path.join(output_root, "coverage.json"), report)
    File.write!(Path.join(output_root, "coverage.txt"), text_report(report))

    if baseline_candidate? do
      candidate = baseline_candidate(report, revision)
      write_json(Path.join(output_root, "baseline-candidate.json"), candidate)
    end

    unless report["status"] == "pass" or baseline_candidate? do
      raise "quality coverage failed:\n- #{Enum.join(report["errors"], "\n- ")}"
    end

    Mix.shell().info(text_report(report))
    report
  end

  defp run_suite(root, output_root, suite_id, owners, coverage_owners) do
    spec = Map.fetch!(@suite_specs, suite_id)
    suite_dir = Path.join([output_root, "suites", suite_id])
    File.mkdir_p!(suite_dir)

    if runnable?(root, spec) do
      mix = System.find_executable("mix") || raise "mix executable is not available"
      export_name = suite_id
      command_args = coverage_args(spec, suite_dir, export_name)

      {output, status} =
        System.cmd(mix, command_args,
          cd: root,
          env: [{"MIX_ENV", "test"}],
          stderr_to_stdout: true
        )

      File.write!(Path.join(suite_dir, "command.log"), output)

      if status != 0 do
        raise "coverage suite #{suite_id} failed with status #{status}; see #{Path.relative_to_cwd(Path.join(suite_dir, "command.log"))}"
      end

      json_path = Path.join(suite_dir, "#{export_name}.json")
      coverdata_path = Path.join([output_root, "coverdata", "#{export_name}.coverdata"])

      report =
        normalize_export(json_path, coverdata_path, owners, coverage_owners, root, suite_id)

      write_json(Path.join(suite_dir, "coverage.json"), report)

      if report["errors"] != [] do
        raise "coverage suite #{suite_id} has invalid ownership:\n- #{Enum.join(report["errors"], "\n- ")}"
      end

      report
    else
      report = empty_suite(suite_id)
      write_json(Path.join(suite_dir, "#{suite_id}.json"), %{"source_files" => []})
      write_json(Path.join(suite_dir, "coverage.json"), report)
      report
    end
  end

  defp runnable?(_root, %{args: _args}), do: true
  defp runnable?(root, %{path: path}), do: File.exists?(Path.join(root, path))

  defp coverage_args(spec, suite_dir, export_name) do
    base = [
      "coveralls.json",
      "--output-dir",
      suite_dir,
      "--export-coverage",
      export_name,
      "--seed",
      "0"
    ]

    case spec do
      %{path: path, tag: tag} -> base ++ ["--only", tag, path]
      %{args: args} -> base ++ args
    end
  end

  defp repository_source(source, root) when is_binary(source) do
    root = Path.expand(root)
    expanded = Path.expand(source, root)
    lib_root = Path.join(root, "lib")

    if String.starts_with?(expanded, lib_root <> "/"), do: Path.relative_to(expanded, root)
  end

  defp repository_source(_source, _root), do: nil

  defp cover_owners(coverdata_path, owners, coverage_owners, root) do
    silence_output(fn ->
      {:ok, _pid} = :cover.start()
      :ok = :cover.import(String.to_charlist(coverdata_path))

      result =
        Enum.reduce(owners, {%{}, %{}, %{}, %{}}, fn {module_name, component},
                                                     {line_owners, file_owners, line_components, file_components} ->
          module = Module.concat([module_name])
          components = Map.get(coverage_owners, module_name, [component]) |> Enum.uniq()

          with compile when is_list(compile) <- module.module_info(:compile),
               source when not is_nil(source) <- compile[:source],
               file <- source |> to_string() |> Path.relative_to(root),
               true <- String.starts_with?(file, "lib/"),
               {:ok, line_calls} <- :cover.analyse(module, :calls, :line) do
            file_owners = Map.update(file_owners, file, [component], &[component | &1])

            file_components =
              Map.update(file_components, file, components, &(components ++ &1))

            {line_owners, line_components} =
              Enum.reduce(line_calls, {line_owners, line_components}, fn {{^module, line}, _count},
                                                                         {current_owners, current_components} ->
                identity = "#{file}:#{line}"

                {
                  Map.update(current_owners, identity, [component], &[component | &1]),
                  Map.update(current_components, identity, components, &(components ++ &1))
                }
              end)

            {line_owners, file_owners, line_components, file_components}
          else
            _other -> {line_owners, file_owners, line_components, file_components}
          end
        end)

      :cover.stop()
      result
    end)
  end

  defp silence_output(fun) do
    {:ok, capture} = StringIO.open("")
    original = Process.group_leader()
    true = Process.group_leader(self(), capture)

    try do
      fun.()
    after
      Process.group_leader(self(), original)
      StringIO.close(capture)
    end
  end

  defp union_lines(suites) do
    Enum.reduce(suites, {%{}, []}, fn suite, {current, errors} ->
      Enum.reduce(map_at(suite, "lines"), {current, errors}, fn {identity, line}, {lines, line_errors} ->
        line_component = line["component"]

        case {line_component, lines[identity]} do
          {component, _existing} when not is_binary(component) or component == "" ->
            {lines, ["line #{identity} has no component owner" | line_errors]}

          {_component, nil} ->
            value = %{
              "component" => line["component"],
              "components" => coverage_components(line),
              "covered" => line["covered"],
              "covered_by" => if(line["covered"], do: [suite["suite"]], else: [])
            }

            {Map.put(lines, identity, value), line_errors}

          {component, %{"component" => existing_component}}
          when existing_component != component ->
            message = "line #{identity} maps to both #{existing_component} and #{component}"
            {lines, [message | line_errors]}

          {_component, existing} ->
            components = Enum.uniq(existing["components"] ++ coverage_components(line))

            covered_by =
              if line["covered"],
                do: Enum.uniq([suite["suite"] | existing["covered_by"]]),
                else: existing["covered_by"]

            value = %{
              existing
              | "components" => components,
                "covered" => existing["covered"] or line["covered"],
                "covered_by" => covered_by
            }

            {Map.put(lines, identity, value), line_errors}
        end
      end)
    end)
  end

  defp component_metrics(lines, component_ids) do
    Map.new(component_ids, fn component ->
      owned =
        Map.filter(lines, fn {_identity, line} -> component in coverage_components(line) end)

      {component, metric(owned)}
    end)
  end

  defp coverage_components(line) do
    case line["components"] do
      components when is_list(components) and components != [] -> components
      _other -> [line["component"]]
    end
  end

  defp suite_contributions(suites) do
    covered_by =
      for suite <- suites,
          {identity, %{"covered" => true}} <- map_at(suite, "lines"),
          reduce: %{} do
        current -> Map.update(current, identity, [suite["suite"]], &[suite["suite"] | &1])
      end

    Map.new(suites, fn suite ->
      id = suite["suite"]
      total = Enum.count(covered_by, fn {_line, ids} -> id in ids end)
      unique = Enum.count(covered_by, fn {_line, ids} -> ids == [id] end)

      {id,
       %{
         "covered_lines" => total,
         "unique_covered_lines" => unique,
         "relevant_lines" => map_size(map_at(suite, "lines"))
       }}
    end)
  end

  defp metric(lines) do
    relevant = map_size(lines)
    covered = Enum.count(lines, fn {_identity, line} -> line["covered"] end)
    percent = if relevant == 0, do: 0.0, else: Float.round(covered * 100 / relevant, 4)
    %{"relevant_lines" => relevant, "covered_lines" => covered, "percent" => percent}
  end

  defp threshold_errors(package, components, baseline, thresholds) do
    package_minimum = number(thresholds["package_minimum_percent"])
    component_minimum = number(thresholds["component_minimum_percent"])
    maximum_regression = number(thresholds["maximum_component_regression_points"])

    package_errors =
      if package["percent"] < package_minimum,
        do: ["package coverage #{package["percent"]}% is below #{package_minimum}%"],
        else: []

    Enum.reduce(components, package_errors, fn {id, metric}, errors ->
      expected = map_at(map_at(baseline, "components"), id)
      floor = number(expected["floor_percent"] || component_minimum)
      prior = number(expected["baseline_percent"])
      percent = metric["percent"]

      errors =
        if metric["relevant_lines"] == 0,
          do: ["component #{id} has no line coverage evidence" | errors],
          else: errors

      errors =
        if percent < component_minimum,
          do: ["component #{id} coverage #{percent}% is below #{component_minimum}%" | errors],
          else: errors

      errors =
        if percent < floor,
          do: ["component #{id} coverage #{percent}% is below its #{floor}% floor" | errors],
          else: errors

      if prior - percent > maximum_regression do
        ["component #{id} regressed #{Float.round(prior - percent, 4)} points from #{prior}%" | errors]
      else
        errors
      end
    end)
  end

  defp text_report(report) do
    package = report["package"]

    component_lines =
      report["components"]
      |> Enum.sort()
      |> Enum.map(fn {id, metric} ->
        "#{id}: #{metric["percent"]}% (#{metric["covered_lines"]}/#{metric["relevant_lines"]})"
      end)

    suite_lines =
      report["suites"]
      |> Enum.sort()
      |> Enum.map(fn {id, metric} ->
        "#{id}: total #{metric["covered_lines"]}, unique #{metric["unique_covered_lines"]}"
      end)

    error_lines = Enum.map(report["errors"], &"FAIL: #{&1}")

    ([
       "Quality coverage: #{String.upcase(report["status"])}",
       "Package: #{package["percent"]}% (#{package["covered_lines"]}/#{package["relevant_lines"]})",
       "",
       "Components"
     ] ++ component_lines ++ ["", "Suite contribution"] ++ suite_lines ++ [""] ++ error_lines)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
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

  defp map_at(map, key) when is_map(map), do: Map.get(map, key, %{})
  defp map_at(_value, _key), do: %{}
  defp valid_percent?(value), do: is_number(value) and value >= 0 and value <= 100
  defp add_unless(errors, true, _message), do: errors
  defp add_unless(errors, false, message), do: [message | errors]
  defp number(value) when is_integer(value), do: value * 1.0
  defp number(value) when is_float(value), do: value
  defp number(_value), do: 0.0
end
