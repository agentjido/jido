defmodule Jido.Examples.Topology.AuthoringExtension.Role do
  @moduledoc false
  defstruct [:key, :module, :__spark_metadata__]
end

defmodule Jido.Examples.Topology.AuthoringExtension.Roles do
  @moduledoc "Lowers role declarations into ordinary Topology Agent entries."
  @behaviour Jido.Topology.Extension

  @role %Spark.Dsl.Entity{
    name: :role,
    target: Jido.Examples.Topology.AuthoringExtension.Role,
    args: [:key, :module],
    schema: [
      key: [type: :atom, required: true],
      module: [type: :atom, required: true]
    ]
  }

  use Spark.Dsl.Extension,
    dsl_patches: [
      %Spark.Dsl.Patch.AddEntity{section_path: [:topology, :agents], entity: @role}
    ]

  @impl Jido.Topology.Extension
  def lower_topology(config, entities) do
    {roles, rest} =
      Enum.split_with(
        entities,
        &is_struct(&1, Jido.Examples.Topology.AuthoringExtension.Role)
      )

    agents =
      config.agents ++
        Enum.map(roles, fn role ->
          %{key: role.key, module: role.module, initial_state: %{label: Atom.to_string(role.key)}}
        end)

    metadata = Map.put(config.metadata, :role_count, length(roles))
    {:ok, %{config | agents: agents, metadata: metadata}, rest}
  end
end

defmodule Jido.Examples.Topology.AuthoringExtension do
  @moduledoc "Uses one static extension to declare a normal Topology Agent."

  use Jido.Topology,
    name: "topology_authoring_extension",
    extensions: [Jido.Examples.Topology.AuthoringExtension.Roles]

  topology do
    agents do
      role(:operator, Jido.Examples.Topology.Cell)
    end
  end
end
