defmodule JidoTest.Examples.Basic.AuthoringFormatsTest do
  use JidoTest.BasicSDKCase

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Agent.{Builder, Codec}

  alias Jido.Examples.{
    MinimalAgent,
    TypedCommandAgent,
    PluginStateAgent,
    DirectiveAgent,
    ControlledTurnAgent
  }

  @cases [
    {MinimalAgent, :increment, [2]},
    {TypedCommandAgent, :patch_profile, [%{name: " Updated "}]},
    {TypedCommandAgent, :set_count, [2]},
    {PluginStateAgent, :increment, [2]},
    {DirectiveAgent, :set_count, [2, :valid]},
    {ControlledTurnAgent, :increment, [2, "parity"]}
  ]

  for {module, command, arguments} <- @cases do
    test "all authoring formats execute #{inspect(module)}.#{command} through the same runtime",
         %{
           jido: jido
         } do
      module = unquote(module)
      command = unquote(command)
      arguments = unquote(Macro.escape(arguments))
      definition = module.agent()
      opts = [id: unique_id()]
      expected = module.new!(opts)

      attrs = definition |> Agent.to_map() |> Map.drop([:id, :state])
      direct = Agent.instantiate!(Agent.new!(attrs), opts)
      keyword = Agent.instantiate!(Agent.new!(Map.to_list(attrs)), opts)
      built = Builder.build!(rebuild(definition), opts)
      {:ok, document, registry} = Codec.encode(definition)
      {:ok, decoded} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry, opts)

      assert direct == expected
      assert keyword == expected
      assert built == expected
      assert decoded == expected

      input = input_for(module)
      signal_function = String.to_atom("#{command}_signal!")
      signal = apply(module, signal_function, arguments ++ [[input: input]])
      context = %{observer: self()}
      assert {:ok, candidate, directives} = Agent.cmd(decoded, signal, context: context)

      for {agent, index} <- Enum.with_index([expected, direct, keyword, built, decoded]) do
        agent = %{agent | id: "#{agent.id}-#{index}"}
        {:ok, server} = Jido.start_agent(jido, agent)

        assert {:ok, committed} =
                 apply(
                   module,
                   command,
                   [server | arguments] ++ [[input: input, context: context]]
                 )

        assert committed == %{candidate | id: agent.id}
        await_idle(server)
        assert Server.snapshot(server) == %{agent: committed, state_version: 1}
        assert {:ok, same_candidate, ^directives} = Agent.cmd(agent, signal, context: context)
        assert same_candidate == committed
      end
    end
  end

  defp input_for(PluginStateAgent), do: %{observer: self()}
  defp input_for(_module), do: %{}

  defp rebuild(agent) do
    builder =
      Builder.new(module: agent.module, name: agent.name)
      |> Builder.description(agent.description)
      |> Builder.schema(agent.schema)
      |> Builder.metadata(agent.metadata)

    builder =
      Enum.reduce(agent.plugins, builder, fn {module, options}, acc ->
        Builder.plugin(acc, module, options)
      end)

    Enum.reduce(agent.routes, builder, fn route, acc ->
      {target, defaults} = Codec.target(route.target)
      options = [priority: route.priority, match: route.match]
      options = if is_nil(defaults), do: options, else: Keyword.put(options, :defaults, defaults)
      Builder.route(acc, route.path, target, options)
    end)
  end
end
