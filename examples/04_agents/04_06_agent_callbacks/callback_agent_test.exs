Code.require_file("callback_agent.ex", __DIR__)

defmodule Jido.Examples.CallbackAgentTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.CallbackAgent

  test "initialize transforms candidate state before final validation" do
    agent = CallbackAgent.instantiate!(id: "case-7", state: %{count: 4})

    assert agent.state == %{count: 4, initialized_for: "case-7"}
    assert agent.vsn == 2
  end

  test "public snapshot and restore use the Agent checkpoint callbacks" do
    agent = CallbackAgent.instantiate!(id: "case-7", state: %{count: 4})

    assert {:ok, snapshot} = Jido.Persistence.snapshot(agent)
    assert snapshot.state_format == :custom
    assert snapshot.agent.state == %{id: "case-7", count: 4}
    assert {:ok, restored} = Jido.Persistence.restore(snapshot)
    assert restored == agent
  end

  test "restoration rejects a checkpoint outside its saved envelope" do
    assert {:error, _reason} = Jido.Persistence.restore(%{id: "case-7", count: 4})
  end
end
