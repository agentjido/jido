Code.require_file("models.ex", __DIR__)

defmodule Jido.Examples.AI.ModelHelpersTest do
  use Jido.Test.Case, async: true

  @moduletag :integration

  alias Jido.Examples.AI.ModelHelpers.{FastAgent, PinnedAgent}

  test "each Agent exposes its direct model default" do
    assert FastAgent.explain().defaults.model == "openai:gpt-4o-mini"
    assert PinnedAgent.explain().defaults.model == "anthropic:claude-haiku-4-5"
  end

  test "a request can replace the default model without changing the definition" do
    assert {:ok, %{params: %{model: "openai:gpt-4.1-mini"}}} =
             FastAgent.preflight(%{input: "hello", model: "openai:gpt-4.1-mini"})

    assert FastAgent.explain().defaults.model == "openai:gpt-4o-mini"
    assert {:error, _} = FastAgent.preflight(%{input: "hello", model: :unknown})
  end
end
