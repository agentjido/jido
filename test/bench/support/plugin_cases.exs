defmodule JidoCoreBench.SchemaPlugin do
  @moduledoc false
  use Jido.Plugin

  def state_spec(opts) do
    {:owned,
     Zoi.list(Zoi.integer() |> Zoi.min(Keyword.fetch!(opts, :minimum))) |> Zoi.default([])}
  end
end

defmodule JidoCoreBench.PluginCases do
  @moduledoc false
  alias JidoCoreBench.Fixtures, as: F
  alias Jido.Agent.Command.Runner

  def workloads do
    for count <- [0, 1_000, 10_000], operation <- [:validate, :prepare] do
      owned = if count == 0, do: [], else: Enum.to_list(1..count)

      F.checked(
        "plugin/schema/#{count}/#{operation}",
        fn context ->
          agent = F.agent(1, nil, JidoCoreBench.Add, [{JidoCoreBench.SchemaPlugin, minimum: 0}])
          {%{agent | state: Map.put(agent.state, :owned, owned)}, F.signal(), context}
        end,
        fn {agent, signal, context} ->
          case operation do
            :validate -> Jido.Agent.validate_instance(agent)
            :prepare -> Runner.prepare(agent, signal, context: context)
          end
        end,
        fn {:ok, _result} -> :ok end
      )
      |> Map.put(:verify, fn {agent, signal, context}, {:ok, result} ->
        case operation do
          :validate ->
            F.equal!(result, agent)

          :prepare ->
            F.equal!(result.agent, agent)
            F.equal!(result.signal, signal)

            F.equal!(
              result.context,
              Map.merge(
                context,
                %{agent_id: agent.id, agent_state: agent.state, signal: signal}
              )
            )

            F.equal!(Enum.map(result.plugin_specs, & &1.module), [JidoCoreBench.SchemaPlugin])
        end
      end)
    end
  end
end
