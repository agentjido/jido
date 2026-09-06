defmodule Jido.Examples.Factory.FlowFactory.Contract do
  @moduledoc "Portable assignments and artifacts for the Flow factory."

  def roles, do: ~w(research design api ui test integration quality security delivery)

  def assignment_schema do
    Zoi.object(%{
      mission_id: Zoi.string() |> Zoi.min(1),
      role: Zoi.enum(roles()),
      goal: Zoi.string() |> Zoi.min(1) |> Zoi.max(20_000),
      revision: Zoi.integer() |> Zoi.min(0) |> Zoi.max(2),
      inputs: Zoi.map()
    })
  end

  def artifact_schema do
    Zoi.object(%{
      id: Zoi.string(),
      mission_id: Zoi.string(),
      role: Zoi.enum(roles()),
      revision: Zoi.integer() |> Zoi.min(0) |> Zoi.max(2),
      input_hash: Zoi.string(),
      text: Zoi.string() |> Zoi.min(1) |> Zoi.max(30_000),
      verdict: Zoi.enum([:not_reviewed, :accepted, :changes_required]),
      findings: Zoi.list(Zoi.string())
    })
  end

  def cycle_schema do
    Zoi.object(%{
      mission_id: Zoi.string(),
      goal: Zoi.string(),
      revision: Zoi.integer() |> Zoi.min(0) |> Zoi.max(2),
      security: Zoi.boolean(),
      discovery: Zoi.map(),
      components: Zoi.list(Zoi.map()),
      package: Zoi.map(),
      review: Zoi.map(),
      accepted: Zoi.boolean()
    })
  end

  def assignment_id(input), do: "#{input.mission_id}/#{input.role}/#{input.revision}"

  def output_schema do
    Zoi.object(%{
      mission: cycle_schema(),
      repairs: Zoi.integer() |> Zoi.min(0) |> Zoi.max(2),
      handoff: artifact_schema()
    })
  end

  def input_hash(input) do
    :crypto.hash(:sha256, :erlang.term_to_binary(input, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  def invalid(message), do: {:error, Jido.Action.Error.validation_error(message)}
end
