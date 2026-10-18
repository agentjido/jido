defmodule Jido.Agent.Composition do
  @moduledoc false
  alias Jido.Agent
  alias Jido.Agent.{Mutation, Topology}

  def apply(agent, state, directives) do
    apply_changes(agent, state, directives, Enum.filter(directives, &Mutation.mutation?/1))
  end

  # Runner has already checked the complete state and effect batch.
  defp apply_changes(agent, state, _directives, []), do: {:ok, %{agent | state: state}}

  defp apply_changes(agent, state, directives, changes) do
    with {:ok, candidate, _diff} <- Agent.mutate(%{agent | state: state}, changes),
         :ok <- Agent.Mutation.validate_effects(agent, candidate, directives),
         do: {:ok, candidate}
  end

  @doc "Checks bindings without changing the authored definition."
  def bind(%Agent{} = agent) do
    with {:ok, _} <- Topology.bind(agent, agent.state), do: {:ok, agent}
  end
end
