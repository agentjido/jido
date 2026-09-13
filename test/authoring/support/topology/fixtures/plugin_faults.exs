defmodule JidoTest.Authoring.Topology.Fixtures.FaultFacet do
  use Jido.Topology.Plugin

  alias Jido.Topology.Plugin.Contribution
  alias JidoTest.Authoring.Topology.Fixtures

  def contribute(context, _opts) do
    contribution = %Contribution{plugin: context.plugin}

    case context.agent_key do
      "raise" ->
        raise ArgumentError, "authoring fault"

      "throw" ->
        throw(:authoring_fault)

      "exit" ->
        exit(:authoring_fault)

      "invalid_result" ->
        :ok

      "invalid_shape" ->
        {:ok, %{contribution | resources: :invalid}}

      "wrong_owner" ->
        {:ok, %{contribution | plugin: Fixtures.InboxPackage}}

      "invalid_entry" ->
        {:ok, %{contribution | resources: [42]}}

      "reserved_config" ->
        {:ok, %{contribution | resources: [%{key: :private, config: [name: "taken"]}]}}

      "conflict" ->
        {:ok, %{contribution | resources: [%{key: :events}]}}

      "missing_endpoint" ->
        {:ok,
         %{contribution | connections: [%{agent: context.agent_key, to: :missing, path: "**"}]}}

      "cycle" ->
        {:ok, %{contribution | relationships: [%{parent: context.agent_key, child: :parent}]}}

      "duplicate_owner" ->
        {:ok, %{contribution | relationships: [%{parent: :other, child: context.agent_key}]}}

      "rejected" ->
        {:error,
         Jido.Error.validation_error("Plugin rejected authoring input",
           kind: :input,
           details: %{reason: :authoring_fault}
         )}

      "healthy" ->
        {:ok, contribution}
    end
  end
end

defmodule JidoTest.Authoring.Topology.Fixtures.FaultPackage do
  use Jido.Plugin, topology: JidoTest.Authoring.Topology.Fixtures.FaultFacet
end

defmodule JidoTest.Authoring.Topology.Fixtures.FaultWorker do
  alias JidoTest.Authoring.Topology.Fixtures

  use Jido.Agent,
    name: "authoring_fault_worker",
    plugins: [Fixtures.InboxPackage, Fixtures.FaultPackage]
end

# Each source definition is valid. Only planning invokes the faulty facet.
for {module, key} <- [
      {JidoTest.Authoring.Topology.Fixtures.FaultRaise, "raise"},
      {JidoTest.Authoring.Topology.Fixtures.FaultThrow, "throw"},
      {JidoTest.Authoring.Topology.Fixtures.FaultExit, "exit"},
      {JidoTest.Authoring.Topology.Fixtures.FaultResult, "invalid_result"},
      {JidoTest.Authoring.Topology.Fixtures.FaultShape, "invalid_shape"},
      {JidoTest.Authoring.Topology.Fixtures.FaultOwner, "wrong_owner"},
      {JidoTest.Authoring.Topology.Fixtures.FaultEntry, "invalid_entry"},
      {JidoTest.Authoring.Topology.Fixtures.FaultConfig, "reserved_config"},
      {JidoTest.Authoring.Topology.Fixtures.FaultConflict, "conflict"},
      {JidoTest.Authoring.Topology.Fixtures.FaultEndpoint, "missing_endpoint"},
      {JidoTest.Authoring.Topology.Fixtures.FaultCycle, "cycle"},
      {JidoTest.Authoring.Topology.Fixtures.FaultDuplicateOwner, "duplicate_owner"},
      {JidoTest.Authoring.Topology.Fixtures.FaultRejected, "rejected"},
      {JidoTest.Authoring.Topology.Fixtures.FaultHealthy, "healthy"}
    ] do
  defmodule module do
    alias JidoTest.Authoring.Topology.Fixtures

    use Jido.Topology,
      name: "authoring_fault_" <> key,
      agents: [
        %{key: :parent, module: Fixtures.Worker},
        %{key: :other, module: Fixtures.Worker},
        %{key: key, module: Fixtures.FaultWorker}
      ],
      resources: [%{key: :events}],
      relationships: [%{parent: :parent, child: key}]
  end
end
