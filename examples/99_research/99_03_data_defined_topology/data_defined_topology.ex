defmodule Jido.Examples.Research.DataDefinedTopology do
  @moduledoc "Adds a stored Agent definition to a topology declared with the DSL."

  alias Jido.Agent
  alias Jido.Agent.Codec, as: AgentCodec
  alias Jido.Topology
  alias __MODULE__.Record
  alias __MODULE__.Topology, as: HybridTopology

  @alice_schema Zoi.object(%{
                  label: Zoi.string() |> Zoi.default("Alice"),
                  total: Zoi.integer() |> Zoi.default(0)
                })

  def initial(id), do: HybridTopology.new(id: id)

  # JSON is the stored authoring document. The Registry supplies trusted code
  # and schema values. Alice has no wrapper Agent module.
  def stored_alice do
    with {:ok, alice} <-
           Agent.new(
             name: "Alice",
             schema: @alice_schema,
             routes: [{"examples.research.data_defined_topology.alice.record", Record}],
             metadata: %{"document_id" => "agents/alice"}
           ),
         {:ok, document, registry} <- AgentCodec.encode(alice),
         do: AgentCodec.decode(JSON.decode!(JSON.encode!(document)), registry)
  end

  def expanded(instance, member_source) do
    # Use the existing data API to expose its module-only restriction.
    # A separate definition field is a design choice that requires review.
    agents =
      instance.definition.agents ++
        [%{key: :alice, module: member_source, initial_state: %{total: 2}}]

    with {:ok, definition} <- Topology.new(%{instance.definition | agents: agents}),
         do: Topology.instantiate(definition, id: instance.id, input: instance.input)
  end

  def record(server, type, value) do
    signal =
      Jido.Signal.new!(type, %{value: value}, source: "/examples/research/data_defined_topology")

    Jido.AgentServer.call(server, signal)
  end
end
