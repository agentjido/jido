defmodule Jido.Quality.SourceManifest do
  @commit_pattern ~r/\A[0-9a-f]{40}\z/

  def load!(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, manifest} -> manifest
      {:error, error} -> raise "cannot read quality source manifest: #{inspect(error)}"
    end
  end

  def validate(manifest, root) do
    required_fields = get_in(manifest, ["schema", "required_fields"]) || []
    dispositions = get_in(manifest, ["schema", "dispositions"]) || []
    assets = Map.get(manifest, "assets", [])

    []
    |> validate_required_fields(assets, required_fields)
    |> validate_commits(assets)
    |> validate_dispositions(assets, dispositions)
    |> validate_target_paths(assets)
    |> validate_ported_targets(assets, root)
    |> Enum.reverse()
  end

  defp validate_required_fields(errors, assets, required_fields) do
    assets
    |> Enum.with_index(1)
    |> Enum.reduce(errors, fn {asset, index}, current_errors ->
      Enum.reduce(required_fields, current_errors, fn field, field_errors ->
        if present?(Map.get(asset, field)) do
          field_errors
        else
          ["asset #{index} is missing #{field}" | field_errors]
        end
      end)
    end)
  end

  defp validate_commits(errors, assets) do
    assets
    |> Enum.with_index(1)
    |> Enum.reduce(errors, fn {asset, index}, current_errors ->
      if Regex.match?(@commit_pattern, Map.get(asset, "source_commit", "")) do
        current_errors
      else
        ["asset #{index} has an invalid source_commit" | current_errors]
      end
    end)
  end

  defp validate_dispositions(errors, assets, dispositions) do
    assets
    |> Enum.with_index(1)
    |> Enum.reduce(errors, fn {asset, index}, current_errors ->
      if Map.get(asset, "disposition") in dispositions do
        current_errors
      else
        ["asset #{index} has an unknown disposition" | current_errors]
      end
    end)
  end

  defp validate_target_paths(errors, assets) do
    duplicates =
      assets
      |> Enum.map(&Map.get(&1, "target_path"))
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.filter(fn {_path, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))

    Enum.reduce(duplicates, errors, fn path, current_errors ->
      ["duplicate target_path: #{path}" | current_errors]
    end)
  end

  defp validate_ported_targets(errors, assets, root) do
    assets
    |> Enum.filter(&(Map.get(&1, "disposition") == "ported"))
    |> Enum.reduce(errors, fn asset, current_errors ->
      target_path = Map.get(asset, "target_path", "")

      if File.exists?(Path.join(root, target_path)) do
        current_errors
      else
        ["ported target does not exist: #{target_path}" | current_errors]
      end
    end)
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end

defmodule Jido.Quality.SourceManifestTest do
  use ExUnit.Case, async: true

  alias Jido.Quality.SourceManifest

  @manifest_path Path.join(__DIR__, "source_manifest.yml")
  @root Path.expand("../..", __DIR__)
  @special_tags [:authoring, :system, :load, :throughput, :property, :fuzz, :peer, :bench, :example, :live, :service]

  test "the checked-in manifest is valid" do
    assert SourceManifest.validate(SourceManifest.load!(@manifest_path), @root) == []
  end

  test "rejects a missing full source commit" do
    manifest = manifest_with_asset(%{"source_commit" => ""})
    assert "asset 1 is missing source_commit" in SourceManifest.validate(manifest, @root)
    assert "asset 1 has an invalid source_commit" in SourceManifest.validate(manifest, @root)
  end

  test "rejects an unknown disposition" do
    manifest = manifest_with_asset(%{"disposition" => "pending"})
    assert "asset 1 has an unknown disposition" in SourceManifest.validate(manifest, @root)
  end

  test "rejects duplicate target paths" do
    asset = valid_asset()
    manifest = manifest_with_assets([asset, Map.put(asset, "source_path", "test/other")])
    assert "duplicate target_path: test/quality/README.md" in SourceManifest.validate(manifest, @root)
  end

  test "rejects a missing ported target" do
    manifest = manifest_with_asset(%{"target_path" => "test/quality/missing-target.exs"})

    assert "ported target does not exist: test/quality/missing-target.exs" in SourceManifest.validate(manifest, @root)
  end

  test "default test configuration excludes every special quality tag" do
    excluded_tags =
      ExUnit.configuration()
      |> Keyword.fetch!(:exclude)
      |> Enum.map(fn
        {tag, _value} -> tag
        tag when is_atom(tag) -> tag
      end)

    assert @special_tags -- excluded_tags == []
  end

  defp manifest_with_asset(overrides) do
    manifest_with_assets([Map.merge(valid_asset(), overrides)])
  end

  defp manifest_with_assets(assets) do
    %{
      "schema" => %{
        "required_fields" => [
          "source_repository",
          "source_commit",
          "source_path",
          "target_path",
          "quality_surface",
          "owner",
          "disposition",
          "reason"
        ],
        "dispositions" => ["ported", "superseded", "deferred", "excluded"]
      },
      "assets" => assets
    }
  end

  defp valid_asset do
    %{
      "source_repository" => "jido_signal",
      "source_commit" => "7b825f1d050a0e0159bb2a72ba79c100b5d362d3",
      "source_path" => "test/property",
      "target_path" => "test/quality/README.md",
      "quality_surface" => "property",
      "owner" => "jido.signal",
      "disposition" => "ported",
      "reason" => "Test fixture"
    }
  end
end
