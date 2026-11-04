Code.require_file("catalog.exs", __DIR__)

defmodule Jido.Bench.Result do
  @moduledoc false

  alias Jido.Bench.Catalog

  @schema_version 1
  @required_metadata ~w(benchmark_id component components owner workload limiter profile input_size concurrency warmup sample_count metrics units git_revision checkout_dirty elixir otp seed)

  def schema_version, do: @schema_version

  def metadata(benchmark_id, profile, overrides \\ %{}) do
    entry = Catalog.entry!(benchmark_id)
    settings = Catalog.profile!(entry, profile)

    %{
      benchmark_id: benchmark_id,
      component: entry["component"],
      components: entry["components"],
      owner: entry["owner"],
      workload: entry["workload"],
      limiter: entry["limiter"],
      profile: to_string(profile),
      input_size: settings["input_size"],
      concurrency: settings["concurrency"],
      warmup: settings["warmup"],
      sample_count: settings["sample_count"],
      metrics: entry["metrics"],
      units: entry["units"],
      git_revision: command("git", ["rev-parse", "HEAD"]),
      checkout_dirty: command("git", ["status", "--porcelain"]) != "",
      elixir: System.version(),
      otp: System.otp_release(),
      seed: 0
    }
    |> Map.merge(overrides)
  end

  def validate(report) when is_map(report) do
    metadata = value(report, "metadata", %{})
    cases = value(report, "cases", [])

    []
    |> require(
      value(report, "benchmark_result_schema_version") == @schema_version,
      "benchmark result schema is incompatible"
    )
    |> validate_metadata(metadata)
    |> require(is_list(cases) and cases != [], "benchmark result cases must be a non-empty list")
    |> validate_case_ids(cases)
    |> Enum.reverse()
  end

  def validate(_report), do: ["benchmark result must be a map"]

  def validate!(report) do
    case validate(report) do
      [] -> report
      errors -> raise ArgumentError, Enum.join(errors, "; ")
    end
  end

  def case_inventory(report) do
    report
    |> value("cases", [])
    |> Enum.map(&value(&1, "id"))
  end

  defp validate_metadata(errors, metadata) do
    errors =
      Enum.reduce(@required_metadata, errors, fn field, current ->
        require(current, present?(value(metadata, field)), "benchmark metadata is missing #{field}")
      end)

    errors
    |> require(is_boolean(value(metadata, "checkout_dirty")), "benchmark metadata checkout_dirty must be boolean")
    |> require(value(metadata, "seed") == 0, "benchmark metadata seed must equal 0")
  end

  defp validate_case_ids(errors, cases) when is_list(cases) do
    ids = Enum.map(cases, &value(&1, "id"))

    errors
    |> require(Enum.all?(ids, &present?/1), "every benchmark case must have an id")
    |> require(length(ids) == length(Enum.uniq(ids)), "benchmark case ids must be unique")
  end

  defp validate_case_ids(errors, _cases), do: errors

  defp value(map, key, default \\ nil)
  defp value(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, String.to_atom(key), default))
  defp value(_map, _key, default), do: default

  defp require(errors, true, _message), do: errors
  defp require(errors, false, message), do: [message | errors]
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(value) when is_integer(value), do: value >= 0
  defp present?(value) when is_boolean(value), do: true
  defp present?(_value), do: false

  defp command(executable, arguments) do
    case System.cmd(executable, arguments, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _error -> "unavailable"
    end
  end
end
