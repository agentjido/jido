defmodule Jido.Agent.Codec.Deriver do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Codec.{Data, Registry}

  def agent(agent) do
    entries =
      [{:agent, agent.module}, {:schema, agent.schema}] ++
        Data.registry_entries(agent.metadata) ++
        Enum.flat_map(agent.plugins, &plugin_entries/1)

    with {:ok, routes} <- route_entries(agent.routes),
         do: Registry.derive(entries ++ routes)
  end

  defp plugin_entries({module, options}),
    do: [{:plugin, module} | Data.registry_entries(options)]

  defp route_entries(routes) do
    Authoring.traverse(routes, fn route ->
      {target, defaults} = Authoring.split_target(route.target)

      with {:ok, executable} <- Jido.Executable.resolve(target) do
        entries = [{executable.kind, target} | Data.registry_entries(defaults)]

        {:ok,
         if(is_nil(route.match),
           do: entries,
           else: entries ++ [{:route_match, route.match}]
         )}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, List.flatten(entries)}
      error -> error
    end
  end
end
