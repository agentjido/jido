defmodule Jido.Test.Examples.Catalog do
  @moduledoc false

  @required_entry_fields ~w(id category component readme source test)
  @required_category_fields ~w(id source_root)
  @chapter_pattern ~r/^\d{2}_[a-z][a-z0-9_]*$/
  @lesson_pattern ~r/^(\d{2})_\d{2}_[a-z][a-z0-9_]*$/

  def load!(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, catalog} -> catalog
      {:error, error} -> raise "cannot read example catalog: #{inspect(error)}"
    end
  end

  def validate(catalog, root) do
    categories = Map.get(catalog, "categories", [])
    entries = Map.get(catalog, "examples", [])
    exclusions = Map.get(catalog, "exclusions", [])
    indexes = Map.get(catalog, "index_readmes", [])

    []
    |> require_version(catalog)
    |> require_fields(categories, @required_category_fields, "category")
    |> require_fields(entries, @required_entry_fields, "example")
    |> validate_categories(categories)
    |> validate_exclusions(exclusions, root)
    |> validate_entries(entries, categories, catalog, root)
    |> validate_order(entries)
    |> validate_unique(entries, "id")
    |> validate_unique(entries, "readme")
    |> validate_unique(entries, "source")
    |> validate_unique(entries, "test")
    |> validate_index_readmes(indexes, categories, root)
    |> validate_inventory(entries, categories, exclusions, indexes, root)
    |> Enum.reverse()
  end

  def validate!(catalog, root) do
    case validate(catalog, root) do
      [] -> :ok
      errors -> raise Enum.join(errors, "\n")
    end
  end

  defp require_version(errors, %{"version" => 1}), do: errors
  defp require_version(errors, _catalog), do: ["catalog version must be 1" | errors]

  defp require_fields(errors, records, fields, label) when is_list(records) do
    records
    |> Enum.with_index(1)
    |> Enum.reduce(errors, fn {record, index}, current ->
      Enum.reduce(fields, current, fn field, field_errors ->
        if present?(Map.get(record, field)) do
          field_errors
        else
          ["#{label} #{index} is missing #{field}" | field_errors]
        end
      end)
    end)
  end

  defp require_fields(errors, _records, _fields, label),
    do: ["#{label} register must be a list" | errors]

  defp validate_categories(errors, categories) when is_list(categories) do
    errors
    |> duplicates(categories, "id", "duplicate category id")
    |> then(fn current ->
      Enum.reduce(categories, current, fn category, category_errors ->
        relative_path(category_errors, category["source_root"], "category source root")
      end)
    end)
  end

  defp validate_categories(errors, _categories), do: errors

  defp validate_exclusions(errors, exclusions, root) when is_list(exclusions) do
    Enum.reduce(exclusions, errors, fn exclusion, current ->
      path = exclusion["path"]
      reason = exclusion["reason"]

      current
      |> relative_path(path, "exclusion")
      |> maybe_error(not present?(reason), "exclusion #{inspect(path)} is missing a reason")
      |> maybe_error(
        present?(path) and not File.exists?(Path.join(root, path)),
        "excluded path does not exist: #{path}"
      )
    end)
  end

  defp validate_exclusions(errors, _exclusions, _root),
    do: ["exclusions register must be a list" | errors]

  defp validate_entries(errors, entries, categories, catalog, root)
       when is_list(entries) and is_list(categories) do
    category_map = Map.new(categories, &{&1["id"], &1})
    pattern = Map.get(catalog, "id_pattern", "")

    regex =
      case Regex.compile(pattern) do
        {:ok, compiled} -> compiled
        {:error, _reason} -> nil
      end

    errors = if regex, do: errors, else: ["id_pattern is not a valid regular expression" | errors]

    Enum.reduce(entries, errors, fn entry, current ->
      category = category_map[entry["category"]]

      current
      |> validate_id(entry, regex)
      |> maybe_error(is_nil(category), "unknown category for #{inspect(entry["id"])}")
      |> validate_entry_paths(entry, category, root)
      |> validate_readme_contract(entry, root)
      |> validate_test_contract(entry, root)
    end)
  end

  defp validate_entries(errors, _entries, _categories, _catalog, _root), do: errors

  defp validate_id(errors, entry, regex) do
    id = entry["id"]

    maybe_error(
      errors,
      is_nil(regex) or not is_binary(id) or not Regex.match?(regex, id),
      "invalid example id: #{inspect(id)}"
    )
  end

  defp validate_entry_paths(errors, entry, nil, root) do
    Enum.reduce(~w(readme source test), errors, fn field, current ->
      validate_file(current, entry[field], field, root)
    end)
  end

  defp validate_entry_paths(errors, entry, category, root) do
    errors
    |> validate_file(entry["readme"], "readme", root)
    |> validate_file(entry["source"], "source", root)
    |> validate_file(entry["test"], "test", root)
    |> expected_root(entry["readme"], category["source_root"], "readme")
    |> expected_root(entry["source"], category["source_root"], "source")
    |> expected_root(entry["test"], category["source_root"], "test")
    |> validate_numbered_entry(entry, category)
    |> validate_auxiliary(entry, category, root)
  end

  defp validate_numbered_entry(errors, entry, category) do
    assets =
      [
        {"readme", entry["readme"], category["source_root"]},
        {"source", entry["source"], category["source_root"]},
        {"test", entry["test"], category["source_root"]}
      ] ++
        Enum.map(Map.get(entry, "auxiliary_sources", []), fn path ->
          {"auxiliary source", path, category["source_root"]}
        end)

    {errors, locations} =
      Enum.reduce(assets, {errors, []}, fn {label, path, root}, {current, found} ->
        case numbered_location(path, root) do
          {:ok, chapter, lesson} ->
            chapter_number = String.slice(chapter, 0, 2)

            lesson_number =
              case Regex.run(@lesson_pattern, lesson) do
                [_, number] -> number
                _ -> nil
              end

            next =
              current
              |> maybe_error(
                not Regex.match?(@chapter_pattern, chapter),
                "#{label} chapter must use NN_chapter: #{path}"
              )
              |> maybe_error(
                is_nil(lesson_number),
                "#{label} lesson must use NN_NN_lesson: #{path}"
              )
              |> maybe_error(
                is_binary(lesson_number) and lesson_number != chapter_number,
                "#{label} lesson chapter prefix does not match its parent: #{path}"
              )

            {next, [{chapter, lesson} | found]}

          :error ->
            {["#{label} path must use NN_chapter/NN_NN_lesson: #{path}" | current], found}
        end
      end)

    unique_locations = Enum.uniq(locations)

    expected_id =
      case unique_locations do
        [{_chapter, lesson}] -> lesson
        _ -> nil
      end

    errors
    |> maybe_error(
      length(unique_locations) > 1,
      "paired assets are not co-located in one numbered lesson: #{entry["id"]}"
    )
    |> maybe_error(
      is_binary(expected_id) and entry["id"] != expected_id,
      "example id does not match its numbered lesson: #{entry["id"]}"
    )
  end

  defp numbered_location(path, root) do
    if under?(path, root) do
      case path |> Path.relative_to(root) |> Path.split() do
        [chapter, lesson, _file] -> {:ok, chapter, lesson}
        _ -> :error
      end
    else
      :error
    end
  end

  defp validate_auxiliary(errors, entry, category, root) do
    entry
    |> Map.get("auxiliary_sources", [])
    |> Enum.reduce(errors, fn path, current ->
      current
      |> validate_file(path, "auxiliary source", root)
      |> expected_root(path, category["source_root"], "auxiliary source")
    end)
  end

  defp validate_file(errors, path, label, root) do
    errors
    |> relative_path(path, label)
    |> maybe_error(is_binary(path) and not File.regular?(Path.join(root, path)), "missing #{label}: #{path}")
  end

  defp validate_readme_contract(errors, entry, root) do
    path = entry["readme"]

    if is_binary(path) and File.regular?(Path.join(root, path)) do
      content = File.read!(Path.join(root, path))
      test_name = entry["test"] |> to_string() |> Path.basename()

      maybe_error(
        errors,
        not String.contains?(content, test_name),
        "example README does not link to its paired test: #{path}"
      )
    else
      errors
    end
  end

  defp validate_test_contract(errors, entry, root) do
    path = entry["test"]

    if is_binary(path) and File.regular?(Path.join(root, path)) do
      content = File.read!(Path.join(root, path))
      source = Path.relative_to(entry["source"], Path.dirname(path))
      local_require = ~s|Code.require_file("#{source}", __DIR__)|

      errors
      |> maybe_error(
        not String.contains?(content, "@moduletag :integration"),
        "paired test has no :integration tag: #{path}"
      )
      |> maybe_error(
        not String.contains?(content, local_require),
        "paired test does not load its local source: #{path}"
      )
    else
      errors
    end
  end

  defp validate_unique(errors, entries, field) do
    duplicates(errors, entries, field, "duplicate example #{field}")
  end

  defp validate_order(errors, entries) when is_list(entries) do
    ids = Enum.map(entries, & &1["id"])
    maybe_error(errors, ids != Enum.sort(ids), "example entries must be sorted by id")
  end

  defp validate_order(errors, _entries), do: errors

  defp validate_index_readmes(errors, indexes, categories, root) when is_list(indexes) do
    source_roots = Enum.map(categories, & &1["source_root"])

    Enum.reduce(indexes, errors, fn path, current ->
      current
      |> validate_file(path, "index README", root)
      |> maybe_error(
        not Enum.any?(source_roots, &under?(path, &1)),
        "index README is outside a source category: #{path}"
      )
    end)
  end

  defp validate_index_readmes(errors, _indexes, _categories, _root),
    do: ["index_readmes register must be a list" | errors]

  defp validate_inventory(errors, entries, categories, exclusions, indexes, root) do
    excluded = Enum.map(exclusions, & &1["path"])

    registered_sources =
      Enum.flat_map(entries, fn entry ->
        [entry["source"] | Map.get(entry, "auxiliary_sources", [])]
      end)

    registered_readmes = ["examples/README.md" | Enum.map(entries, & &1["readme"])] ++ indexes
    registered_tests = Enum.map(entries, & &1["test"])

    discovered_sources =
      categories
      |> discover("source_root", ["**/*.ex", "**/*.exs"], root, excluded)
      |> Enum.reject(&String.ends_with?(&1, "_test.exs"))

    discovered_readmes = discover(categories, "source_root", ["**/README.md"], root, excluded)

    discovered_tests =
      categories
      |> discover("source_root", ["**/*_test.exs"], root, excluded)
      |> List.delete("examples/catalog_test.exs")

    errors
    |> unlisted(discovered_sources, registered_sources, "source")
    |> unlisted(discovered_readmes, registered_readmes, "README")
    |> unlisted(discovered_tests, registered_tests, "test")
    |> missing_inventory(registered_sources, discovered_sources, "registered source")
    |> missing_inventory(registered_readmes, discovered_readmes, "registered README")
    |> missing_inventory(registered_tests, discovered_tests, "registered test")
    |> validate_top_level(entries, indexes, excluded, root)
  end

  defp discover(categories, root_field, patterns, root, exclusions) do
    categories
    |> Enum.map(& &1[root_field])
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.flat_map(fn category_root ->
      for(
        pattern <- patterns,
        path <- Path.wildcard(Path.join([root, category_root, pattern])),
        File.regular?(path),
        relative = Path.relative_to(path, root),
        not Enum.any?(exclusions, &under?(relative, &1)),
        do: relative
      )
    end)
    |> Enum.uniq()
  end

  defp validate_top_level(errors, entries, indexes, exclusions, root) do
    example_paths =
      ["examples/README.md", "examples/catalog.yml", "examples/catalog_test.exs"] ++
        Enum.flat_map(entries, fn entry -> [entry["readme"], entry["source"], entry["test"]] end) ++
        indexes ++ exclusions

    validate_root_children(errors, "examples", example_paths, root, "example")
  end

  defp validate_root_children(errors, directory, registered, root, label) do
    allowed =
      registered
      |> Enum.filter(&under?(&1, directory))
      |> Enum.map(&top_child(&1, directory))
      |> Enum.uniq()

    root
    |> Path.join("#{directory}/*")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.reject(&(&1 in allowed))
    |> Enum.reduce(errors, fn path, current -> ["unlisted top-level #{label} path: #{path}" | current] end)
  end

  defp unlisted(errors, discovered, registered, label) do
    (discovered -- registered)
    |> Enum.reduce(errors, fn path, current -> ["unlisted example #{label}: #{path}" | current] end)
  end

  defp missing_inventory(errors, registered, discovered, label) do
    (registered -- discovered)
    |> Enum.reduce(errors, fn path, current -> ["#{label} is outside the discovered inventory: #{path}" | current] end)
  end

  defp expected_root(errors, path, root, label) do
    maybe_error(errors, is_binary(path) and not under?(path, root), "#{label} is outside category root: #{path}")
  end

  defp relative_path(errors, path, label) do
    invalid =
      not is_binary(path) or Path.type(path) != :relative or
        path in ["", "."] or ".." in Path.split(path)

    maybe_error(errors, invalid, "#{label} must be a relative repository path: #{inspect(path)}")
  end

  defp duplicates(errors, records, field, message) do
    records
    |> Enum.map(& &1[field])
    |> Enum.filter(&present?/1)
    |> Enum.frequencies()
    |> Enum.filter(fn {_value, count} -> count > 1 end)
    |> Enum.reduce(errors, fn {value, _count}, current -> ["#{message}: #{value}" | current] end)
  end

  defp under?(path, root) when is_binary(path) and is_binary(root),
    do: path == root or String.starts_with?(path, String.trim_trailing(root, "/") <> "/")

  defp under?(_path, _root), do: false

  defp top_child(path, directory) do
    case path |> Path.relative_to(directory) |> Path.split() do
      [child | _rest] -> Path.join(directory, child)
      [] -> directory
    end
  end

  defp maybe_error(errors, true, message), do: [message | errors]
  defp maybe_error(errors, false, _message), do: errors
  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
