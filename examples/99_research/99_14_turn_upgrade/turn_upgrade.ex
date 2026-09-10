defmodule Jido.Examples.TurnUpgrade do
  @moduledoc "Probes the public idle boundary for a live Agent code upgrade."
  use Jido.Agent, name: "research_turn_upgrade"

  agent do
    schema Zoi.object(%{
             total: Zoi.integer() |> Zoi.default(0),
             revisions: Zoi.list(Zoi.integer()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/research/turn_upgrade"
    route "examples.research.turn_upgrade.run", __MODULE__.Pipeline
  end

  def run(server),
    do:
      Jido.AgentServer.call(
        server,
        Jido.Signal.new!(
          "examples.research.turn_upgrade.run",
          %{},
          source: "/examples/research/turn_upgrade"
        )
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
            use Jido.Action,
              name: "research_upgrade_step",
              schema:
                Zoi.object(%{
                  total: Zoi.integer(),
                  revisions: Zoi.list(Zoi.integer())
                })

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

defmodule Jido.Examples.TurnUpgrade.Step do
  @moduledoc "The stable Action identity that the probe reloads."
  use Jido.Action,
    name: "research_upgrade_step",
    schema: Zoi.object(%{total: Zoi.integer(), revisions: Zoi.list(Zoi.integer())})

  def run(input, _context),
    do: {:ok, %{total: input.total + 1, revisions: input.revisions ++ [1]}}
end

defmodule Jido.Examples.TurnUpgrade.Pipeline do
  @moduledoc "Runs the reloadable Action twice in one finite Flow."
  use Jido.Flow, name: "research_upgrade_pipeline"

  flow do
    step "first",
      action: Jido.Examples.TurnUpgrade.Step,
      params: %{total: 0, revisions: []}

    step "second", action: Jido.Examples.TurnUpgrade.Step, params: result("first")
    output result("second")
  end
end
