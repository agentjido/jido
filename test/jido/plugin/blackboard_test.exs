defmodule Jido.Plugin.BlackboardTest do
  use Jido.Test.Case, async: true
  use Covenant.Case, component: "jido.plugin.blackboard", async: true

  alias Jido.{Agent, AgentServer, Blackboard}
  alias Jido.Plugin.Blackboard.{Client, Server}
  alias Jido.Test.AgentServer.Assertions

  defmodule Owner do
    use Jido.Agent,
      name: "blackboard_owner",
      plugins: [{Server, %{name: "inventory", initial: %{"old" => 1}}}]
  end

  defmodule Probe do
    alias Jido.Joi
    alias Jido.Plugin.Blackboard.Client.Patch

    use Jido.Agent,
      name: "blackboard_client_probe",
      plugins: [{Client, %{name: "inventory", read_on: ["probe.read"], timeout: 200}}]

    state do
      schema Joi.object(%{
               snapshot: Joi.map() |> Joi.default(%{}),
               result: Joi.map() |> Joi.default(%{}),
               request_id: Joi.string() |> Joi.nullable() |> Joi.default(nil)
             })
    end

    routes do
      signal_source "/blackboard/probe"

      route "probe.read", as: :read do
        action params, schema: Joi.object(%{snapshot: Joi.map() |> Joi.default(%{})}), context: context do
          snapshot =
            case context.plugin_inputs[Client] do
              %{runtime: snapshot} when not is_nil(snapshot) -> snapshot
              _no_live_input -> params.snapshot
            end

          {:ok, %{context.agent_state | snapshot: snapshot}}
        end
      end

      route "probe.patch", as: :patch do
        action %{revision: revision, request_id: request_id, put: put, delete: delete},
          schema:
            Joi.object(%{
              revision: Joi.string(),
              request_id: Joi.string(),
              put: Joi.map(),
              delete: Joi.list(Joi.string())
            }),
          context: context do
          {:ok, %{context.agent_state | request_id: request_id},
           [%Patch{request_id: request_id, revision: revision, put: put, delete: delete}]}
        end
      end

      route "jido.blackboard.patch.result" do
        action _params, schema: Joi.map(), context: context do
          {:ok, %{context.agent_state | result: context.signal.data}}
        end
      end
    end
  end

  @tag obligation: "jido.plugin.blackboard.I1"
  test "the name is unique within an instance and released when the owner stops", %{jido: jido} do
    other = :"blackboard_test_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: other, namespace: unique_id("blackboard-ns")})
    assert {:ok, owner} = Assertions.start_agent(jido, Owner)
    assert {:ok, _other_owner} = Assertions.start_agent(other, Owner)
    assert {:error, _reason} = Assertions.start_agent(jido, Owner)

    assert {:ok, %{revision: revision}} = Blackboard.read(jido, "inventory")
    assert {:ok, %{values: %{"old" => 1}}} = Blackboard.read(other, "inventory")

    assert :ok = Jido.stop_agent(jido, owner)
    assert {:error, :unavailable} = Blackboard.read(jido, "inventory")

    assert {:ok, _replacement} = Assertions.start_agent(jido, Owner)
    assert {:error, :conflict} = Blackboard.patch(jido, "inventory", revision, %{"old" => 2})
    assert {:ok, %{values: %{"old" => 1}}} = Blackboard.read(jido, "inventory")
  end

  @tag obligation: "jido.plugin.blackboard.I2"
  test "changes and removals apply together, with portable values and a fresh revision", %{jido: jido} do
    assert {:ok, _owner} = Assertions.start_agent(jido, Owner)
    assert {:ok, %{revision: revision, values: %{"old" => 1}} = original} = Blackboard.read(jido, "inventory")

    assert {:error, :invalid_request} =
             Blackboard.patch(jido, "inventory", revision, %{"new" => [%{"pid" => self()}]})

    assert {:error, :invalid_request} = Blackboard.patch(jido, "inventory", revision, %{new: 2})
    assert {:error, :invalid_request} = Blackboard.patch(jido, "inventory", revision, %{"old" => 2}, ["old"])
    assert {:error, :invalid_request} = Blackboard.patch(jido, "inventory", revision, %{}, ["old" | :invalid])
    assert {:error, :invalid_request} = Blackboard.patch(jido, "inventory", revision, %{"old" => 2}, [], 4_294_967_296)
    assert {:ok, ^original} = Blackboard.read(jido, "inventory")

    assert {:ok, %{values: %{"new" => 2}, revision: next} = changed} =
             Blackboard.patch(jido, "inventory", revision, %{"new" => 2}, ["old"])

    refute next == revision
    assert {:error, :conflict} = Blackboard.patch(jido, "inventory", revision, %{"old" => 3}, ["new"])
    assert {:ok, ^changed} = Blackboard.read(jido, "inventory")
  end

  @tag obligation: "jido.plugin.blackboard.I3"
  test "selected live reads fail when the board is absent and pure turns use explicit data", %{jido: jido} do
    assert {:ok, probe} = Assertions.start_agent(jido, Probe)
    assert {:ok, %{status: :failed}} = AgentServer.call(probe, Probe.read_signal!(%{}))
    assert AgentServer.snapshot(probe).agent.state.snapshot == %{}

    read = Probe.read_signal!(%{snapshot: %{values: %{"old" => 7}, revision: "explicit"}})
    agent = Agent.instantiate!(Probe.definition(), id: unique_id("pure"))
    assert {:ok, pure, []} = Agent.cmd(agent, read)
    assert pure.state.snapshot == %{values: %{"old" => 7}, revision: "explicit"}

    assert {:ok, %{status: :committed}} = AgentServer.call(probe, patch_signal("absent", "missing"))

    assert_eventually(
      AgentServer.snapshot(probe).agent.state.result == %{
        "board" => "inventory",
        "request_id" => "missing",
        "status" => "unavailable"
      }
    )

    assert {:ok, _owner} = Assertions.start_agent(jido, Owner)
    assert {:ok, %{status: :committed}} = AgentServer.call(probe, Probe.read_signal!(%{}))
    assert %{values: %{"old" => 1}} = AgentServer.snapshot(probe).agent.state.snapshot
  end

  @tag obligation: "jido.plugin.blackboard.I4"
  test "invalid Directives cannot patch and a committed timeout can have applied a write", %{jido: jido} do
    assert {:ok, owner} = Assertions.start_agent(jido, Owner)
    assert {:ok, probe} = Assertions.start_agent(jido, Probe)
    assert {:ok, %{revision: revision} = original} = Blackboard.read(jido, "inventory")

    invalid = Probe.patch_signal!(%{revision: revision, request_id: "invalid", put: %{"old" => 2}, delete: ["old"]})
    assert {:ok, %{status: :failed}} = AgentServer.call(probe, invalid)
    assert AgentServer.snapshot(probe).agent.state.request_id == nil
    assert {:ok, ^original} = Blackboard.read(jido, "inventory")

    %{pid: board} = Assertions.plugin(owner, Server)
    :ok = :sys.suspend(board)

    try do
      assert {:ok, %{status: :committed}} = AgentServer.call(probe, patch_signal(revision, "timeout"))
      assert AgentServer.snapshot(probe).agent.state.request_id == "timeout"

      assert_eventually(
        AgentServer.snapshot(probe).agent.state.result == %{
          "board" => "inventory",
          "request_id" => "timeout",
          "status" => "timeout"
        }
      )
    after
      :ok = :sys.resume(board)
    end

    assert {:ok, %{status: :committed}} = AgentServer.call(probe, Probe.read_signal!(%{}))
    assert %{values: %{"old" => 2}} = AgentServer.snapshot(probe).agent.state.snapshot

    assert {:ok, %{status: :committed}} = AgentServer.call(probe, patch_signal(revision, "stale"))
    assert_eventually(AgentServer.snapshot(probe).agent.state.result["status"] == "conflict")
    assert AgentServer.snapshot(probe).agent.state.result["request_id"] == "stale"
  end

  defp patch_signal(revision, request_id) do
    Probe.patch_signal!(%{revision: revision, request_id: request_id, put: %{"old" => 2}, delete: []})
  end
end
