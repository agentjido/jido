defmodule Jido.BlackboardLoadTest do
  use Jido.Test.Case, async: true

  alias Jido.Blackboard
  alias Jido.Plugin.Blackboard.Server
  alias Jido.Test.AgentServer.Assertions

  @moduletag :load

  defmodule Owner do
    use Jido.Agent,
      name: "blackboard_load_owner",
      plugins: [{Server, %{name: "shared"}}]
  end

  test "concurrent writers from the same revision have one winner", %{jido: jido} do
    assert {:ok, _owner} = Assertions.start_agent(jido, Owner)
    assert {:ok, %{revision: revision}} = Blackboard.read(jido, "shared")

    results =
      1..64
      |> Task.async_stream(fn count -> Blackboard.patch(jido, "shared", revision, %{"count" => count}) end,
        max_concurrency: 64
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _snapshot}, &1))
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 63
    assert {:ok, ^winner} = Blackboard.read(jido, "shared")
  end
end
