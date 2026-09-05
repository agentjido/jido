defmodule Jido.Examples.RecursiveLanguageModel do
  @moduledoc """
  Runs a local RLM simulation in one Agent Turn.

  A scripted model controls real recursive reads and reductions. Caller context
  supplies the model and external corpus store. Each successful Turn commits
  the final counts, source ranges, call tree, and work totals once. Failed work
  preserves Agent state but does not undo adapter calls. Retrying repeats those
  calls. Corpus handles must identify immutable revisions.

  Recursion is sequential within a Turn. There are no child Agents or durable
  intermediate commits. Use Server `exec_opts: [timeout: milliseconds]` for an
  execution deadline. The `analyze/5` timeout limits caller waiting only.
  """

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.RecursiveLanguageModel.Contracts
  alias Jido.Signal

  use Jido.Agent, name: "examples_recursive_language_model"

  agent do
    schema Zoi.object(%{
             corpus_id: Zoi.string() |> Zoi.default(""),
             counts: Contracts.counts() |> Zoi.default(%{}),
             source_ranges: Zoi.list(Contracts.range()) |> Zoi.default([]),
             call_tree: Zoi.list(Contracts.call_node()) |> Zoi.default([]),
             usage: Contracts.usage() |> Zoi.default(%{}),
             turns: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)
           })
  end

  routes do
    route "examples.rlm.run", Jido.Examples.RecursiveLanguageModel.Run
  end

  @doc "Builds a request. A nil range selects the complete corpus."
  def analyze_signal!(corpus_id, opts \\ []) do
    Signal.new!(
      "examples.rlm.run",
      %{
        corpus_id: corpus_id,
        query: :failed_jobs_by_service,
        range: Keyword.get(opts, :range),
        limits: Map.merge(Contracts.limits(), Keyword.get(opts, :limits, %{}))
      },
      source: "/examples/recursive_language_model"
    )
  end

  @doc "Runs the simulation through the Agent Server with transient clients."
  def analyze(server, corpus_id, model, store, opts \\ []) do
    Server.call(server, analyze_signal!(corpus_id, opts),
      context: %{model: model, store: store},
      timeout: Keyword.get(opts, :timeout, 5_000)
    )
  end
end

defmodule Jido.Examples.RecursiveLanguageModel.Run do
  @moduledoc false
  alias Jido.Examples.RecursiveLanguageModel.{Contracts, Runner}

  use Jido.Action, name: "examples_rlm_run", schema: Contracts.request()

  @impl true
  def run(input, %{agent_state: state} = context) do
    with {:ok, result} <- Runner.run(input, context) do
      {:ok, Map.merge(state, Map.put(result, :turns, state.turns + 1))}
    end
  end
end
