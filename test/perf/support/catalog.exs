defmodule Jido.Test.Perf.Catalog do
  @moduledoc false

  @modes ~w(load benchmark)
  @required_family_fields ~w(id mode component components owner workload limiter command evidence)
  @required_benchmark_fields ~w(quick_profile supported_profiles metrics units profiles)
  @required_profile_fields ~w(input_size concurrency warmup sample_count)
  @catalog_path Path.expand("../catalog.yml", __DIR__)

  def load! do
    case YamlElixir.read_from_file(@catalog_path) do
      {:ok, catalog} -> catalog
      {:error, reason} -> raise "cannot read benchmark catalog: #{inspect(reason)}"
    end
  end

  def entry!(id) do
    load!()
    |> Map.fetch!("families")
    |> Enum.find(&(&1["id"] == id))
    |> case do
      nil -> raise KeyError, key: id, term: "perf catalog"
      entry -> entry
    end
  end

  def profile!(entry, profile) do
    entry
    |> Map.fetch!("profiles")
    |> Map.fetch!(to_string(profile))
  end

  def validate(catalog) do
    families = Map.get(catalog, "families", [])

    []
    |> require(catalog["schema_version"] == 1, "catalog schema_version must equal 1")
    |> require(families != [], "catalog must list perf families")
    |> validate_unique_ids(families)
    |> validate_families(families)
    |> Enum.reverse()
  end

  defp validate_unique_ids(errors, families) do
    families
    |> Enum.map(& &1["id"])
    |> Enum.frequencies()
    |> Enum.filter(fn {_id, count} -> count > 1 end)
    |> Enum.reduce(errors, fn {id, _count}, current -> ["duplicate perf family: #{inspect(id)}" | current] end)
  end

  defp validate_families(errors, families) do
    Enum.reduce(families, errors, fn family, current ->
      id = family["id"] || "unknown"

      current =
        Enum.reduce(@required_family_fields, current, fn field, field_errors ->
          require(field_errors, present?(family[field]), "perf family #{id} is missing #{field}")
        end)

      current = require(current, family["mode"] in @modes, "perf family #{id} has unknown mode")

      case family["mode"] do
        "benchmark" -> validate_benchmark(current, id, family)
        "load" -> require(current, present?(family["bounded_case"]), "load family #{id} is missing bounded_case")
        _other -> current
      end
    end)
  end

  defp validate_benchmark(errors, id, family) do
    errors =
      Enum.reduce(@required_benchmark_fields, errors, fn field, current ->
        require(current, present?(family[field]), "benchmark #{id} is missing #{field}")
      end)

    profiles = family["profiles"] || %{}
    supported = family["supported_profiles"] || []

    errors
    |> require(Enum.sort(Map.keys(profiles)) == Enum.sort(supported), "benchmark #{id} profile lists differ")
    |> require(family["quick_profile"] in supported, "benchmark #{id} quick_profile is not supported")
    |> validate_profiles(id, profiles)
  end

  defp validate_profiles(errors, id, profiles) do
    Enum.reduce(profiles, errors, fn {name, profile}, current ->
      Enum.reduce(@required_profile_fields, current, fn field, field_errors ->
        require(field_errors, present?(profile[field]), "benchmark #{id} profile #{name} is missing #{field}")
      end)
    end)
  end

  defp require(errors, true, _message), do: errors
  defp require(errors, false, message), do: [message | errors]
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value) or is_map(value), do: value != [] and value != %{}
  defp present?(value) when is_integer(value), do: value >= 0
  defp present?(_value), do: false
end
