defmodule Jido.Flow.InlineTest.Host do
  @moduledoc false

  defmacro __using__(_options) do
    quote do
      use Jido.Flow.Inline
      import Jido.Flow.InlineTest.Host, only: [define: 3]
    end
  end

  defmacro define(path, options, do: body) do
    compiled = Jido.Flow.Inline.compile!(path, options, body, __CALLER__)

    quote do
      unquote(compiled.declaration_ast)
      unquote(compiled.target_ast)
    end
  end
end

defmodule Jido.Flow.InlineTest.LateHook do
  @moduledoc false

  defmacro __before_compile__(_caller) do
    quote do
      @late_target (define([host: Jido.Flow.InlineTest.Host, declaration: "late", role: :flow],
                      name: "late_inline_flow"
                    ) do
                      step "increment",
                        action: JidoActionTest.Fixtures.Actions.Add,
                        params: %{value: input(:value), amount: 1}

                      output result("increment")
                    end)

      def late_target, do: @late_target
    end
  end
end

defmodule Jido.Flow.InlineTest.LateOwner do
  @moduledoc false
  use Jido.Flow.InlineTest.Host
  @before_compile Jido.Flow.InlineTest.LateHook
end

defmodule Jido.Flow.InlineTest.Extension do
  @moduledoc false
  use Jido.Flow.Extension

  defmacro add(name, value, amount) do
    quote do
      step unquote(name),
        action: JidoActionTest.Fixtures.Actions.Add,
        params: %{value: unquote(value), amount: unquote(amount)}
    end
  end
end

defmodule Jido.Flow.InlineTest.BlockingAction do
  @moduledoc false
  use Jido.Action, name: "inline_flow_blocking_action"

  @impl true
  def run(_params, %{observer: observer}) do
    send(observer, {:inline_flow_blocking, self()})

    receive do
      :release -> {:ok, %{version: :old}}
    end
  end
end

defmodule Jido.Flow.InlineTest.Owner do
  @moduledoc false
  require Jido.Flow.InlineTest.Host

  @path [host: Jido.Flow.InlineTest.Host, declaration: "math", role: :flow]

  @target (Jido.Flow.InlineTest.Host.define @path,
             id: "tests/flows/inline-math",
             name: "inline_math",
             description: "An embedded math Flow",
             extensions: [Jido.Flow.InlineTest.Extension] do
             add("increment", input(:value), 1)

             step "double", value <- result("increment", :value) do
               {:ok, %{value: value * 2}}
             end

             output result("double")
           end)

  def path, do: @path
  def target, do: @target
end

