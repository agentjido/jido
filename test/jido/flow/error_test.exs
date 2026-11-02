defmodule Jido.Flow.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.Error

  test "converts non-exception failures without raising" do
    assert Error.to_map(:invalid) == %{
             type: :flow_definition_error,
             message: ":invalid",
             details: %{},
             retryable?: false
           }
  end
end
