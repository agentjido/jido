Code.require_file("effects_as_data.ex", __DIR__)

defmodule Jido.Examples.Actions.EffectsAsDataTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Actions.EffectsAsData.PrepareEmail

  test "returns an effect request without dispatching it" do
    assert {:ok, %{status: :prepared}, [effect]} =
             Jido.Exec.run(PrepareEmail, %{message_id: "message-1", recipient: "ops@example.test"})

    assert effect == %{
             kind: :deliver_email,
             message_id: "message-1",
             recipient: "ops@example.test"
           }
  end
end
