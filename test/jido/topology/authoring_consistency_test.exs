defmodule JidoTest.Topology.AuthoringConsistencyTest do
  use ExUnit.Case, async: false

  alias Jido.Topology

  defmodule Member do
    use Jido.Agent, name: "consistency_member"
  end

  defmodule Label do
    defstruct [:value, :__spark_metadata__]
  end

  defmodule LabelValues do
    def label_value, do: :imported

    def extension(module) do
      send(Process.get(:authoring_test_owner), {:extension_evaluated, module})
      module
    end

    defmacro extension_macro(module) do
      send(Process.get(:authoring_test_owner), {:extension_evaluated, __MODULE__})
      module
    end
  end

  defmodule Labels do
    @label %Spark.Dsl.Entity{
      name: :label,
      target: Label,
      args: [:value],
      schema: [value: [type: :any, required: true]]
    }
    use Spark.Dsl.Extension,
      imports: [LabelValues],
      dsl_patches: [%Spark.Dsl.Patch.AddEntity{section_path: [:agent], entity: @label}]

    def lower_agent(config, entities) do
      {labels, rest} = Enum.split_with(entities, &is_struct(&1, Label))
      metadata = Enum.reduce(labels, config.metadata, &Map.put(&2, :label, &1.value))
      {:ok, %{config | metadata: metadata}, rest}
    end

    def lower_topology(config, entities), do: {:ok, config, entities}
  end

  defmodule RootLabels do
    @label %Spark.Dsl.Entity{
      name: :label,
      target: Label,
      args: [:value],
      schema: [value: [type: :any, required: true]]
    }

    use Spark.Dsl.Extension,
      imports: [LabelValues],
      sections: [%Spark.Dsl.Section{name: :labels, entities: [@label]}]

    def lower_topology(config, entities) do
      {labels, rest} = Enum.split_with(entities, &is_struct(&1, Label))
      metadata = Enum.reduce(labels, config.metadata, &Map.put(&2, :label, &1.value))
      {:ok, %{config | metadata: metadata}, rest}
    end
  end

  defmodule TopologyLabels do
    @label %Spark.Dsl.Entity{
      name: :label,
      target: Label,
      args: [:value],
      schema: [value: [type: :any, required: true]]
    }
    use Spark.Dsl.Extension,
      dsl_patches: [
        %Spark.Dsl.Patch.AddEntity{section_path: [:topology, :resources], entity: @label}
      ]

    def lower_topology(config, entities) do
      {labels, rest} = Enum.split_with(entities, &is_struct(&1, Label))
      metadata = Enum.reduce(labels, config.metadata, &Map.put(&2, :label, &1.value))
      {:ok, %{config | metadata: metadata}, rest}
    end
  end

  test "both hosts evaluate computed extensions once in each option form" do
    for host <- [Jido.Agent, Jido.Topology], form <- [:keyword, :map, :expression, :attribute] do
      module = unique_module()

      options =
        if form == :map,
          do: "%{name: \"consistent\", extensions: [#{LabelValues}.extension(#{Labels})]}",
          else: "[name: \"consistent\", extensions: [#{LabelValues}.extension(#{Labels})]]"

      setup =
        case form do
          :attribute -> "@options #{options}\nuse #{host}, @options"
          :expression -> "use #{host}, List.wrap(#{options})"
          _ -> "use #{host}, #{options}"
        end

      compile("""
      defmodule #{module} do
        #{setup}
        agent do
          label label_value()
        end
      end
      """)

      assert module.definition().metadata == %{label: :imported}
      assert_received {:extension_evaluated, Labels}
      refute_received {:extension_evaluated, Labels}
    end
  end

  test "computed extension macros run once in the evaluated options" do
    for host <- [Jido.Agent, Jido.Topology] do
      module = unique_module()

      compile("""
      defmodule #{module} do
        require #{LabelValues}
        use #{host}, name: "macro", extensions: [#{LabelValues}.extension_macro(#{Labels})]
        agent do
          label label_value()
        end
      end
      """)

      assert module.definition().metadata == %{label: :imported}
      assert_received {:extension_evaluated, LabelValues}
      refute_received {:extension_evaluated, LabelValues}
    end
  end

  for host <- [Jido.Agent, Jido.Topology],
      form <- [:keyword, :map, :attribute, :attribute_map, :extension_attribute] do
    test "#{inspect(host)} registers extensions from #{form} options once" do
      host = unquote(host)
      form = unquote(form)
      module = unique_module()
      setup = option_setup(host, form)

      compile("""
      defmodule #{module} do
        #{setup}
        agent do
          label :kept
        end
        #{topology_body(host)}
      end
      """)

      assert module.definition().metadata == %{label: :kept}
      assert module.definition().name == "consistent"
      assert_host(module, host)
    end
  end

  test "root blocks retain caller variables and aliases" do
    module = unique_module()

    compile("""
    defmodule #{module} do
      alias #{Member}, as: Worker
      count = 2
      labels = %{owner: :caller}
      use Jido.Topology, name: "caller_scope"
      agent do
        metadata labels
      end
      topology do
        agents do
          group :workers, Worker, count: count
        end
      end
    end
    """)

    assert module.definition().metadata == %{owner: :caller}
    assert [%{count: 2, module: Member}] = module.topology().groups
  end

  test "deferred blocks retain extension imports from module attribute options" do
    module = unique_module()

    compile("""
    defmodule #{module} do
      @options [name: "imports", extensions: [#{Labels}]]
      use Jido.Agent, @options
      agent do
        label label_value()
      end
    end
    """)

    assert module.definition().metadata == %{label: :imported}
  end

  test "literal extension options retain extension-owned root sections and imports" do
    module = unique_module()

    compile("""
    defmodule #{module} do
      use Jido.Topology, name: "root_imports", extensions: [#{RootLabels}]
      labels do
        label label_value()
      end
    end
    """)

    assert module.topology().metadata == %{label: :imported}
  end

  test "literal root sections remain available beside computed extensions" do
    module = unique_module()

    compile("""
    defmodule #{module} do
      use Jido.Topology, name: "mixed_imports",
        extensions: [#{RootLabels}, #{LabelValues}.extension(#{Labels})]
      labels do
        label label_value()
      end
      agent do
        label label_value()
      end
    end
    """)

    assert module.topology().metadata == %{label: :imported}
    assert module.definition().metadata == %{label: :imported}
    assert_received {:extension_evaluated, Labels}
    refute_received {:extension_evaluated, Labels}
  end

  test "the combined host evaluates its options once" do
    module = unique_module()

    compile("""
    defmodule #{module} do
      use Jido.Topology, (send(Process.get(:authoring_test_owner), :options_evaluated); [name: "once"])
    end
    """)

    assert_received :options_evaluated
    refute_received :options_evaluated
  end

  for {kind, field} <- [agent: :initial_state, group: :initial_state, group: :count] do
    test "#{kind} preserves explicit nil for #{field}" do
      kind = unquote(kind)
      field = unquote(field)
      entry = %{key: :member, module: Member} |> Map.put(field, nil)
      collection = unquote(if kind == :agent, do: :agents, else: :groups)
      assert {:error, direct} = Topology.new(%{collection => [entry], name: "nil"})
      module = unique_module()

      error =
        assert_raise CompileError, fn ->
          compile("""
          defmodule #{module} do
            use Jido.Topology, name: "nil"
            topology do
              agents do
                #{kind} :member, #{Member}, #{field}: nil
              end
            end
          end
          """)
        end

      assert error.description == Exception.message(direct)
      assert direct.details.source_path == [collection, 0, field]
      assert error.line == 5
    end
  end

  test "omitted group fields retain defaults" do
    module = unique_module()

    compile("""
    defmodule #{module} do
      use Jido.Topology, name: "defaults"
      topology do
        agents do
          group :members, #{Member}
        end
      end
    end
    """)

    assert [%{count: 1, initial_state: %{}, depends_on: []}] = module.topology().groups

    assert {:ok, direct} =
             Topology.new(name: "defaults", groups: [%{key: :members, module: Member}])

    assert module.topology() == direct
  end

  test "explicit values cannot impersonate omitted optional fields" do
    for value <- [{Jido.Topology.EntryMetadata, :omitted}, {:present, 1}, false] do
      assert {:error, direct} =
               Topology.new(
                 name: "presence",
                 groups: [%{key: :workers, module: Member, count: value}]
               )

      module = unique_module()

      error =
        assert_raise CompileError, fn ->
          compile("""
          defmodule #{module} do
            use Jido.Topology, name: "presence"
            topology do
              agents do
                group :workers, #{Member}, count: #{inspect(value)}
              end
            end
          end
          """)
        end

      assert error.description == Exception.message(direct)
      assert error.line == 5
    end
  end

  test "an explicit nil optional field is retained without compiler debug metadata" do
    module = unique_module()

    error =
      assert_raise CompileError, fn ->
        compile(
          """
          defmodule #{module} do
            use Jido.Topology, name: "no_debug"
            topology do
              agents do
                group :workers, #{Member}, count: nil
              end
            end
          end
          """,
          debug_info: false
        )
      end

    assert error.description == "Group count must be nonnegative or an input reference"
  end

  test "semantic errors identify the field in the second declaration" do
    module = unique_module()

    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule #{module} do
          use Jido.Topology, name: "located"
          topology do
            agents do
              agent :first, #{Member}
              group :second, #{Member} do
                count -1
              end
            end
          end
        end
        """)
      end

    assert error.line == 7
    assert error.description == "Group count must be nonnegative or an input reference"
  end

  test "duplicate declarations identify the second key" do
    module = unique_module()

    error =
      assert_raise CompileError, fn ->
        compile("""
        defmodule #{module} do
          use Jido.Topology, name: "duplicates"
          topology do
            agents do
              agent :same, #{Member}
              group :same, #{Member}
            end
          end
        end
        """)
      end

    assert error.line == 6
    assert error.description == "Duplicate topology key"
  end

  test "unescapable state values report the declaration file and line" do
    assert {:error, direct} =
             Topology.new(
               name: "runtime",
               agents: [
                 %{key: :worker, module: Member, initial_state: %{callback: fn -> :ok end}}
               ]
             )

    for kind <- [:agent, :group],
        debug_info <- [true, false],
        state <- [
          "%{callback: fn -> :ok end}",
          "%{nested: [fn -> :ok end]}",
          "%{nested: {:callback, fn -> :ok end}}",
          "%{(fn -> :ok end) => :callback}"
        ] do
      module = unique_module()

      error =
        assert_raise CompileError, fn ->
          compile(
            """
            defmodule #{module} do
              use Jido.Topology, name: "runtime"
              topology do
                agents do
                  #{kind} :worker, #{Member} do
                    initial_state #{state}
                  end
                end
              end
            end
            """,
            debug_info: debug_info
          )
        end

      assert error.description == Exception.message(direct)
      assert error.file == "authoring_consistency.ex"
      # Spark omits source annotations when compiler debug metadata is disabled.
      assert error.line == if(debug_info, do: 6, else: 1)
    end
  end

  defmodule InvalidTail do
    def lower_agent(config, _entities), do: {:ok, config, [:entry | :invalid]}
    def lower_topology(config, _entities), do: {:ok, config, [:entry | :invalid]}
  end

  test "both extension hosts reject improper input and callback lists" do
    for host <- [Jido.Agent.Extension, Jido.Topology.Extension] do
      for {extensions, config, entities} <- [
            {[:extension | :invalid], %{}, []},
            {[], %{}, [:entry | :invalid]},
            {[], %URI{}, []},
            {[InvalidTail], %{}, []}
          ] do
        assert {:error, %Jido.Error.ValidationError{}} = host.lower(extensions, config, entities)
      end
    end
  end

  defp unique_module, do: Module.concat(__MODULE__, "Case#{System.unique_integer([:positive])}")

  defp assert_host(module, Jido.Topology) do
    assert module.topology().name == "consistent"
    assert module.topology().metadata == %{label: :topology}
  end

  defp assert_host(_module, Jido.Agent), do: :ok

  defp topology_body(Jido.Agent), do: ""
  defp topology_body(Jido.Topology), do: "topology do\nresources do\nlabel :topology\nend\nend"

  defp option_setup(host, form) do
    extensions = if host == Jido.Topology, do: "#{Labels}, #{TopologyLabels}", else: "#{Labels}"

    options =
      case form do
        form when form in [:map, :attribute_map] ->
          "%{name: \"consistent\", extensions: [#{extensions}]}"

        _ ->
          "[name: \"consistent\", extensions: [#{extensions}]]"
      end

    case form do
      :extension_attribute ->
        "@extensions [#{extensions}]\nuse #{host}, name: \"consistent\", extensions: @extensions"

      form when form in [:attribute, :attribute_map] ->
        "@options #{options}\nuse #{host}, @options"

      _ ->
        "use #{host}, #{options}"
    end
  end

  defp compile(source, options \\ [debug_info: true]) do
    owner = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Process.put(:authoring_test_owner, owner)
        previous = Code.compiler_options(options)

        result =
          try do
            Code.compile_string(source, "authoring_consistency.ex")
          after
            Code.compiler_options(previous)
          end

        send(owner, {self(), :compiled, result})
      end)

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
        flunk("Authoring compilation did not finish")
    end
  end
end