defmodule Jido.Flow.InlineTest do
  use Covenant.Case, component: "jido_action.inline_flow", async: false

  alias Jido.Flow.Inline
  alias Jido.Flow.InlineTest.{LateOwner, Owner}

  setup do
    loaded = MapSet.new(:code.all_loaded(), &elem(&1, 0))

    on_exit(fn ->
      for {module, _} <- :code.all_loaded(),
          not MapSet.member?(loaded, module),
          String.starts_with?(Atom.to_string(module), [
            "Elixir.Jido.Flow.InlineTest.",
            "Elixir.Jido.Flow.Generated.Inline."
          ]) do
        :code.purge(module)
        :code.delete(module)
      end
    end)
  end

  @tag obligation: ["jido_action.inline_flow.I1", "jido_action.inline_flow.I2"]
  test "a host compiles an embedded body as one normal Flow module" do
    target = Owner.target()

    assert target == Inline.target!(Owner, Owner.path())
    assert target.__jido_inline_flow__() == {Owner, Owner.path()}
    assert target.__jido_authoring_kind__() == :flow
    assert target.name() == "inline_math"
    assert target.description() == "An embedded math Flow"
    assert target.flow().name == "inline_math"
    assert {:ok, %{value: 8}} = Jido.Exec.run(target, %{value: 3})

    assert action = target.step_action("double")
    assert action.__jido_authoring_kind__() == :action
  end

  @tag obligation: "jido_action.inline_flow.I3"
  test "the owner rejects a duplicate inline Flow identity" do
    owner = unique_owner("Duplicate")
    path = [host: Jido.Flow.InlineTest.Host, declaration: "same", role: :flow]

    source = """
    defmodule #{inspect(owner)} do
      require Jido.Flow.InlineTest.Host

      Jido.Flow.InlineTest.Host.define #{inspect(path)}, [name: "first"] do
        step "first",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: 1, amount: 1}

        output result("first")
      end

      Jido.Flow.InlineTest.Host.define #{inspect(path)}, [name: "second"] do
        step "second",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: 1, amount: 1}

        output result("second")
      end
    end
    """

    assert_raise CompileError, ~r/duplicate inline Flow identity/, fn ->
      Code.compile_string(source, "duplicate_inline_flow.ex")
    end

    purge([owner, generated_target(owner, path)])
  end

  @tag obligation: "jido_action.inline_flow.I2"
  test "an owner index includes a Flow emitted by a late compile hook" do
    path = [host: Jido.Flow.InlineTest.Host, declaration: "late", role: :flow]

    assert LateOwner.late_target() == Inline.target!(LateOwner, path)
    assert {:ok, %{value: 4}} = Jido.Exec.run(LateOwner.late_target(), %{value: 3})
  end

  @tag obligation: "jido_action.inline_flow.I1"
  test "the normal Flow compiler reports an invalid embedded body at its source" do
    owner = unique_owner("Invalid")
    path = [host: Jido.Flow.InlineTest.Host, declaration: "invalid", role: :flow]

    source = """
    defmodule #{inspect(owner)} do
      require Jido.Flow.InlineTest.Host

      Jido.Flow.InlineTest.Host.define #{inspect(path)}, [name: "invalid"] do
        step "increment",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: input(:value), amount: 1}

        output result("missing")
      end
    end
    """

    error =
      assert_raise CompileError, ~r/reference points to an unknown component/, fn ->
        Code.compile_string(source, "invalid_inline_flow.ex")
      end

    assert error.file == "invalid_inline_flow.ex"
    assert error.line == 9
    purge([owner, generated_target(owner, path)])
  end

  @tag obligation: "jido_action.inline_flow.I3"
  test "lookup rejects an unknown or malformed identity" do
    assert_raise ArgumentError, ~r/unknown inline Flow identity/, fn ->
      Inline.target!(Owner, host: Jido.Flow.InlineTest.Host, declaration: "missing", role: :flow)
    end

    assert_raise ArgumentError, ~r/unknown inline Flow identity/, fn ->
      Inline.target!(Owner, host: Jido.Flow.InlineTest.Host, declaration: "math", role: :action)
    end
  end

  @tag obligation: "jido_action.inline_flow.I1"
  test "path and Flow options evaluate once in owner scope" do
    owner = unique_owner("Options")
    path = path("options")
    key = {owner, :option_evaluations}

    source = """
    defmodule #{inspect(owner)} do
      require Jido.Flow.InlineTest.Host

      @flow_name "owner_scoped_flow"
      @schema Zoi.object(%{value: Zoi.integer()})
      @output_schema Zoi.object(%{value: Zoi.integer()})

      @target (Jido.Flow.InlineTest.Host.define(
        (Process.put(#{inspect(key)}, Process.get(#{inspect(key)}, 0) + 1); #{inspect(path)}),
        name: (Process.put(#{inspect(key)}, Process.get(#{inspect(key)}, 0) + 1); @flow_name),
        schema: @schema,
        output_schema: @output_schema
      ) do
        step "increment",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: input(:value), amount: 1}

        output result("increment")
      end)

      def target, do: @target
    end
    """

    Code.compile_string(source, "inline_flow_options.ex")

    assert Process.get(key) == 2
    assert owner.target().name() == "owner_scoped_flow"
    assert owner.target().schema().fields == Zoi.object(%{value: Zoi.integer()}).fields
    assert owner.target().output_schema().fields == Zoi.object(%{value: Zoi.integer()}).fields
    assert {:ok, %{value: 5}} = Jido.Exec.run(owner.target(), %{value: 4})

    assert {:error, %Jido.Action.Error.InvalidInputError{}} =
             Jido.Exec.run(owner.target(), %{value: "bad"})

    Process.delete(key)
  end

  @tag obligation: "jido_action.inline_flow.I1"
  test "the generated Flow body does not capture owner functions or attributes" do
    owner = unique_owner("Scope")
    declaration_path = path("scope")

    source = """
    defmodule #{inspect(owner)} do
      require Jido.Flow.InlineTest.Host

      Jido.Flow.InlineTest.Host.define #{inspect(declaration_path)}, [name: "scope"] do
        step "owner_step",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: helper(), amount: 1}

        output result("owner_step")
      end

      defp helper, do: 1
    end
    """

    error =
      assert_raise CompileError, fn ->
        Code.compile_string(source, "inline_flow_scope.ex")
      end

    assert error.file == "inline_flow_scope.ex"
    assert error.description =~ "unsupported Flow expression"
    assert error.description =~ "helper()"
    refute Code.ensure_loaded?(generated_target(owner, declaration_path))

    attribute_owner = unique_owner("AttributeScope")
    attribute_path = path("attribute_scope")

    attribute_source = """
    defmodule #{inspect(attribute_owner)} do
      require Jido.Flow.InlineTest.Host
      @step_name "owner_step"

      Jido.Flow.InlineTest.Host.define #{inspect(attribute_path)}, [name: "scope"] do
        step @step_name,
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: 1, amount: 1}

        output result(@step_name)
      end
    end
    """

    warning =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        attribute_error =
          assert_raise CompileError, fn ->
            Code.compile_string(attribute_source, "inline_flow_attribute_scope.ex")
          end

        assert attribute_error.file == "inline_flow_attribute_scope.ex"
        assert attribute_error.description == "Action name must be a string."
      end)

    assert warning =~ "undefined module attribute @step_name"
    refute Code.ensure_loaded?(generated_target(attribute_owner, attribute_path))
  end

  @tag obligation: "jido_action.inline_flow.I2"
  test "repeated setup installs one hook pair and preserves all declarations" do
    owner = unique_owner("RepeatedSetup")
    first = path("first")
    second = path("second")

    source = """
    defmodule #{inspect(owner)} do
      use Jido.Flow.Inline
      use Jido.Flow.Inline
      :ok = Jido.Flow.Inline.setup!(__ENV__)
      require Jido.Flow.InlineTest.Host

      @first (Jido.Flow.InlineTest.Host.define #{inspect(first)}, [name: "first"] do
        step "first",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: 0, amount: 1}

        output result("first")
      end)

      @second (Jido.Flow.InlineTest.Host.define #{inspect(second)}, [name: "second"] do
        step "second",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: 0, amount: 2}

        output result("second")
      end)

      @hook_counts {
        Enum.count(Module.get_attribute(__MODULE__, :on_definition), fn
          {Jido.Flow.Inline.Owner, _} -> true
          _ -> false
        end),
        Enum.count(Module.get_attribute(__MODULE__, :before_compile), fn
          Jido.Flow.Inline.Owner -> true
          {Jido.Flow.Inline.Owner, _} -> true
          _ -> false
        end)
      }

      def targets, do: {@first, @second}
      def hook_counts, do: @hook_counts
    end
    """

    Code.compile_string(source, "inline_flow_repeated_setup.ex")

    assert owner.hook_counts() == {1, 1}
    assert owner.targets() == {Inline.target!(owner, first), Inline.target!(owner, second)}
  end

  @tag obligation: "jido_action.inline_flow.I2"
  test "the reserved lookup rejects clauses before or after setup and default arguments" do
    definitions = [
      "def __jido_inline_flows__, do: %{}\n  use Jido.Flow.Inline",
      "use Jido.Flow.Inline\n  def __jido_inline_flows__, do: %{}",
      "use Jido.Flow.Inline\n  def __jido_inline_flows__(_value \\\\ nil), do: %{}"
    ]

    for definition <- definitions do
      owner = unique_owner("Reserved")

      source = """
      defmodule #{inspect(owner)} do
        #{definition}
      end
      """

      error =
        assert_raise CompileError, fn ->
          Code.compile_string(source, "inline_flow_reserved.ex")
        end

      assert error.file == "inline_flow_reserved.ex"

      assert error.description ==
               "reserved inline Flow function __jido_inline_flows__/0 cannot have user clauses"
    end
  end

  @tag obligation: "jido_action.inline_flow.I2"
  test "a failed replacement preserves the loaded target and a corrected retry replaces it" do
    owner = unique_owner("Replacement")
    declaration_path = path("replacement")

    compile_owner(owner, declaration_path, "first", 1)
    target = owner.target()
    assert {:ok, %{value: 2}} = Jido.Exec.run(target, %{})

    invalid = owner_source(owner, declaration_path, 123, 5, ~s|output result("increment")|)

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert_raise CompileError, ~r/flow name must be a string/, fn ->
        Code.compile_string(invalid, "inline_flow_invalid_replacement.ex")
      end
    end)

    assert target.name() == "first"
    assert {:ok, %{value: 2}} = Jido.Exec.run(target, %{})

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      compile_owner(owner, declaration_path, "corrected", 2)
    end)

    assert owner.target() == target
    assert target.name() == "corrected"
    assert {:ok, %{value: 3}} = Jido.Exec.run(target, %{})

    invalid_body =
      owner_source(owner, declaration_path, "invalid_body", 5, ~s|output result("missing")|)

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert_raise CompileError, ~r/reference points to an unknown component/, fn ->
        Code.compile_string(invalid_body, "inline_flow_invalid_body_replacement.ex")
      end
    end)

    refute Code.ensure_loaded?(target)

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      compile_owner(owner, declaration_path, "recovered", 3)
    end)

    assert owner.target() == target
    assert target.name() == "recovered"
    assert {:ok, %{value: 4}} = Jido.Exec.run(target, %{})
  end

  @tag obligation: "jido_action.inline_flow.I2"
  test "recompilation keeps a process that already runs the old Flow alive" do
    owner = unique_owner("LiveReplacement")
    declaration_path = path("live_replacement")
    observer = self()

    source = """
    defmodule #{inspect(owner)} do
      require Jido.Flow.InlineTest.Host

      @target (Jido.Flow.InlineTest.Host.define #{inspect(declaration_path)}, [name: "old"] do
        step "work", action: Jido.Flow.InlineTest.BlockingAction, params: %{}
        output result("work")
      end)

      def target, do: @target
    end
    """

    Code.compile_string(source, "inline_flow_live_replacement.ex")
    target = owner.target()
    task = Task.async(fn -> Jido.Exec.run(target, %{}, %{observer: observer}) end)
    assert_receive {:inline_flow_blocking, action_pid}, 1_000

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      compile_owner(owner, declaration_path, "new", 2)
    end)

    assert Process.alive?(task.pid)
    send(action_pid, :release)
    assert Task.await(task) == {:ok, %{version: :old}}
    assert owner.target() == target
    assert target.name() == "new"
    assert {:ok, %{value: 3}} = Jido.Exec.run(target, %{})
  end

  @tag obligation: "jido_action.inline_flow.I3"
  test "typed paths reject every value outside the declared grammar" do
    host = Jido.Flow.InlineTest.Host

    invalid_paths = [
      [],
      [host: host, role: :flow],
      [owner: host, declaration: "bad", role: :flow],
      [host: host, declaration: "bad", role: :action],
      [{"host", host}, {:declaration, "bad"}, {:role, :flow}],
      [{:host, host}, {nil, "bad"}, {:role, :flow}],
      [host: nil, declaration: "bad", role: :flow],
      [host: host, declaration: 1.5, role: :flow],
      [{:host, host}, {:declaration, "bad"}, {:role, :flow} | :tail]
    ]

    for invalid_path <- invalid_paths do
      owner = unique_owner("InvalidPath")

      source = """
      defmodule #{inspect(owner)} do
        require Jido.Flow.InlineTest.Host

        Jido.Flow.InlineTest.Host.define #{inspect(invalid_path)}, [name: "bad"] do
          output %{}
        end
      end
      """

      error =
        assert_raise CompileError, fn ->
          Code.compile_string(source, "inline_flow_invalid_path.ex")
        end

      assert error.file == "inline_flow_invalid_path.ex"
      assert error.line == 4
      assert error.description =~ "inline Flow identity must have at least three typed segments"
      refute Code.ensure_loaded?(generated_target(owner, invalid_path))
    end
  end

  @tag obligation: "jido_action.inline_flow.I3"
  test "identity uses the owner and complete path, not Flow metadata" do
    paths = [
      [host: Jido.Flow.InlineTest.Host, group: "one", operation: "same", role: :flow],
      [host: Jido.Flow.InlineTest.Host, group: "two", operation: "same", role: :flow],
      [host: Jido.Flow.InlineTest.Host, declaration: "1", role: :flow],
      [host: Jido.Flow.InlineTest.Host, declaration: 1, role: :flow],
      [host: Jido.Flow.InlineTest.Host, declaration: :"1", role: :flow]
    ]

    owners = [unique_owner("IdentityA"), unique_owner("IdentityB")]

    for owner <- owners do
      declarations =
        Enum.map_join(paths, "\n", fn declaration_path ->
          """
          Jido.Flow.InlineTest.Host.define #{inspect(declaration_path)}, [name: "shared"] do
            step "work",
              action: JidoActionTest.Fixtures.Actions.Add,
              params: %{value: 0, amount: 1}

            output result("work")
          end
          """
        end)

      Code.compile_string("""
      defmodule #{inspect(owner)} do
        require Jido.Flow.InlineTest.Host
        #{declarations}
      end
      """)
    end

    targets =
      for owner <- owners, declaration_path <- paths, do: Inline.target!(owner, declaration_path)

    assert length(Enum.uniq(targets)) == length(owners) * length(paths)
    assert Enum.all?(targets, &(&1.name() == "shared"))
  end

  @tag obligation: "jido_action.inline_flow.I3"
  test "a false branch emits no target or index entry" do
    owner = unique_owner("FalseBranch")
    skipped = path("skipped")

    source = """
    defmodule #{inspect(owner)} do
      use Jido.Flow.Inline
      require Jido.Flow.InlineTest.Host

      if false do
        Jido.Flow.InlineTest.Host.define #{inspect(skipped)}, [name: "skipped"] do
          output %{}
        end
      end
    end
    """

    Code.compile_string(source, "inline_flow_false_branch.ex")

    assert owner.__jido_inline_flows__() == %{}
    assert_raise ArgumentError, fn -> Inline.target!(owner, skipped) end
    refute Code.ensure_loaded?(generated_target(owner, skipped))
  end

  @tag obligation: "jido_action.inline_flow.I3"
  test "a foreign generated module fails before replacement" do
    owner = unique_owner("Foreign")
    declaration_path = path("foreign")
    target = generated_target(owner, declaration_path)

    Module.create(
      target,
      quote do
        def __jido_inline_flow__, do: :foreign
        def untouched, do: :foreign
      end,
      __ENV__
    )

    assert_raise CompileError, ~r/generated inline Flow module.*already belongs/, fn ->
      compile_owner(owner, declaration_path, "foreign", 1)
    end

    assert target.untouched() == :foreign

    for marker <- [:raise, :throw] do
      purge([target])

      marker_definition =
        case marker do
          :raise -> quote(do: def(__jido_inline_flow__(), do: raise("foreign marker")))
          :throw -> quote(do: def(__jido_inline_flow__(), do: throw(:foreign_marker)))
        end

      Module.create(target, marker_definition, __ENV__)

      assert_raise CompileError, ~r/generated inline Flow module.*already belongs/, fn ->
        compile_owner(owner, declaration_path, "foreign", 1)
      end
    end
  end

  @tag obligation: "jido_action.inline_flow.I3"
  test "lookup is inert and unknown string paths do not create atoms" do
    names = for i <- 1..50, do: "missing_#{i}_#{System.unique_integer([:positive])}"

    lookup = fn ->
      for name <- names do
        missing = [host: Jido.Flow.InlineTest.Host, declaration: name, role: :flow]
        assert_raise ArgumentError, fn -> Inline.target!(Owner, missing) end
      end
    end

    for name <- names, do: assert_raise(ArgumentError, fn -> String.to_existing_atom(name) end)
    for _ <- 1..3, do: lookup.()
    for name <- names, do: assert_raise(ArgumentError, fn -> String.to_existing_atom(name) end)

    owner = unique_owner("Lookup")
    known = path("known")

    source = """
    defmodule #{inspect(owner)} do
      require Jido.Flow.InlineTest.Host

      @target (Jido.Flow.InlineTest.Host.define #{inspect(known)}, [name: "known"] do
        step "work", [], inline: [context: ctx] do
          send(ctx.observer, :inline_flow_work)
          {:ok, %{worked: true}}
        end

        output result("work")
      end)

      def target, do: @target
    end
    """

    Code.compile_string(source, "inline_flow_lookup.ex")
    assert Inline.target!(owner, known) == owner.target()
    refute_received :inline_flow_work

    assert {:ok, %{worked: true}} = Jido.Exec.run(owner.target(), %{}, %{observer: self()})
    assert_received :inline_flow_work
  end

  @tag obligation: "jido_action.inline_flow.I3"
  test "compilation requires an open owner and lookup requires a completed owner" do
    assert_raise CompileError, ~r/requires a compiling owner/, fn ->
      Inline.compile!(
        Macro.escape(path("outside")),
        [name: "outside"],
        quote(do: output(%{})),
        __ENV__
      )
    end

    assert_raise CompileError, ~r/requires a compiling owner/, fn -> Inline.setup!(__ENV__) end

    function_owner = unique_owner("FunctionScope")
    function_path = path("function_scope")

    function_source = """
    defmodule #{inspect(function_owner)} do
      require Jido.Flow.InlineTest.Host

      def invalid do
        Jido.Flow.InlineTest.Host.define #{inspect(function_path)}, [name: "invalid"] do
          output %{}
        end
      end
    end
    """

    function_error =
      assert_raise CompileError, fn ->
        Code.compile_string(function_source, "inline_flow_function_scope.ex")
      end

    assert function_error.file == "inline_flow_function_scope.ex"

    assert function_error.description ==
             "inline Flow compilation requires a compiling owner module"

    refute Code.ensure_loaded?(generated_target(function_owner, function_path))

    owner = unique_owner("OpenLookup")
    missing = path("missing")

    source = """
    defmodule #{inspect(owner)} do
      use Jido.Flow.Inline
      Jido.Flow.Inline.target!(__MODULE__, #{inspect(missing)})
    end
    """

    assert_raise ArgumentError, ~r/only after the owner compiles/, fn ->
      Code.compile_string(source, "inline_flow_open_lookup.ex")
    end
  end

  @tag obligation: "jido_action.inline_flow.I3"
  test "lookup rejects foreign owner indexes and non-module owners" do
    declaration_path = path("foreign_index")
    foreign = unique_owner("ForeignIndex")
    non_map = unique_owner("NonMapIndex")
    raising_index = unique_owner("RaisingIndex")
    throwing_index = unique_owner("ThrowingIndex")
    missing_target_owner = unique_owner("MissingTargetIndex")
    non_module_target_owner = unique_owner("NonModuleTargetIndex")
    raising_target_owner = unique_owner("RaisingTargetIndex")
    throwing_target_owner = unique_owner("ThrowingTargetIndex")
    missing_target = unique_owner("MissingTarget")
    raising_target = unique_owner("RaisingTarget")
    throwing_target = unique_owner("ThrowingTarget")

    Module.create(
      foreign,
      quote do
        def __jido_inline_flows__, do: %{unquote(Macro.escape(declaration_path)) => String}
      end,
      __ENV__
    )

    Module.create(non_map, quote(do: def(__jido_inline_flows__(), do: [])), __ENV__)

    Module.create(
      raising_index,
      quote(do: def(__jido_inline_flows__(), do: raise("invalid index"))),
      __ENV__
    )

    Module.create(
      throwing_index,
      quote(do: def(__jido_inline_flows__(), do: throw(:invalid_index))),
      __ENV__
    )

    for {owner, target} <- [
          {missing_target_owner, missing_target},
          {non_module_target_owner, "not a module"},
          {raising_target_owner, raising_target},
          {throwing_target_owner, throwing_target}
        ] do
      Module.create(
        owner,
        quote do
          def __jido_inline_flows__,
            do: %{unquote(Macro.escape(declaration_path)) => unquote(target)}
        end,
        __ENV__
      )
    end

    Module.create(
      raising_target,
      quote(do: def(__jido_inline_flow__(), do: raise("invalid target"))),
      __ENV__
    )

    Module.create(
      throwing_target,
      quote(do: def(__jido_inline_flow__(), do: throw(:invalid_target))),
      __ENV__
    )

    owners = [
      foreign,
      non_map,
      raising_index,
      throwing_index,
      missing_target_owner,
      non_module_target_owner,
      raising_target_owner,
      throwing_target_owner,
      nil,
      "Owner",
      %{},
      42
    ]

    for owner <- owners do
      error = assert_raise ArgumentError, fn -> Inline.target!(owner, declaration_path) end

      assert error.message ==
               "unknown inline Flow identity in #{inspect(owner)}: #{inspect(declaration_path)}"
    end
  end

  defp unique_owner(label) do
    Module.concat(__MODULE__, "#{label}#{System.unique_integer([:positive])}")
  end

  defp path(name) do
    [host: Jido.Flow.InlineTest.Host, declaration: name, role: :flow]
  end

  defp compile_owner(owner, declaration_path, name, amount) do
    source = owner_source(owner, declaration_path, name, amount, ~s|output result("increment")|)
    Code.compile_string(source, "inline_flow_owner.ex")
    owner
  end

  defp owner_source(owner, declaration_path, name, amount, output) do
    """
    defmodule #{inspect(owner)} do
      require Jido.Flow.InlineTest.Host

      @target (Jido.Flow.InlineTest.Host.define #{inspect(declaration_path)}, [name: #{inspect(name)}] do
        step "increment",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: 1, amount: #{amount}}

        #{output}
      end)

      def target, do: @target
    end
    """
  end

  defp generated_target(owner, path) do
    digest =
      :crypto.hash(:sha256, :erlang.term_to_binary({owner, path}))
      |> Base.encode16(case: :lower)

    Module.concat(Jido.Flow.Generated.Inline, "F" <> digest)
  end

  defp purge(modules) do
    for module <- modules do
      :code.purge(module)
      :code.delete(module)
    end
  end
end
