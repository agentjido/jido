defmodule Jido.Examples.OutputRepair.Attempt do
  @moduledoc false
  alias Jido.Examples.LLM.Adapter
  use Jido.Action, name: "llm_repair_attempt"

  def run(%{state: state}, context) do
    with {:ok, raw} <-
           Adapter.call(context, :model, :complete, %{
             prompt: state.prompt,
             feedback: state.feedback,
             attempt: state.attempts + 1
           }) do
      case Zoi.parse(Adapter.answer_schema(), raw) do
        {:ok, result} ->
          {:ok,
           %{
             state
             | answer: result.answer,
               missing: 0,
               feedback: "",
               attempts: state.attempts + 1
           }}

        {:error, issues} ->
          {:ok, %{state | missing: 1, feedback: inspect(issues), attempts: state.attempts + 1}}
      end
    end
  end
end

defmodule Jido.Examples.OutputRepair.Pipeline do
  @moduledoc "Expected schema failures are attempt data. Three total attempts allow two repairs."
  alias Jido.Examples.LLM.Adapter
  use Jido.Flow, name: "llm_output_repair", schema: Adapter.prompt_schema()

  flow do
    iterate "repair" do
      state Zoi.object(%{
              prompt: Zoi.string(),
              answer: Zoi.string(),
              feedback: Zoi.string(),
              missing: Zoi.integer() |> Zoi.min(0) |> Zoi.max(1),
              attempts: Zoi.integer() |> Zoi.min(0)
            }),
            initial: %{prompt: input(:prompt), answer: "", feedback: "", missing: 1, attempts: 0}

      action Jido.Examples.OutputRepair.Attempt
      params %{state: state()}
      update body_result()
      while state(:missing) > 0
      max_iterations 3
    end

    step "finish" do
      action %{answer: answer, attempts: attempts} <- result("repair", :state),
             name: "llm_repair_finish",
             schema:
               Zoi.object(%{
                 answer: Zoi.string() |> Zoi.min(1),
                 missing: Zoi.literal(0),
                 attempts: Zoi.integer()
               }) do
        {:ok, %{answer: answer, attempts: attempts}}
      end
    end

    output result("finish")
  end
end

defmodule Jido.Examples.OutputRepair do
  @moduledoc "A bounded SDK Iterate loop sends actual validation feedback to the next model call."

  use Jido.Agent, name: "llm_repair_agent"

  agent do
    schema Zoi.object(%{
             answer: Zoi.string() |> Zoi.default(""),
             attempts: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/llm"

    route "llm.repair", Jido.Examples.OutputRepair.Pipeline do
      define :answer, args: [:prompt]
    end
  end
end
