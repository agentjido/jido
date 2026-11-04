defmodule Jido.Quality.ComponentProof do
  @moduledoc false

  def load!(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, proof} -> proof
      {:error, error} -> raise "cannot read component proof: #{inspect(error)}"
    end
  end

  def validate(proof, root, options \\ []) do
    active = Keyword.get_lazy(options, :active_components, fn -> active_components(root) end)
    inventory = Keyword.get_lazy(options, :inventory, fn -> module_inventory(root) end)

    covenant_owners =
      Keyword.get_lazy(options, :covenant_owners, fn -> covenant_owners(proof, root, active) end)

    components = list(proof["components"])
    profiles = map(proof["proof_profiles"])
    groups = map(proof["evidence_groups"])
    schema = map(proof["schema"])

    errors =
      []
      |> validate_components(components, active, profiles)
      |> validate_profiles(profiles, groups, schema, root)
      |> validate_inventory(proof["module_inventory"], inventory)

    {_owners, ownership_errors} =
      ownership(proof, root,
        active_components: active,
        inventory: inventory,
        covenant_owners: covenant_owners
      )

    Enum.sort(errors ++ ownership_errors)
  end

  def ownership(proof, root) do
    active = active_components(root)
    inventory = module_inventory(root)

    ownership(proof, root,
      active_components: active,
      inventory: inventory,
      covenant_owners: covenant_owners(proof, root, active)
    )
  end

  def ownership(proof, _root, options) do
    active = Keyword.fetch!(options, :active_components)
    inventory = Keyword.fetch!(options, :inventory)
    covenant_owners = Keyword.fetch!(options, :covenant_owners)
    component_ids = proof |> list_at("components") |> Enum.map(& &1["id"])
    ownership = map(proof["module_ownership"])
    overrides = list(ownership["overrides"])
    rules = list(ownership["fallback_rules"])

    duplicate_overrides =
      overrides
      |> Enum.group_by(& &1["module"])
      |> Enum.filter(fn {_module, records} -> length(records) > 1 end)
      |> Enum.map(fn {module, _records} -> "module #{module} has two primary ownership overrides" end)

    override_map = Map.new(overrides, &{&1["module"], &1["component"]})

    {owners, errors} =
      Enum.reduce(inventory.production_modules, {%{}, duplicate_overrides}, fn module, {current, errors} ->
        case owner_for(module, override_map, covenant_owners, rules) do
          {:ok, owner} ->
            if owner in active and owner in component_ids do
              {Map.put(current, module, owner), errors}
            else
              {current, ["module #{module} has unknown primary owner #{inspect(owner)}" | errors]}
            end

          {:error, reason} ->
            {current, [reason | errors]}
        end
      end)

    public_errors =
      for module <- inventory.public_modules,
          not Map.has_key?(owners, module),
          do: "public module #{module} has no primary component owner"

    {owners, Enum.sort(errors ++ public_errors)}
  end

  def module_inventory(root) do
    production_modules =
      case :application.get_key(:jido, :modules) do
        {:ok, modules} -> modules
        :undefined -> []
      end
      |> Enum.filter(&production_module?(&1, root))
      |> Enum.map(&inspect/1)
      |> Enum.sort()

    public_modules =
      Enum.filter(production_modules, fn name ->
        module = Module.concat([name])
        match?({:docs_v1, _, _, _, document, _, _} when is_map(document), Code.fetch_docs(module))
      end)

    %{production_modules: production_modules, public_modules: public_modules}
  end

  def digest(modules) do
    :sha256
    |> :crypto.hash(Enum.join(Enum.sort(modules), "\n"))
    |> Base.encode16(case: :lower)
  end

  defp validate_components(errors, components, active, profiles) do
    ids = Enum.map(components, & &1["id"])

    duplicates =
      ids
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(fn {id, _count} -> "duplicate component id: #{id}" end)

    missing = Enum.map(active -- ids, &"active component is missing: #{&1}")
    unknown = Enum.map(ids -- active, &"component is not active: #{&1}")

    bad_profiles =
      for component <- components,
          not Map.has_key?(profiles, component["proof_profile"]),
          do: "component #{component["id"]} has unknown proof profile: #{inspect(component["proof_profile"])}"

    errors ++ duplicates ++ missing ++ unknown ++ bad_profiles
  end

  defp validate_profiles(errors, profiles, groups, schema, root) do
    proof_types = list(schema["proof_types"])
    states = list(schema["proof_states"])
    reason_codes = list(schema["not_applicable_reason_codes"])

    Enum.reduce(profiles, errors, fn {profile_name, profile}, current ->
      missing = proof_types -- Map.keys(profile)
      unknown = Map.keys(profile) -- proof_types

      current =
        current ++
          Enum.map(missing, &"profile #{profile_name} is missing proof type #{&1}") ++
          Enum.map(unknown, &"profile #{profile_name} has unknown proof type #{&1}")

      Enum.reduce(proof_types, current, fn type, profile_errors ->
        validate_proof(
          profile_errors,
          profile_name,
          type,
          map(profile[type]),
          groups,
          states,
          reason_codes,
          root
        )
      end)
    end)
  end

  defp validate_proof(errors, profile, type, proof, groups, states, reason_codes, root) do
    state = proof["state"]
    prefix = "profile #{profile} proof #{type}"
    errors = add_unless(errors, state in states, "#{prefix} has unknown state")

    case state do
      "required" ->
        group_name = proof["evidence_group"]
        paths = list(groups[group_name])

        errors
        |> add_unless(is_binary(group_name) and paths != [], "#{prefix} has no evidence group")
        |> validate_evidence_paths(paths, root, prefix)
        |> validate_executable_evidence(type, paths, root, prefix)

      "not_applicable" ->
        errors
        |> add_unless(proof["owner"] == "self", "#{prefix} has no named owner")
        |> add_unless(proof["reason_code"] in reason_codes, "#{prefix} has no valid reason code")
        |> add_unless(
          is_binary(proof["reason"]) and String.length(String.trim(proof["reason"])) >= 30,
          "#{prefix} has no specific reason"
        )

      _other ->
        errors
    end
  end

  defp validate_evidence_paths(errors, paths, root, prefix) do
    Enum.reduce(paths, errors, fn path, current ->
      valid = repository_path?(path, root) and File.exists?(Path.join(root, path))
      add_unless(current, valid, "#{prefix} evidence does not exist: #{inspect(path)}")
    end)
  end

  defp validate_executable_evidence(errors, type, paths, root, prefix)
       when type in ["authoring", "example", "property", "fuzz"] do
    files =
      paths
      |> Enum.flat_map(fn path ->
        full = Path.join(root, path)

        if File.dir?(full) do
          Path.wildcard(Path.join(full, "**/*_test.exs"))
        else
          if String.ends_with?(full, "_test.exs"), do: [full], else: []
        end
      end)

    errors = add_unless(errors, files != [], "#{prefix} has no executable test")

    if type in ["property", "fuzz"] do
      marker = if type == "fuzz", do: "fuzz", else: "property"
      found? = Enum.any?(files, &(File.regular?(&1) and String.contains?(File.read!(&1), marker)))
      add_unless(errors, found?, "#{prefix} has no #{type} evidence marker")
    else
      errors
    end
  end

  defp validate_executable_evidence(errors, _type, _paths, _root, _prefix), do: errors

  defp validate_inventory(errors, expected, inventory) do
    expected = map(expected)

    errors
    |> add_unless(
      expected["production_count"] == length(inventory.production_modules),
      "production module inventory count changed"
    )
    |> add_unless(
      expected["production_sha256"] == digest(inventory.production_modules),
      "production module inventory digest changed"
    )
    |> add_unless(
      expected["public_count"] == length(inventory.public_modules),
      "public module inventory count changed"
    )
    |> add_unless(
      expected["public_sha256"] == digest(inventory.public_modules),
      "public module inventory digest changed"
    )
  end

  defp owner_for(module, overrides, covenant_owners, rules) do
    case overrides[module] do
      nil -> covenant_or_fallback_owner(module, covenant_owners[module] || [], rules)
      owner -> {:ok, owner}
    end
  end

  defp covenant_or_fallback_owner(_module, [owner], _rules), do: {:ok, owner}

  defp covenant_or_fallback_owner(module, owners, _rules) when length(owners) > 1 do
    {:error, "module #{module} has two primary Covenant owners: #{Enum.join(Enum.sort(owners), ", ")}"}
  end

  defp covenant_or_fallback_owner(module, [], rules) do
    matches =
      rules
      |> Enum.filter(&rule_match?(module, &1))
      |> Enum.group_by(&rule_specificity/1)

    case matches do
      map when map_size(map) == 0 ->
        {:error, "module #{module} has no primary component owner"}

      map ->
        {_length, best} = Enum.max_by(map, &elem(&1, 0))
        owners = best |> Enum.map(& &1["component"]) |> Enum.uniq()

        case owners do
          [owner] -> {:ok, owner}
          _ -> {:error, "module #{module} has two primary fallback owners: #{Enum.join(Enum.sort(owners), ", ")}"}
        end
    end
  end

  defp active_components(root) do
    root
    |> Path.join("test/contracts/coverage.json")
    |> File.read!()
    |> JSON.decode!()
    |> get_in(["components"])
    |> Map.keys()
    |> Enum.sort()
  end

  defp covenant_owners(proof, root, active) do
    pattern = get_in(proof, ["module_ownership", "covenant_records"])

    root
    |> Path.join(pattern)
    |> Path.wildcard()
    |> Enum.reduce(%{}, fn path, owners ->
      component = component_id(path, root)

      if component in active do
        path
        |> File.read!()
        |> frontmatter!()
        |> Map.get("modules", [])
        |> Enum.reduce(owners, fn module, current ->
          Map.update(current, module, [component], &[component | &1])
        end)
      else
        owners
      end
    end)
    |> Map.new(fn {module, components} -> {module, Enum.uniq(components)} end)
  end

  defp component_id(path, root) do
    path
    |> Path.relative_to(Path.join(root, "test/contracts"))
    |> String.trim_trailing(".obligations.md")
    |> String.replace("/", ".")
  end

  defp frontmatter!(content) do
    case String.split(content, "---", parts: 3) do
      [_, frontmatter, _body] ->
        case YamlElixir.read_from_string(frontmatter) do
          {:ok, data} -> data
          {:error, error} -> raise "invalid Covenant frontmatter: #{inspect(error)}"
        end

      _other ->
        raise "missing Covenant frontmatter"
    end
  end

  defp production_module?(module, root) do
    with true <- Code.ensure_loaded?(module),
         source when is_list(source) <- module.module_info(:compile)[:source] do
      String.starts_with?(Path.expand(to_string(source)), Path.join(Path.expand(root), "lib") <> "/")
    else
      _other -> false
    end
  end

  defp rule_match?(module, %{"exact" => exact}) when is_binary(exact), do: module == exact

  defp rule_match?(module, %{"prefix" => prefix}) when is_binary(prefix) do
    module == prefix or String.starts_with?(module, prefix <> ".")
  end

  defp rule_match?(_module, _rule), do: false

  defp rule_specificity(%{"exact" => exact}) when is_binary(exact), do: {String.length(exact), 1}
  defp rule_specificity(%{"prefix" => prefix}) when is_binary(prefix), do: {String.length(prefix), 0}
  defp rule_specificity(_rule), do: {0, 0}

  defp repository_path?(path, root) when is_binary(path) do
    expanded_root = Path.expand(root)
    expanded_path = Path.expand(path, expanded_root)

    Path.type(path) != :absolute and
      expanded_path != expanded_root and
      String.starts_with?(expanded_path, expanded_root <> "/")
  end

  defp repository_path?(_path, _root), do: false

  defp add_unless(errors, true, _error), do: errors
  defp add_unless(errors, false, error), do: [error | errors]
  defp list_at(map, key), do: map |> map() |> Map.get(key) |> list()
  defp list(value) when is_list(value), do: value
  defp list(_value), do: []
  defp map(value) when is_map(value), do: value
  defp map(_value), do: %{}
end
