defmodule Jido.Agent.Turn.OutcomeTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Turn.Outcome

  test "Outcome has no public authoring API" do
    refute function_exported?(Outcome, :schema, 0)
    refute function_exported?(Outcome, :new, 1)
    refute function_exported?(Outcome, :new!, 1)
  end
end
