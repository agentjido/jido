defmodule JidoTest.Topology.AuthoringExtensionTest do
  use JidoTest.Case, async: false

  defmodule Role do
    defstruct [:key, :module, :__spark_metadata__]
  end

  defmodule Roles do
    @role %Spark.Dsl.Entity{
      name: :role,
      target: Role,
      args: [:key, :module],
      schema: [
        key: [type: :atom, required: true],
        module: [type: :atom, required: true]
      ]
    }

    use Spark.Dsl.Extension,
      sections: [%Spark.Dsl.Section{name: :roles, entities: [@role]}]

    @behaviour Jido.Topology.Extension

    @impl Jido.Topology.Extension
    def lower_topology(config, entities) do
      {roles, rest} = Enum.split_with(entities, &match?(%Role{}, &1))

      agents =
        Enum.reduce(roles, config.agents, fn role, agents ->
          agents ++ [%{key: role.key, module: role.module}]
        end)

      metadata = Map.put(config.metadata, :role_count, length(roles))
      {:ok, %{config | agents: agents, metadata: metadata}, rest}
    end
  end

  defmodule Unclaimed do
    use Spark.Dsl.Extension, sections: Roles.sections()
    def lower_topology(config, entities), do: {:ok, config, entities}
  end

  defmodule PatchedRoles do
    @role %Spark.Dsl.Entity{
      name: :role,
      target: Role,
      args: [:key, :module],
      schema: [
        key: [type: :atom, required: true],
        module: [type: :atom, required: true]
      ]
    }

    use Spark.Dsl.Extension,
      dsl_patches: [
        %Spark.Dsl.Patch.AddEntity{section_path: [:agents], entity: @role}
      ]

    defdelegate lower_topology(config, entities), to: Roles
  end

  defmodule CoreStructRoles do
    @role %Spark.Dsl.Entity{
      name: :core_struct_role,
      target: Jido.Topology.DSL.Agent,
      args: [:key, :module],
      schema: [
        key: [type: :atom, required: true],
        module: [type: :atom, required: true]
      ]
    }

    use Spark.Dsl.Extension,
      sections: [%Spark.Dsl.Section{name: :core_struct_roles, entities: [@role]}]

    def lower_topology(config, entities) do
      {roles, rest} =
        Enum.split_with(entities, &match?(%Jido.Topology.DSL.Agent{}, &1))

      agents = config.agents ++ Enum.map(roles, &%{key: &1.key, module: &1.module})
      {:ok, %{config | agents: agents}, rest}
    end
  end

  defmodule BadConfig do
    use Spark.Dsl.Extension
    def lower_topology(config, entities), do: {:ok, Map.put(config, :surprise, true), entities}
  end

  defmodule NoLower do
    use Spark.Dsl.Extension
  end

  defmodule InvalidAgents do
    use Spark.Dsl.Extension
    def lower_topology(config, entities), do: {:ok, %{config | agents: :invalid}, entities}
  end

  defmodule First do
    def lower_topology(config, entities),
      do: {:ok, Map.put(config, :order, [:first]), entities}
  end

  defmodule Second do
    def lower_topology(%{order: [:first]} = config, []),
      do: {:ok, %{config | order: [:first, :second]}, []}
  end

  defmodule InvalidResult do
    def lower_topology(_, _), do: :invalid
  end

  defmodule InvalidConfigResult do
    def lower_topology(_, _), do: {:ok, %Role{}, []}
  end

  defmodule InvalidRemainingResult do
    def lower_topology(config, _), do: {:ok, config, :invalid}
  end

  defmodule InvalidErrorResult do
    def lower_topology(_, _), do: {:error, :invalid}
  end

  defmodule Reject do
    def lower_topology(_, _), do: Jido.Agent.Authoring.error("Extension rejection")
  end

  test "an extension section lowers into ordinary Topology configuration" do
    module = Module.concat(__MODULE__, "Topology#{System.unique_integer([:positive])}")

    compile_isolated(
      quote do
        defmodule unquote(module) do
          use Jido.Topology, name: "extended_topology", extensions: [Roles]

          roles do
            role(:operator, Jido.Examples.Topology.Cell)
          end

          resources do
            bus :events
          end

          connections do
            subscribe :operator, to: :events, path: "htn.**"
          end
        end
      end
    )

    definition = module.topology()
    assert definition.metadata == %{role_count: 1}
    assert [%{key: "operator", module: Jido.Examples.Topology.Cell}] = definition.agents
    assert {:ok, instance} = module.new(id: "extended")
    assert map_size(instance.plan.agents) == 1
    assert map_size(instance.plan.resources) == 1
    assert {:ok, document, registry} = Jido.Topology.Codec.encode(definition)
    assert {:ok, ^definition} = Jido.Topology.Codec.decode(document, registry)
  end

  test "an extension entity can be added to an existing Topology section" do
    module = Module.concat(__MODULE__, "Patched#{System.unique_integer([:positive])}")

    compile_isolated(
      quote do
        defmodule unquote(module) do
          use Jido.Topology, name: "patched_topology", extensions: [PatchedRoles]

          agents do
            agent(:base, Jido.Examples.Topology.Cell)
            role(:operator, Jido.Examples.Topology.Cell)
          end
        end
      end
    )

    definition = module.topology()
    assert definition.metadata == %{role_count: 1}
    assert Enum.map(definition.agents, & &1.key) == ["base", "operator"]
    assert {:ok, instance} = module.new(id: "patched")
    assert map_size(instance.plan.agents) == 2
  end

  test "a Core struct in a custom section remains an extension entity" do
    module = Module.concat(__MODULE__, "CoreStruct#{System.unique_integer([:positive])}")

    compile_isolated(
      quote do
        defmodule unquote(module) do
          use Jido.Topology, name: "core_struct_topology", extensions: [CoreStructRoles]

          core_struct_roles do
            core_struct_role(:operator, Jido.Examples.Topology.Cell)
          end
        end
      end
    )

    assert [%{key: "operator", module: Jido.Examples.Topology.Cell}] =
             module.topology().agents
  end

  test "unclaimed declarations fail at compilation" do
    module = Module.concat(__MODULE__, "Unclaimed#{System.unique_integer([:positive])}")

    assert_raise CompileError, ~r/Unclaimed Topology extension entities/, fn ->
      compile_isolated(
        quote do
          defmodule unquote(module) do
            use Jido.Topology, name: "unclaimed", extensions: [Unclaimed]

            roles do
              role(:operator, Jido.Examples.Topology.Cell)
            end
          end
        end
      )
    end
  end

  test "extension output passes the common Topology validation" do
    for {extension, message} <- [
          {BadConfig, ~r/Unknown/},
          {InvalidAgents, ~r/Expected a proper list/}
        ] do
      module = Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")

      assert_raise CompileError, message, fn ->
        compile_isolated(
          quote do
            defmodule unquote(module) do
              use Jido.Topology, name: "invalid", extensions: [unquote(extension)]
            end
          end
        )
      end
    end
  end

  test "invalid extension declarations fail at compilation" do
    for {extensions, message} <- [
          {[NoLower], ~r/must implement lower_agent\/2 or lower_topology\/2/},
          {[BadConfig, BadConfig], ~r/Duplicate Topology extension/}
        ] do
      module = Module.concat(__MODULE__, "Contract#{System.unique_integer([:positive])}")

      assert_raise CompileError, message, fn ->
        compile_isolated(
          quote do
            defmodule unquote(module) do
              use Jido.Topology,
                name: "invalid_extension_contract",
                extensions: unquote(extensions)
            end
          end
        )
      end
    end
  end

  test "extensions execute in declared order through the shared data contract" do
    assert {:ok, %{order: [:first, :second]}} =
             Jido.Topology.Extension.lower([First, Second], %{}, [])

    assert {:ok, %{}} = Jido.Topology.Extension.lower([], %{}, [])
  end

  test "duplicate, absent, and invalid extension contracts return structured errors" do
    for extensions <- [
          [First, First],
          [String],
          [nil],
          [InvalidResult],
          [InvalidConfigResult],
          [InvalidRemainingResult],
          [InvalidErrorResult],
          :invalid
        ] do
      assert {:error, error} = Jido.Topology.Extension.lower(extensions, %{}, [])
      assert is_exception(error)
    end

    assert {:error, error} = Jido.Topology.Extension.lower([Reject], %{}, [])
    assert Exception.message(error) == "Extension rejection"

    assert {:error, error} = Jido.Topology.Extension.lower([], %{}, [%Role{key: :x}])
    assert Exception.message(error) == "Unclaimed Topology extension entities"
  end

  defp compile_isolated(ast) do
    owner = self()

    {pid, ref} =
      spawn_monitor(fn -> send(owner, {self(), :compiled, Code.compile_quoted(ast)}) end)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        receive do
          {^pid, :compiled, result} -> result
        end

      {:DOWN, ^ref, :process, ^pid, {error, stack}} ->
        reraise error, stack
    after
      10_000 ->
        Process.exit(pid, :kill)
        flunk("Topology compilation did not finish")
    end
  end
end
