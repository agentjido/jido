defmodule Jido.AgentServer.Composition.StartFailureTest do
  use Jido.Test.Case, async: true
  alias Jido.AgentServer, as: Server

  defmodule FailingMember do
    use Jido.Agent, name: "start_failure_member"
    def initialize(_state, _context), do: {:error, :member_failed}
  end

  defmodule RaisingMember do
    use Jido.Agent, name: "start_failure_raising_member"
    def initialize(_state, _context), do: raise("member failed")
  end

  defmodule FailingOwner do
    use Jido.Agent, name: "start_failure_owner"

    topology do
      agent :bad, FailingMember
    end
  end

  defmodule RaisingOwner do
    use Jido.Agent, name: "start_failure_raising_owner"

    topology do
      agent :bad, RaisingMember
    end
  end

  defp outcome(c, module) do
    case Jido.start_agent(c.jido, module, id: unique_id("owner")) do
      {:ok, server} ->
        # Let the worker and its root exit first in some runs, so await_ready
        # has to read the recorded reason.
        Process.sleep(:rand.uniform(5) - 1)
        Server.await_ready(server, 2_000)

      error ->
        error
    end
  end

  test "a member start failure reports its reason in every run", c do
    for _run <- 1..50 do
      assert {:error, reason} = outcome(c, FailingOwner)
      assert %{code: :initialize_failed} = reason
    end
  end

  test "a raising member reports its reason in every run", c do
    for _run <- 1..25 do
      assert {:error, reason} = outcome(c, RaisingOwner)
      assert %{details: %{code: :agent_callback_failed}} = reason
    end
  end
end
