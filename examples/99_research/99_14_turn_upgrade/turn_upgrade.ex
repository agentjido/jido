defmodule Jido.Examples.TurnUpgrade.Step do
  @moduledoc "The isolated Action that the example reloads between Flow steps."
  use Jido.Action, name: "research_upgrade_step"

  def run(input, _context),
    do: {:ok, %{total: input.total + 1, revisions: input.revisions ++ [1]}}
end

defmodule Jido.Examples.TurnUpgrade.Barrier do
  @moduledoc false
  use Jido.Action, name: "research_upgrade_barrier"

  def run(input, %{observer: observer, gate: gate}) do
    send(observer, {:between_upgrade_steps, gate, self()})

    receive do
      {:release, ^gate} -> {:ok, input}
    after
      5_000 -> {:error, Jido.Action.Error.execution_error("Upgrade barrier timed out")}
    end
  end

  def run(input, _context), do: {:ok, input}
end

defmodule Jido.Examples.TurnUpgrade.Pipeline do
  @moduledoc false
  use Jido.Flow, name: "research_upgrade_pipeline"

  flow do
    step "first",
      action: Jido.Examples.TurnUpgrade.Step,
      params: %{total: 0, revisions: []}

    step "barrier", action: Jido.Examples.TurnUpgrade.Barrier, params: result("first")
    step "second", action: Jido.Examples.TurnUpgrade.Step, params: result("barrier")
    output result("second")
  end
end

defmodule Jido.Examples.TurnUpgrade do
  @moduledoc """
  Tests whether a live Turn retains one Action revision across a code load.
  Only Step is reloaded. Tests are serial and pause outside that module.
  This is a deployment probe, not a core upgrade API or release installer.
  """
  use Jido.Agent, name: "research_turn_upgrade"

  agent do
    schema Zoi.object(%{
             total: Zoi.integer() |> Zoi.default(0),
             revisions: Zoi.list(Zoi.integer()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/upgrade"
    route "upgrade.run", __MODULE__.Pipeline
  end

  def run(server, context \\ %{}),
    do:
      Jido.AgentServer.call(
        server,
        Jido.Signal.new!("upgrade.run", %{}, source: "/examples/upgrade"),
        context: context
      )

  @doc "Loads revision 1 or 2 of the isolated Step, with no forced code purge."
  def install_step(revision) when revision in [1, 2] do
    module = __MODULE__.Step
    true = :code.soft_purge(module)
    :code.delete(module)
    amount = if revision == 1, do: 1, else: 10

    previous = Code.compiler_options(ignore_module_conflict: true)

    try do
      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            use Jido.Action, name: "research_upgrade_step"

            def run(input, _context),
              do:
                {:ok,
                 %{
                   total: input.total + unquote(amount),
                   revisions: input.revisions ++ [unquote(revision)]
                 }}
          end
        end
      )
    after
      Code.compiler_options(ignore_module_conflict: previous.ignore_module_conflict)
    end

    :ok
  end
end
