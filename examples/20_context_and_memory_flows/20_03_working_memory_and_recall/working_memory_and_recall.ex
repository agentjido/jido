defmodule Jido.Examples.ContextMemory.WorkingMemoryRecall.StructureWorkingMemory do
  use Jido.Action, name: "example_structure_working_memory"

  @impl true
  def run(%{plan: plan, facts: facts, preferences: preferences}, _context) do
    {:ok,
     %{
       plan: plan,
       facts: Enum.uniq(facts),
       preferences: preferences,
       owner: :application,
       version: 1
     }}
  end
end

defmodule Jido.Examples.ContextMemory.WorkingMemoryRecall.SemanticRecall do
  use Jido.Action, name: "example_semantic_recall"

  @impl true
  def run(%{query: query, scope: scope, memories: memories, limit: limit}, context) do
    eligible = Enum.filter(memories, &in_scope?(&1, scope))
    client = Jido.AI.InferenceClient.Selection.client!(context)
    texts = [query | Enum.map(eligible, & &1.text)]

    with {:ok, [query_vector | memory_vectors]} <- client.embed("offline:embedding", texts, []) do
      recalled =
        eligible
        |> Enum.zip(memory_vectors)
        |> Enum.map(fn {memory, vector} ->
          Map.put(memory, :score, cosine(query_vector, vector))
        end)
        |> Enum.sort_by(&{-&1.score, &1.id})
        |> Enum.take(limit)

      {:ok, %{query: query, scope: scope, recalled: recalled, considered: length(eligible)}}
    else
      {:error, reason} ->
        {:error, Jido.Error.execution_error("semantic recall failed", %{reason: reason})}
    end
  end

  defp in_scope?(memory, scope) do
    Enum.all?(scope, fn {key, value} -> Map.get(memory.scopes, key) == value end)
  end

  defp cosine(left, right) do
    dot = Enum.zip_with(left, right, &Kernel.*/2) |> Enum.sum()
    magnitude = fn vector -> vector |> Enum.map(&(&1 * &1)) |> Enum.sum() |> :math.sqrt() end

    denominator = magnitude.(left) * magnitude.(right)
    if denominator == 0.0, do: 0.0, else: dot / denominator
  end
end

defmodule Jido.Examples.ContextMemory.WorkingMemoryRecall.Combine do
  use Jido.Action, name: "example_combine_working_memory_recall"

  @impl true
  def run(%{working_memory: working_memory, recall: recall}, _context) do
    {:ok, %{working_memory: working_memory, recall: recall}}
  end
end

defmodule Jido.Examples.ContextMemory.WorkingMemoryRecall do
  use Jido.Flow,
    name: "example_working_memory_and_recall",
    schema:
      Jido.Joi.object(%{
        plan: Jido.Joi.string(),
        facts: Jido.Joi.list(Jido.Joi.string()),
        preferences: Jido.Joi.map(),
        query: Jido.Joi.string() |> Jido.Joi.min(1),
        scope: Jido.Joi.map(),
        memories: Jido.Joi.list(Jido.Joi.map()),
        limit: Jido.Joi.integer() |> Jido.Joi.min(1)
      })

  alias Jido.Examples.ContextMemory.WorkingMemoryRecall.{
    Combine,
    SemanticRecall,
    StructureWorkingMemory
  }

  flow do
    step "working_memory",
      action: StructureWorkingMemory,
      params: %{
        plan: input(:plan),
        facts: input(:facts),
        preferences: input(:preferences)
      }

    step "recall",
      action: SemanticRecall,
      params: %{
        query: input(:query),
        scope: input(:scope),
        memories: input(:memories),
        limit: input(:limit)
      }

    step "combine",
      action: Combine,
      params: %{working_memory: result("working_memory"), recall: result("recall")}

    output result("combine")
  end
end
