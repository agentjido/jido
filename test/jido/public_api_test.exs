defmodule Jido.PublicAPITest do
  use Jido.Test.Case, async: true

  test "builds instance supervisor names" do
    assert Jido.Instance.Names.agent_supervisor(MyApp.Jido) == MyApp.Jido.AgentSupervisor
    assert Jido.Instance.Names.agent_supervisor(MyApp.Sub.Jido) == MyApp.Sub.Jido.AgentSupervisor
  end

  test "generates unique UUID7 identifiers" do
    id1 = Jido.Id.uuid7()
    id2 = Jido.Id.uuid7()

    assert Jido.Id.uuid7?(id1)
    assert Jido.Id.uuid7?(id2)
    refute id1 == id2
  end

  test "stop_agent/3 returns not_found for an unknown id", %{jido: jido} do
    assert {:error, :not_found} = Jido.stop_agent(jido, "missing-agent")
  end
end
