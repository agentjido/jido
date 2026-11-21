Code.require_file("inline_actions.ex", __DIR__)

defmodule Jido.Examples.Actions.InlineActionsTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Actions.InlineActions.Greeting

  test "runs an owner-scoped inline Action through Exec" do
    assert {:ok, %{message: "Hello Ada"}} = Greeting.run(%{name: "Ada"}, %{prefix: "Hello "})
    assert {:error, %Jido.Error.ValidationError{}} = Greeting.run(%{name: ""}, %{prefix: "Hello "})
  end
end
