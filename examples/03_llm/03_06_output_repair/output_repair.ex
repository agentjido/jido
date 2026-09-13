defmodule Jido.Examples.OutputRepair do
  @moduledoc "Uses a bounded Flow Iterate loop to repair invalid model output."

  use Jido.Agent, name: "examples_llm_output_repair"

  agent do
    schema Zoi.object(%{
             answer: Zoi.string() |> Zoi.default(""),
             attempts: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/llm/output_repair"

    route "examples.llm.output_repair.answer", Jido.Examples.OutputRepair.Pipeline do
      define :answer, args: [:prompt]
    end
  end
end

defmodule Jido.Examples.OutputRepair.Repair do
  @moduledoc false
  alias Jido.Examples.LLM.Adapter

  use Jido.Action,
    name: "examples_llm_output_repair_step",
    schema:
      Zoi.object(%{
        repair:
          Zoi.object(%{
            prompt: Zoi.string() |> Zoi.min(1),
            answer: Zoi.string(),
            feedback: Zoi.string(),
            missing: Zoi.integer() |> Zoi.min(0) |> Zoi.max(1),
            attempts: Zoi.integer() |> Zoi.min(0)
          })
      })

  def run(%{repair: repair}, context) do
    with {:ok, raw} <-
           Adapter.call(context, :model, :complete, %{
             prompt: repair.prompt,
             feedback: repair.feedback,
             attempt: repair.attempts + 1
           }) do
      case Zoi.parse(Adapter.answer_schema(), raw) do
        {:ok, result} ->
          {:ok,
           %{
             repair
             | answer: result.answer,
               missing: 0,
               feedback: "",
               attempts: repair.attempts + 1
           }}

        {:error, issues} ->
          {:ok, %{repair | missing: 1, feedback: inspect(issues), attempts: repair.attempts + 1}}
      end
    end
  end
end

defmodule Jido.Examples.OutputRepair.Pipeline do
  @moduledoc "Allows three total attempts, including two repair requests."

  alias Jido.Examples.LLM.Adapter

  @state_schema Zoi.object(%{
                  prompt: Zoi.string() |> Zoi.min(1),
                  answer: Zoi.string(),
                  feedback: Zoi.string(),
                  missing: Zoi.integer() |> Zoi.min(0) |> Zoi.max(1),
                  attempts: Zoi.integer() |> Zoi.min(0)
                })

  use Jido.Flow,
    name: "examples_llm_output_repair_flow",
    schema: Adapter.prompt_schema()

  flow do
    iterate "repair" do
      state @state_schema,
        initial: %{prompt: input(:prompt), answer: "", feedback: "", missing: 1, attempts: 0}

      action Jido.Examples.OutputRepair.Repair
      params %{repair: state()}

      update body_result()
      while state(:missing) > 0
      max_iterations 3
    end

    step "finish",
         %{answer: answer, attempts: attempts} <- result("repair", :state),
         inline: [
           schema:
             Zoi.object(%{
               answer: Zoi.string() |> Zoi.min(1),
               missing: Zoi.literal(0),
               attempts: Zoi.integer() |> Zoi.min(1)
             })
         ] do
      {:ok, %{answer: answer, attempts: attempts}}
    end

    output result("finish")
  end
end
