alias InlineConsumer.{Bound, Callback, Host, Roles, Steps}
alias Jido.Action.Inline

roles = Roles
steps_owner = Steps

offset = System.fetch_env!("INLINE_OFFSET") |> String.to_integer()
{:ok, _} = Application.ensure_all_started(:inline_consumer)
{:ok, modules} = :application.get_key(:inline_consumer, :modules)
owners = [Bound, Callback, Roles, Steps]
for owner <- owners, do: false = :code.is_loaded(owner)

# Read the application manifest before any owner lookup. Every target must load
# from this consumer's artifacts, including targets emitted by a late hook.
targets =
  Enum.filter(
    modules,
    &String.starts_with?(Atom.to_string(&1), "Elixir.Jido.Action.Generated.Inline.")
  )

for target <- targets do
  {:module, ^target} = Code.ensure_loaded(target)

  true =
    List.to_string(:code.which(target))
    |> String.starts_with?(System.fetch_env!("INLINE_ARTIFACT_ROOT"))
end

for owner <- owners, do: false = :code.is_loaded(owner)
step = Enum.find(targets, &(&1.name() in ["first", "renamed"]))
registry = Jido.Authoring.Registry.new!(%{{"actions/step/v1", 1} => {:action, step}})

{:ok, ^step} =
  Jido.Authoring.Registry.resolve(
    registry,
    {"actions/step/v1", 1},
    :action
  )

false = :code.is_loaded(Steps)
{:ok, %{value: value}} = Jido.Exec.run(step, %{value: 2})
true = value == 2 + offset

for target <- targets do
  {owner, path} = target.__jido_inline_action__()
  ^target = Inline.target!(owner, path)
end

{:ok, %{message: "bound:[7]"}} = Host.run(Bound, "bound", 3, %{prefix: "bound:"})
{:ok, %{message: "default:[4]"}} = Host.run(Callback, "callback", %{}, %{prefix: "default:"})

{:error, %Jido.Action.Error.InvalidInputError{}} =
  Host.run(Callback, "callback", %{value: "bad"}, %{})

for {name, expected} <- [{"late_first", "late:[6]"}, {"late_second", "late:[7]"}] do
  {:ok, %{message: ^expected}} = Host.run(Callback, name, %{value: 5}, %{prefix: "late:"})
end

role_targets =
  Map.new(roles.__jido_inline_actions__(), fn {_path, target} -> {target.name(), target} end)

for {role, target} <- role_targets do
  true = role in ["step", "finish"]
  expected = 6 + offset
  {:ok, %{value: ^expected}} = Jido.Exec.run(target, %{value: 6})
end

expected_roles = 6 + 2 * offset
{:ok, %{value: ^expected_roles}} = Jido.Exec.run(Roles, %{value: 6})

steps = steps_owner.flow().components
expected = (2 + offset) * map_size(steps)
{:ok, %{value: ^expected}} = Jido.Exec.run(Steps, %{value: 2})

# Removed paths must be absent from both public lookup APIs.
missing = fn lookup ->
  try do
    lookup.()
    raise "stale inline target"
  rescue
    ArgumentError -> :ok
  end
end

for name <- ["first", "second", "renamed"], name not in Map.keys(steps) do
  missing.(fn -> steps_owner.step_action(name) end)
end

snapshot = fn owner, targets ->
  {:ok, identity} = Jido.Flow.semantic_identity(owner.flow())

  %{
    identity: identity,
    targets: Map.new(targets, fn {name, target} -> {name, Atom.to_string(target)} end)
  }
end

IO.puts(
  "INLINE_RESULT=" <>
    JSON.encode!(%{
      roles: snapshot.(Roles, role_targets),
      steps:
        snapshot.(
          Steps,
          Map.new(steps, fn {name, %{call: instruction}} ->
            {name, instruction.target}
          end)
        ),
      count: length(targets)
    })
)
