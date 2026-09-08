defmodule JidoTest.Agent.AuthoringExtensionTest do
  use JidoTest.Case, async: false

  defmodule Label do
    defstruct [:key, :value, :__spark_metadata__]
  end

  defmodule Ref do
    defstruct [:target]
  end

  defmodule Labels do
    @label %Spark.Dsl.Entity{
      name: :label,
      target: Label,
      args: [:key, :value],
      schema: [key: [type: :atom, required: true], value: [type: :any, required: true]]
    }
    use Spark.Dsl.Extension,
      dsl_patches: [%Spark.Dsl.Patch.AddEntity{section_path: [:agent], entity: @label}]

    def route_target_options, do: [:ref]

    def lower_agent(config, entities) do
      {labels, rest} = Enum.split_with(entities, &match?(%Label{}, &1))
      metadata = Enum.reduce(labels, config.metadata, &Map.put(&2, &1.key, &1.value))

      routes =
        Enum.map(config.routes, fn
          %{target: %Ref{target: target}} = route ->
            %{route | target: target}

          %{
            target:
              {%Jido.Agent.Extension.RouteTarget{
                 extension: __MODULE__,
                 option: :ref,
                 value: target
               }, defaults}
          } = route ->
            %{route | target: {target, defaults}}

          %{
            target: %Jido.Agent.Extension.RouteTarget{
              extension: __MODULE__,
              option: :ref,
              value: target
            }
          } = route ->
            %{route | target: target}

          route ->
            route
        end)

      {:ok, %{config | metadata: metadata, routes: routes}, rest}
    end
  end

  defmodule Unclaimed do
    use Spark.Dsl.Extension, dsl_patches: Labels.dsl_patches()
    def lower_agent(config, entities), do: {:ok, config, entities}
  end

  defmodule ConflictingRouteTarget do
    def route_target_options, do: [:ref]
  end

  defmodule InvalidRouteTargetOptions do
    def route_target_options, do: [:ref, :ref]
  end

  defmodule BadConfig do
    use Spark.Dsl.Extension
    def lower_agent(config, entities), do: {:ok, Map.put(config, :surprise, true), entities}
  end

  defmodule First do
    def lower_agent(config, entities), do: {:ok, Map.put(config, :order, [:first]), entities}
  end

  defmodule Second do
    def lower_agent(%{order: [:first]} = config, []),
      do: {:ok, %{config | order: [:first, :second]}, []}
  end

  defmodule InvalidResult do
    def lower_agent(_, _), do: :invalid
  end

  defmodule Reject do
    def lower_agent(_, _), do: Jido.Agent.Authoring.error("Extension rejection")
  end

  defmodule InvalidRoutes do
    use Spark.Dsl.Extension
    def lower_agent(config, entities), do: {:ok, %{config | routes: :invalid}, entities}
  end

  defmodule Add do
    use Jido.Action, name: "extension_add", schema: Zoi.object(%{amount: Zoi.integer()})
    def run(%{amount: n}, %{agent_state: state}), do: {:ok, %{state | count: state.count + n}}
  end

  defmodule Turns do
    use Jido.Plugin
    def state_spec(_), do: {:turns, Zoi.integer() |> Zoi.default(0)}
    def update_state(n, _, _), do: {:ok, n + 1}
  end

  test "foreign entities lower with ordinary Plugins, routes and generated helpers", %{jido: jido} do
    module = Module.concat(__MODULE__, "Agent#{System.unique_integer([:positive])}")

    compile_isolated(
      quote do
        defmodule unquote(module) do
          use Jido.Agent, name: "extended_agent", extensions: [Labels]

          agent do
            schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
            label(:owner, "consumer")
            plugin Turns
          end

          routes do
            signal_source "/extension"

            route "add", %Ref{target: Add} do
              define :add, args: [:amount]
            end

            route "ordinary", Add
            route "extension_target", ref: Add
            route "extension_target_defaults", ref: Add, defaults: %{amount: 1}
          end
        end
      end
    )

    definition = module.agent()
    assert definition.metadata == %{owner: "consumer"}
    assert [{Turns, []}] = definition.plugins
    assert Enum.count(definition.routes, &(&1.target == Add)) == 3
    assert Enum.any?(definition.routes, &(&1.target == {Add, %{amount: 1}}))
    {:ok, server} = Jido.start_agent(jido, module)
    assert {:ok, %{state: %{count: 3, turns: 1}}} = module.add(server, 3)
    assert {:ok, document, registry} = Jido.Agent.Codec.encode(definition)
    assert {:ok, ^definition} = Jido.Agent.Codec.decode(document, registry)
  end

  test "extension route target options must be declared and unambiguous" do
    assert_raise CompileError, ~r/Unknown Agent extension route target option :unknown/, fn ->
      compile_isolated(
        quote do
          defmodule unquote(
                      Module.concat(
                        __MODULE__,
                        "UnknownRouteTarget#{System.unique_integer([:positive])}"
                      )
                    ) do
            use Jido.Agent, name: "unknown_route_target", extensions: [Labels]

            routes do
              route "unknown", unknown: Add
            end
          end
        end
      )
    end

    assert {:error, error} =
             Jido.Agent.Extension.route_target_extension([Labels, ConflictingRouteTarget], :ref)

    assert Exception.message(error) == "Conflicting Agent extension route target option :ref"

    assert {:error, error} =
             Jido.Agent.Extension.route_target_extension([InvalidRouteTargetOptions], :ref)

    assert Exception.message(error) ==
             "Agent extension route_target_options/0 must return unique atom names"

    assert {:error, error} = Jido.Agent.Extension.route_target_extension(:invalid, :ref)
    assert Exception.message(error) == "Invalid Agent extension route target option"
  end

  test "a route has only one module or extension target" do
    for routes <- [
          quote(do: route("mixed", Add, ref: Add)),
          quote(do: route("multiple", ref: Add, other: Add))
        ] do
      assert_raise CompileError,
                   ~r/route requires exactly one target module or extension target option/,
                   fn ->
                     compile_isolated(
                       quote do
                         defmodule unquote(
                                     Module.concat(
                                       __MODULE__,
                                       "InvalidRouteTarget#{System.unique_integer([:positive])}"
                                     )
                                   ) do
                           use Jido.Agent, name: "invalid_route_target", extensions: [Labels]

                           routes do
                             unquote(routes)
                           end
                         end
                       end
                     )
                   end
    end
  end

  test "unclaimed declarations fail at compilation" do
    assert_raise CompileError, ~r/Unclaimed Agent extension entities/, fn ->
      compile_isolated(
        quote do
          defmodule unquote(
                      Module.concat(
                        __MODULE__,
                        "UnclaimedAgent#{System.unique_integer([:positive])}"
                      )
                    ) do
            use Jido.Agent, name: "unclaimed", extensions: [Unclaimed]

            agent do
              label(:owner, "consumer")
            end
          end
        end
      )
    end
  end

  test "extension output still passes the common Agent validation" do
    assert_raise CompileError, ~r/Unknown/, fn ->
      compile_isolated(
        quote do
          defmodule unquote(
                      Module.concat(
                        __MODULE__,
                        "InvalidAgent#{System.unique_integer([:positive])}"
                      )
                    ) do
            use Jido.Agent, name: "invalid", extensions: [BadConfig]
          end
        end
      )
    end
  end

  test "extensions execute in declared order through the shared data contract" do
    assert {:ok, %{order: [:first, :second]}} =
             Jido.Agent.Extension.lower([First, Second], %{}, [])

    assert {:ok, %{}} = Jido.Agent.Extension.lower([], %{}, [])
  end

  test "duplicate, absent and invalid extension contracts return structured errors" do
    for extensions <- [[First, First], [String], [nil], [InvalidResult], :invalid] do
      assert {:error, error} = Jido.Agent.Extension.lower(extensions, %{}, [])
      assert is_exception(error)
    end

    assert {:error, error} = Jido.Agent.Extension.lower([Reject], %{}, [])
    assert Exception.message(error) == "Extension rejection"
    assert {:error, error} = Jido.Agent.Extension.lower([], %{}, [%Label{key: :x}])
    assert Exception.message(error) == "Unclaimed Agent extension entities"
  end

  test "invalid lowered routes use compile diagnostics" do
    assert_raise CompileError, ~r/Agent routes must be a list/, fn ->
      compile_isolated(
        quote do
          defmodule unquote(
                      Module.concat(
                        __MODULE__,
                        "InvalidRoutes#{System.unique_integer([:positive])}"
                      )
                    ) do
            use Jido.Agent, name: "invalid_routes", extensions: [InvalidRoutes]
          end
        end
      )
    end
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
        flunk("Agent compilation did not finish")
    end
  end
end
