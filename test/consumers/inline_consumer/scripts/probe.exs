alias InlineConsumer.{Bound, Callback, Embedded, Host, Roles, Steps}

# Use dynamic calls below so script compilation cannot preload these owners.
roles = Roles
steps_owner = Steps
embedded_owner = Embedded

{:ok, _} = Application.ensure_all_started(:inline_consumer)
{:ok, modules} = :application.get_key(:inline_consumer, :modules)
owners = [Bound, Callback, Embedded, Roles, Steps]
owners_unloaded = fn -> Enum.all?(owners, &(:code.is_loaded(&1) == false)) end
before_load = owners_unloaded.()

# Discover and load from the application manifest before looking up any owner.
targets =
  Enum.filter(modules, fn module ->
    String.starts_with?(Atom.to_string(module), [
      "Elixir.Jido.Action.Generated.Inline.",
      "Elixir.Jido.Flow.Generated.Inline."
    ])
  end)

artifacts =
  for target <- targets do
    {:module, ^target} = Code.ensure_loaded(target)
    path = List.to_string(:code.which(target))
    %{file: Path.basename(path), local: String.starts_with?(path, System.fetch_env!("INLINE_ARTIFACT_ROOT"))}
  end

after_load = owners_unloaded.()
step = Enum.find(targets, &(&1.name() in ["first", "renamed"]))
flow = Enum.find(targets, &function_exported?(&1, :__jido_inline_flow__, 0))

catalog =
  Jido.Catalog.from_targets!(Steps, :inline_consumer, %{
    {"actions/step/v1", 1} => step,
    {"flows/embedded/v1", 1} => flow
  })

catalog_results =
  for {id, kind, target} <- [
        {"actions/step/v1", :action, step},
        {"flows/embedded/v1", :flow, flow}
      ] do
    Jido.Catalog.resolve(catalog, {id, 1}) == {:ok, target}
  end

after_catalog = owners_unloaded.()

run = fn target, params ->
  {:ok, result} = Jido.Exec.run(target, params)
  result
end

# Execute both generated target types before explicit owner lookup.
direct = %{action: run.(step, %{value: 2}), flow: run.(flow, %{value: 2})}

lookups =
  for target <- targets do
    if function_exported?(target, :__jido_inline_flow__, 0) do
      {owner, path} = target.__jido_inline_flow__()
      Jido.Flow.Inline.target!(owner, path) == target
    else
      {owner, path} = target.__jido_inline_action__()
      Jido.Action.Inline.target!(owner, path) == target
    end
  end

host_results =
  for {owner, name, params, context} <- [
        {Bound, "bound", 3, %{prefix: "bound:"}},
        {Callback, "callback", %{}, %{prefix: "default:"}},
        {Callback, "late_first", %{value: 5}, %{prefix: "late:"}},
        {Callback, "late_second", %{value: 5}, %{prefix: "late:"}}
      ],
      into: %{} do
    {:ok, result} = Host.run(owner, name, params, context)
    {name, result}
  end

validation = match?({:error, %Jido.Error.ValidationError{}}, Host.run(Callback, "callback", %{value: "bad"}, %{}))
role_targets = Map.new(roles.__jido_inline_actions__(), fn {_path, target} -> {target.name(), target} end)
steps = steps_owner.flow().components

missing_steps =
  for name <- ["first", "second", "renamed"], not Map.has_key?(steps, name), into: %{} do
    try do
      steps_owner.step_action(name)
      {name, false}
    rescue
      ArgumentError -> {name, true}
    end
  end

snapshot = fn owner, targets ->
  {:ok, identity} = Jido.Flow.semantic_identity(owner.flow())
  %{identity: identity, targets: Map.new(targets, fn {name, target} -> {name, Atom.to_string(target)} end)}
end

IO.puts(
  "INLINE_RESULT=" <>
    JSON.encode!(%{
      artifacts: Enum.sort_by(artifacts, & &1.file),
      owners_unloaded: [before_load, after_load, after_catalog],
      catalog: catalog_results,
      lookups: lookups,
      results: %{
        direct: direct,
        host: host_results,
        validation: validation,
        roles: run.(Roles, %{value: 6}),
        role_actions: Map.new(role_targets, fn {name, target} -> {name, run.(target, %{value: 6})} end),
        steps: run.(Steps, %{value: 2}),
        embedded: run.(embedded_owner.target(), %{value: 2})
      },
      missing_steps: missing_steps,
      roles: snapshot.(Roles, role_targets),
      steps: snapshot.(Steps, Map.new(steps, fn {name, %{call: instruction}} -> {name, instruction.target} end))
    })
)
