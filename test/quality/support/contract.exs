defmodule Jido.Quality.Contract do
  @moduledoc false

  @minimum_package_coverage 90
  @minimum_component_coverage 80
  @maximum_component_regression 0.5
  @required_covenant_coverage 100

  def load!(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, contract} -> contract
      {:error, error} -> raise "cannot read quality contract: #{inspect(error)}"
    end
  end

  def validate(contract, root, today \\ Date.utc_today()) do
    schema = map(contract["schema"])
    suites = list(contract["suites"])
    waivers = list(contract["waivers"])
    findings = list(contract["stability_findings"])

    []
    |> validate_top_level(contract, list(schema["required_top_level_fields"]))
    |> validate_suite_fields(suites, list(schema["suite_required_fields"]))
    |> validate_suite_ids(suites)
    |> validate_suite_states(suites, list(schema["suite_states"]))
    |> validate_required_suites(suites, list(schema["required_suite_ids"]))
    |> validate_coverage_states(suites, list(schema["coverage_states"]))
    |> validate_aliases(suites)
    |> validate_suite_artifacts(suites, root)
    |> validate_thresholds(map(contract["thresholds"]))
    |> validate_fuzz(map(contract["fuzz"]))
    |> validate_reports(map(contract["reports"]), root)
    |> validate_registries(map(contract["registries"]), root)
    |> validate_waivers(waivers, list(schema["waiver_required_fields"]), today, findings)
    |> validate_stability_findings(
      findings,
      list(schema["stability_required_fields"]),
      list(schema["stability_statuses"]),
      suites
    )
    |> Enum.sort()
  end

  def validate!(contract, root, today \\ Date.utc_today()) do
    case validate(contract, root, today) do
      [] -> :ok
      errors -> raise "invalid quality contract:\n- #{Enum.join(errors, "\n- ")}"
    end
  end

  defp validate_top_level(errors, contract, fields) do
    Enum.reduce(fields, errors, fn field, current ->
      add_unless(current, Map.has_key?(contract, field), "contract is missing #{field}")
    end)
  end

  defp validate_suite_fields(errors, suites, fields) do
    suites
    |> Enum.with_index(1)
    |> Enum.reduce(errors, fn {suite, index}, current ->
      Enum.reduce(fields, current, fn field, field_errors ->
        add_unless(
          field_errors,
          present?(suite[field]),
          "#{suite_name(suite, index)} is missing #{field}"
        )
      end)
    end)
  end

  defp validate_suite_ids(errors, suites) do
    suites
    |> Enum.map(& &1["id"])
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.reduce(errors, fn
      {id, count}, current when count > 1 -> ["duplicate suite id: #{id}" | current]
      {_id, _count}, current -> current
    end)
  end

  defp validate_suite_states(errors, suites, states) do
    Enum.reduce(suites, errors, fn suite, current ->
      add_unless(
        current,
        suite["state"] in states,
        "suite #{suite["id"] || "<unknown>"} has unknown state: #{inspect(suite["state"])}"
      )
    end)
  end

  defp validate_required_suites(errors, suites, required_ids) do
    by_id = Map.new(suites, &{&1["id"], &1})

    Enum.reduce(required_ids, errors, fn id, current ->
      case by_id[id] do
        %{"state" => "required"} -> current
        nil -> ["required suite is missing: #{id}" | current]
        _suite -> ["required suite is not required: #{id}" | current]
      end
    end)
  end

  defp validate_coverage_states(errors, suites, states) do
    Enum.reduce(suites, errors, fn suite, current ->
      add_unless(
        current,
        suite["coverage"] in states,
        "suite #{suite["id"] || "<unknown>"} has unknown coverage state: #{inspect(suite["coverage"])}"
      )
    end)
  end

  defp validate_aliases(errors, suites) do
    available = Mix.Project.config()[:aliases] |> Keyword.keys() |> Enum.map(&to_string/1)

    Enum.reduce(suites, errors, fn suite, current ->
      alias_name = suite["alias"]

      add_unless(
        current,
        alias_name == "test" or alias_name in available,
        "suite #{suite["id"] || "<unknown>"} has unknown alias: #{inspect(alias_name)}"
      )
    end)
  end

  defp validate_suite_artifacts(errors, suites, root) do
    Enum.reduce(suites, errors, fn suite, current ->
      artifacts = list(suite["evidence_artifacts"])
      id = suite["id"] || "<unknown>"

      current
      |> add_unless(artifacts != [], "suite #{id} has no evidence artifacts")
      |> validate_paths(artifacts, root, "suite #{id} evidence artifact")
    end)
  end

  defp validate_thresholds(errors, thresholds) do
    lines = map(thresholds["line_coverage"])
    covenant = map(thresholds["covenant"])

    errors
    |> validate_minimum(
      lines["package_minimum_percent"],
      @minimum_package_coverage,
      "package line coverage"
    )
    |> validate_minimum(
      lines["component_minimum_percent"],
      @minimum_component_coverage,
      "component line coverage"
    )
    |> validate_range(
      lines["maximum_component_regression_points"],
      0,
      @maximum_component_regression,
      "maximum component regression"
    )
    |> add_unless(
      covenant["obligation_coverage_percent"] == @required_covenant_coverage,
      "Covenant obligation coverage must equal #{@required_covenant_coverage}"
    )
  end

  defp validate_fuzz(errors, fuzz) do
    errors
    |> add_unless(fuzz["required_seed"] == 0, "fuzz required_seed must equal 0")
    |> add_unless(fuzz["bounded_generators"] == true, "fuzz generators must be bounded")
    |> add_unless(
      fuzz["replayable_reduced_inputs"] == true,
      "fuzz reduced inputs must be replayable"
    )
    |> add_unless(fuzz["complete_reports"] == true, "fuzz reports must be complete")
  end

  defp validate_reports(errors, reports, root) do
    values = Enum.map(["root", "json", "text"], &reports[&1])

    errors
    |> add_unless(Enum.all?(values, &present?/1), "reports must declare root, json, and text paths")
    |> add_unless(reports["json"] != reports["text"], "JSON and text report paths must differ")
    |> validate_paths(values, root, "report path")
  end

  defp validate_registries(errors, registries, root) do
    paths = Map.values(registries)

    errors
    |> add_unless(present?(registries["component_proof"]), "registries must declare component_proof")
    |> add_unless(
      present?(registries["coverage_baseline"]),
      "registries must declare coverage_baseline"
    )
    |> validate_paths(paths, root, "registry path")
    |> then(fn current ->
      Enum.reduce(paths, current, fn path, path_errors ->
        add_unless(
          path_errors,
          repository_path?(path, root) and File.regular?(Path.join(root, path)),
          "registry does not exist: #{inspect(path)}"
        )
      end)
    end)
  end

  defp validate_waivers(errors, waivers, fields, today, findings) do
    findings_by_id = Map.new(findings, &{&1["id"], &1})

    waivers
    |> Enum.with_index(1)
    |> Enum.reduce(errors, fn {waiver, index}, current ->
      name = "waiver #{waiver["id"] || index}"

      current
      |> validate_record_fields(waiver, fields, name)
      |> validate_expiry(waiver["expires_on"], today, name)
      |> add_unless(
        Map.has_key?(findings_by_id, waiver["finding_id"]),
        "#{name} has unknown finding_id"
      )
      |> add_unless(
        is_nil(findings_by_id[waiver["finding_id"]]) or
          findings_by_id[waiver["finding_id"]]["owner"] == waiver["owner"],
        "#{name} owner does not match its finding"
      )
    end)
  end

  defp validate_stability_findings(errors, findings, fields, statuses, suites) do
    suite_ids = Enum.map(suites, & &1["id"])

    findings
    |> Enum.with_index(1)
    |> Enum.reduce(errors, fn {finding, index}, current ->
      name = "stability finding #{finding["id"] || index}"

      current
      |> validate_record_fields(finding, fields, name)
      |> add_unless(finding["status"] in statuses, "#{name} has unknown status")
      |> add_unless(finding["suite_id"] in suite_ids, "#{name} has unknown suite_id")
      |> validate_date(finding["observed_on"], "#{name} observed_on")
    end)
  end

  defp validate_record_fields(errors, record, fields, name) do
    Enum.reduce(fields, errors, fn field, current ->
      add_unless(current, present?(record[field]), "#{name} is missing #{field}")
    end)
  end

  defp validate_expiry(errors, value, today, name) do
    case parse_date(value) do
      {:ok, date} -> add_unless(errors, Date.compare(date, today) != :lt, "#{name} is expired")
      :error -> ["#{name} has invalid expires_on" | errors]
    end
  end

  defp validate_date(errors, value, name) do
    case parse_date(value) do
      {:ok, _date} -> errors
      :error -> ["#{name} is invalid" | errors]
    end
  end

  defp validate_minimum(errors, value, minimum, name) do
    add_unless(errors, is_number(value) and value >= minimum, "#{name} must be at least #{minimum}")
  end

  defp validate_range(errors, value, minimum, maximum, name) do
    add_unless(
      errors,
      is_number(value) and value >= minimum and value <= maximum,
      "#{name} must be between #{minimum} and #{maximum}"
    )
  end

  defp validate_paths(errors, paths, root, label) do
    Enum.reduce(paths, errors, fn path, current ->
      add_unless(current, repository_path?(path, root), "#{label} leaves the repository: #{inspect(path)}")
    end)
  end

  defp repository_path?(path, root) when is_binary(path) do
    expanded_root = Path.expand(root)
    expanded_path = Path.expand(path, expanded_root)

    Path.type(path) != :absolute and
      expanded_path != expanded_root and
      String.starts_with?(expanded_path, expanded_root <> "/")
  end

  defp repository_path?(_path, _root), do: false

  defp parse_date(%Date{} = date), do: {:ok, date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  defp parse_date(_value), do: :error

  defp suite_name(suite, index), do: "suite #{suite["id"] || index}"

  defp add_unless(errors, true, _error), do: errors
  defp add_unless(errors, false, error), do: [error | errors]

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(value) when is_map(value), do: map_size(value) > 0
  defp present?(value), do: not is_nil(value)

  defp list(value) when is_list(value), do: value
  defp list(_value), do: []
  defp map(value) when is_map(value), do: value
  defp map(_value), do: %{}
end
