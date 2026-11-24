defmodule Jido.Examples.AI.Reasoning.TaskList.PlanClient do
  @moduledoc false
  @behaviour Jido.AI.InferenceClient

  alias Jido.Examples.Support.OfflineInferenceClient, as: Offline

  @impl true
  def generate_object(model, prompt, schema, options) do
    %{role: :user, content: [%{text: brief}]} = prompt |> ReqLLM.Context.to_list() |> List.last()

    with {:ok, object} <- plan_for(brief, schema) do
      Offline.generate_object(model, prompt, schema, Keyword.put(options, :offline_object, object))
    end
  end

  for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks), name != :generate_object do
    @impl true
    defdelegate unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))), to: Offline
  end

  defp plan_for("Review the release.", schema), do: validate_plan(["changes", "checks", "release_notes"], schema)
  defp plan_for("Report the verification results.", schema), do: validate_plan(["checks"], schema)
  defp plan_for("Return duplicate tasks.", schema), do: validate_plan(["checks", "checks"], schema)

  # Pass invalid output to the Flow to test its allowlist check.
  defp plan_for("Return an unknown task.", _schema), do: {:ok, %{"tasks" => ["changes", "publish"]}}

  defp validate_plan(tasks, schema), do: ReqLLM.Schema.validate(%{"tasks" => tasks}, schema)
end
