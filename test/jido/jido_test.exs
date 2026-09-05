defmodule JidoTest.JidoTest do
  use JidoTest.Case, async: true

  test "builds instance supervisor names" do
    assert Jido.agent_supervisor_name(MyApp.Jido) == MyApp.Jido.AgentSupervisor
    assert Jido.agent_supervisor_name(MyApp.Sub.Jido) == MyApp.Sub.Jido.AgentSupervisor
  end

  test "generates unique identifiers" do
    id1 = Jido.generate_id()
    id2 = Jido.generate_id()

    assert is_binary(id1)
    assert is_binary(id2)
    refute id1 == id2
  end

  test "stop_agent/3 returns not_found for an unknown id", %{jido: jido} do
    assert {:error, :not_found} = Jido.stop_agent(jido, "missing-agent")
  end
end
