defmodule Jido.Topology.ViewTest do
  use ExUnit.Case, async: true

  alias Jido.{Agent, Topology}
  alias Jido.Codec.{Data, Registry}
  alias Jido.Topology.View
  alias JidoTest.AgentFixtures.{Add, CounterAgent}

  defp registry do
    Registry.new!(%{
      "agents/counter/v1" => {:agent, CounterAgent},
      "agents/core/v1" => {:agent, Agent},
      "schemas/counter/v1" => {:schema, CounterAgent.domain_schema()},
      "schemas/empty/v1" => {:schema, Zoi.object(%{})},
      "actions/add/v1" => {:action, Add}
    })
  end

  defp instance do
    stored =
      Agent.new!(
        name: "stored_counter",
        metadata: %{"private" => "hidden metadata"},
        routes: [{"counter.add", Add}]
      )

    Topology.new!(
      name: "system",
      metadata: %{"private" => "hidden topology metadata"},
      agents: [
        %{key: :compiled, module: CounterAgent},
        %{key: :stored, definition: stored}
      ],
      resources: [%{key: :events, kind: :bus}],
      children: [
        %{key: :team, topology: %{name: "team"}, activation: :lazy}
      ]
    )
    |> Topology.instantiate(id: "root")
    |> Topology.unwrap!()
  end

  defp status do
    %{
      status: :degraded,
      ready?: false,
      activation: :lazy,
      active_members: 1,
      dormant_members: 1,
      target_revision: 4,
      ready: 2,
      pending: 0,
      restore_error: nil,
      errors: %{
        "agent/stored" => {:member_start_failed, "private failure detail"},
        self() => "unknown failure"
      },
      member_statuses: %{
        "agent/compiled" => :ready,
        "agent/stored" => :error
      },
      children: %{
        "team" => %{
          id: "root/child/team",
          status: :failed,
          error: {:child_boot_failed, "private child detail"}
        }
      }
    }
  end

  test "projects an accepted instance and status without runtime access" do
    assert {:ok, view} = View.project(instance(), status(), registry())
    assert :ok = Data.check_document(view)

    assert %{
             "type" => "jido.topology.view",
             "version" => 1,
             "id" => "root",
             "name" => "system",
             "revision" => 4,
             "activation" => "lazy",
             "readiness" => %{
               "status" => "degraded",
               "ready" => false,
               "active_members" => 1,
               "dormant_members" => 1,
               "ready_components" => 2,
               "pending_components" => 0
             }
           } = view

    assert %{"total" => 2, "truncated" => false, "items" => members} = view["members"]
    assert Enum.map(members, & &1["key"]) == ["agent/compiled", "agent/stored"]
    assert Enum.at(members, 0)["status"] == "ready"
    assert Enum.at(members, 1)["status"] == "error"
    assert Enum.all?(members, &is_map(&1["agent"]))

    assert view["resources"] == %{
             "items" => [%{"key" => "bus/events", "kind" => "bus"}],
             "total" => 1,
             "truncated" => false
           }

    assert view["children"] == %{
             "items" => [
               %{
                 "key" => "team",
                 "name" => "team",
                 "activation" => "lazy",
                 "status" => "failed",
                 "error" => %{"code" => "child_boot_failed"}
               }
             ],
             "total" => 1,
             "truncated" => false
           }

    assert view["errors"] == %{
             "items" => [
               %{"component" => "agent/stored", "code" => "member_start_failed"},
               %{"component" => "child/team", "code" => "child_boot_failed"},
               %{"component" => "topology", "code" => "topology_error"}
             ],
             "total" => 3,
             "truncated" => false
           }

    encoded = inspect(view)
    refute encoded =~ "hidden"
    refute encoded =~ "private failure detail"
    refute encoded =~ "private child detail"
    refute encoded =~ inspect(CounterAgent)
    refute encoded =~ inspect(self())
  end

  test "bounds collections and does not expand child topologies" do
    assert {:ok, view} =
             View.project(instance(), status(), registry(),
               member_limit: 1,
               operation_limit: 0,
               resource_limit: 0,
               child_limit: 0,
               error_limit: 1
             )

    assert %{"total" => 2, "truncated" => true, "items" => [_]} = view["members"]
    assert %{"total" => 1, "truncated" => true, "items" => []} = view["resources"]
    assert %{"total" => 1, "truncated" => true, "items" => []} = view["children"]
    assert %{"truncated" => true, "items" => [_]} = view["errors"]

    [member] = view["members"]["items"]

    assert member["agent"]["operations"] == %{
             "items" => [],
             "total" => 1,
             "truncated" => true
           }
  end

  test "projects hibernated and unavailable member lifecycle values" do
    lifecycle_status =
      Map.merge(status(), %{
        hibernated_members: 1,
        errors: %{},
        member_statuses: %{
          "agent/compiled" => :hibernated,
          "agent/stored" => :unavailable
        }
      })

    assert {:ok, view} = View.project(instance(), lifecycle_status, registry())
    assert view["readiness"]["hibernated_members"] == 1
    assert Enum.map(view["members"]["items"], & &1["status"]) == ["hibernated", "unavailable"]
  end

  test "uses safe defaults for an incomplete status snapshot" do
    assert {:ok, view} = View.project(instance(), %{status: :ready}, registry())

    assert view["readiness"]["ready"]
    assert view["activation"] == "unknown"
    assert Enum.all?(view["members"]["items"], &(&1["status"] == "unknown"))
    assert [%{"status" => "unknown", "error" => nil}] = view["children"]["items"]
    assert view["errors"] == %{"items" => [], "total" => 0, "truncated" => false}
  end

  test "rejects invalid projection input and limits" do
    assert {:error, %Jido.Error.ValidationError{}} =
             View.project(instance(), status(), registry(), member_limit: 501)

    assert {:error, %Jido.Error.ValidationError{}} =
             View.project(instance(), status(), registry(), unknown: 1)

    assert {:error, %Jido.Error.ValidationError{}} =
             View.project(instance().definition, status(), registry())
  end
end
