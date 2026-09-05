defmodule Jido.Examples.Factory.Plan do
  @moduledoc "The first factory plan: parallel research and design, then build, then quality review."

  @doc "Returns the fixed dependency graph. Each department produces a text artifact."
  def steps do
    [
      %{
        id: "research",
        depends_on: [],
        brief: "List requirements, assumptions, and open questions. Do not claim web research."
      },
      %{
        id: "design",
        depends_on: [],
        brief: "Write a proposed design with interfaces and acceptance criteria."
      },
      %{
        id: "build",
        depends_on: ["research", "design"],
        brief:
          "Use the supplied inputs to write an implementation proposal with concrete examples. Do not claim to have run code."
      },
      %{
        id: "quality",
        depends_on: ["build"],
        brief:
          "Review the supplied implementation proposal. List defects, missing tests, and limits. Do not claim that tests passed."
      }
    ]
  end

  @doc false
  def stages do
    Map.new(steps(), fn step ->
      {step.id, Map.merge(step, %{status: :pending, text: ""})}
    end)
  end
end
