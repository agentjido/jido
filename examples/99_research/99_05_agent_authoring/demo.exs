Code.require_file("example.ex", __DIR__)
Code.require_file("alice.ex", __DIR__)

alias Jido.Examples.ComposableAgentAuthoring.{Alice, Team}

for module <- [Team, Alice] do
  definition = module.definition()
  ^definition = Jido.Agent.define!(definition)
  {:ok, ^definition} = Jido.Agent.validate(definition)
  instance = Jido.Agent.instantiate!(definition, id: "#{definition.name}-demo")

  for value <- [definition, instance] do
    {:ok, document, registry} = Jido.Agent.Codec.encode(value)
    {:ok, ^value} = Jido.Agent.Codec.decode(document, registry)
    {:ok, json} = Jido.Agent.to_json(value, registry)
    {:ok, ^value} = Jido.Agent.from_json(json, registry)
  end

  IO.puts("#{definition.name}: canonical Agent definition; JSON round trips passed")
  IO.puts(inspect(definition, pretty: true, limit: :infinity, width: 100))
end

IO.puts("Authoring checks passed. No handlers or runtime services ran.")
