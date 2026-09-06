# Contract probes for Rounds 25 and 30. These do not measure time.
defmodule JidoCoreEffects.Owned do
  use Jido.Plugin

  def state_spec(_opts),
    do: {:owned, Zoi.integer() |> Zoi.transform({__MODULE__, :increment, []})}

  def increment(value, _opts), do: value + 1
  def update_state(value, _directives, _opts), do: {:ok, value}
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
{:ok, %{owned: 2}, []} = Jido.Plugin.update_state({:ok, %{owned: 1}, []}, specs)
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

  {:error, %Jido.Error.ValidationError{message: "Agent state does not match its schema"}} =
    Jido.Agent.cmd(instance, signal,
      task_supervisor: JidoCoreEffects.TaskSupervisor,
      context: %{probe_owner: self()}
    )

  receive do
    :action_ran -> :ok
  after
    1_000 -> raise "Action did not run"
  end

  IO.puts("Round 30: the command runs its Action, then rejects the second state parse")
after
  Supervisor.stop(supervisor)
end
