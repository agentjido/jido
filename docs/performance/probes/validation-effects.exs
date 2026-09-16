# Contract probes for Rounds 25 and 30. These do not measure time.
# The second probe checks the current post-Action schema transform behavior.
defmodule JidoCoreEffects.Owned do
  use Jido.Plugin, agent: __MODULE__.Agent
end

defmodule JidoCoreEffects.Owned.Agent do
  use Jido.Agent.Plugin

  def state_spec(_opts),
    do: {:owned, Zoi.integer() |> Zoi.transform({__MODULE__, :increment, []})}

  def increment(value, _opts), do: value + 1
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}
end

defmodule JidoCoreEffects.Reset do
  use Jido.Action, name: "core_effects_reset"
  def stringify(value, _opts), do: Integer.to_string(value)

  def run(_params, context) do
    send(context.probe_owner, :action_ran)
    {:ok, %{context.agent_state | count: 1}}
  end
end

{:ok, specs} = Jido.Plugin.normalize_all([JidoCoreEffects.Owned])
probe_agent =
  Jido.Agent.new!(name: "core_effects_owned", plugins: [JidoCoreEffects.Owned])
  |> Map.put(:id, "core-effects-owned")
  |> Map.put(:state, %{owned: 1})

probe_signal = Jido.Signal.new!("probe.owned", %{}, source: "/probe")
{:ok, %{owned: 2}, []} =
  Jido.Agent.Plugin.Pipeline.run(
    {:ok, %{owned: 1}, []},
    probe_agent,
    probe_signal,
    %{},
    Jido.Agent.Plugin.specs(specs)
  )
IO.puts("Round 25: unchanged reducer output still transforms owned state from 1 to 2")

{:ok, supervisor} = Jido.start_link(name: JidoCoreEffects)

try do
  definition =
    Jido.Agent.new!(
      name: "core_effects",
      schema:
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.transform({JidoCoreEffects.Reset, :stringify, []})
        }),
      routes: [{"probe.reset", JidoCoreEffects.Reset}]
    )

  instance = %{definition | id: "core-effects", state: %{count: 1}}
  signal = Jido.Signal.new!("probe.reset", %{}, source: "/probe")

  {:ok, next_agent, []} =
    Jido.Agent.cmd(instance, signal,
      task_supervisor: JidoCoreEffects.TaskSupervisor,
      context: %{probe_owner: self()}
    )

  %{count: "1"} = next_agent.state

  receive do
    :action_ran -> :ok
  after
    1_000 -> raise "Action did not run"
  end

  IO.puts("Round 30: the command runs its Action, then applies the state transform")
after
  Supervisor.stop(supervisor)
end
