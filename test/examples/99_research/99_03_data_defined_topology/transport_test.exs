defmodule JidoTest.Examples.Research.DataTopologyTransportTest do
  use ExUnit.Case, async: true
  @moduletag :example

  alias Jido.Agent.Codec, as: AgentCodec
  alias Jido.Examples.Research.DataDefinedTopology.{Definitions, Startup, Transport}
  alias Jido.Topology
  alias Jido.Topology.Codec

  for topology_form <- [:dsl, :data], member_form <- [:module, :dsl_value, :json] do
    test "#{topology_form} Topology JSON retains exact #{member_form} Agent definitions and plan" do
      entries = entries(unquote(member_form))
      assert {:ok, definition} = Startup.definition(unquote(topology_form), entries)
      assert {:ok, decoded, document, registry} = Transport.round_trip(definition)
      assert decoded === definition
      assert document["type"] == "jido.topology"
      assert {:ok, ^document} = Codec.encode(definition, registry)
      assert {:ok, instance} = Topology.instantiate(definition, id: "json-members")
      assert {:ok, ^instance} = Topology.instantiate(decoded, id: "json-members")

      # A document cannot select modules or schemas outside the supplied Registry.
      assert {:error, %Jido.Error.ValidationError{}} = Codec.decode(document, %{})
    end
  end

  test "stable Agent documents retain distinct definitions and reject unknown identifiers" do
    registry = Definitions.registry()
    unknown = "unknown-behavior-#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

    for key <- [:alice, :bob, :charlie] do
      definition = Definitions.direct(key)
      assert {:ok, document} = AgentCodec.encode(definition, registry)

      assert {:ok, ^definition} =
               AgentCodec.decode(JSON.decode!(JSON.encode!(document)), registry)

      assert {:error, %Jido.Error.ValidationError{}} =
               AgentCodec.decode(
                 %{document | "module" => unknown},
                 registry
               )
    end

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end

  defp entries(:module), do: Startup.module_entries()

  defp entries(form) do
    assert {:ok, entries} = Startup.data_entries(form)
    entries
  end
end

defmodule JidoTest.Examples.Research.DataTopologyTransportActivationTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.DataTopologyAssertions

  alias Jido.Examples.Research.DataDefinedTopology.{Startup, Transport}
  alias Jido.Topology
  alias Jido.Topology.Controller

  for topology_form <- [:dsl, :data], member_form <- [:module, :json] do
    test "a decoded #{topology_form} Topology activates and runs #{member_form} members", c do
      entries = entries(unquote(member_form))
      assert {:ok, definition} = Startup.definition(unquote(topology_form), entries)
      assert {:ok, decoded, _document, _registry} = Transport.round_trip(definition)
      assert {:ok, instance} = Topology.instantiate(decoded, id: unique_id("decoded-members"))
      controller = start_supervised!({Controller, jido: c.jido, topology: instance})

      try do
        assert :ok = Controller.await_ready(controller)
        assert_started(c.jido, instance, entries)
        assert_executed(c.jido, instance, entries)
      after
        stop_plan(controller, c.jido, instance)
      end
    end
  end

  defp entries(:module), do: Startup.module_entries()

  defp entries(:json) do
    assert {:ok, entries} = Startup.data_entries(:json)
    entries
  end
end
