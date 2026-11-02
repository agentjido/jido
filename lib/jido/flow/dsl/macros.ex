defmodule Jido.Flow.DSL.MacroSupport do
  @moduledoc false

  alias Jido.Authoring.Options

  @doc false
  @spec validate_options!(term(), Macro.Env.t(), String.t(), String.t()) :: :ok | no_return()
  defdelegate validate_options!(options, caller, options_message, duplicate_label),
    to: Options,
    as: :validate!

  @doc false
  @spec entity(
          [Macro.t()],
          term(),
          module(),
          atom(),
          Macro.Env.t(),
          {String.t(), String.t()}
        ) :: Macro.t()
  def entity(arguments, options, module, function, caller, {label, mixed_label}) do
    validate_options!(
      options,
      caller,
      "#{label} options must be a keyword list",
      "#{label} field"
    )

    arguments = arguments ++ [source(caller)]

    case Keyword.pop(options, :do) do
      {nil, short_options} ->
        quote generated: true, line: caller.line, file: caller.file do
          require unquote(module)

          unquote(module).unquote(function)(
            unquote_splicing(arguments),
            unquote(short_options)
          )
        end

      {block, []} ->
        quote generated: true, line: caller.line, file: caller.file do
          require unquote(module)

          unquote(module).unquote(function)(unquote_splicing(arguments)) do
            unquote(block)
          end
        end

      {_block, _mixed_options} ->
        compile_error!(caller, "do not mix keyword and block fields in #{mixed_label}")
    end
  end

  @doc false
  @spec source(Macro.Env.t()) :: Macro.t()
  def source(caller), do: Macro.escape(%{line: caller.line})

  @doc false
  @spec compile_error!(Macro.Env.t(), String.t()) :: no_return()
  defdelegate compile_error!(caller, description), to: Options, as: :error!
end

defmodule Jido.Flow.DSL.Macros do
  @moduledoc false

  alias Jido.Action.Inline
  alias Jido.Flow.DSL.{InlineStep, MacroSupport, ModuleCompiler}

  @parallel_forbidden_imports [
    step: 2,
    step: 3,
    step: 4,
    choice: 2,
    timer: 2,
    await: 2,
    selection: 2,
    map: 2,
    parallel: 2,
    reduce: 2,
    iterate: 2,
    invoke: 2,
    handoff: 2,
    output: 1
  ]

  defmacro step(name, options) do
    caller = __CALLER__
    step_name = Macro.unique_var(:step_name, __MODULE__)

    declaration =
      entity(step_name, options, extension_module(["Flow", "Step"]), :__step__, caller)

    quote line: caller.line do
      unquote(step_name) = unquote(ModuleCompiler).register_step!(unquote(name), __ENV__)
      unquote(declaration)
    end
  end

  defmacro step(name, bindings, options) do
    inline_step(name, InlineStep.parse!(bindings, options, __CALLER__), __CALLER__)
  end

  defmacro step(name, bindings, options, body_options) do
    inline_step(
      name,
      InlineStep.parse!(bindings, options, body_options, __CALLER__),
      __CALLER__
    )
  end

  defp inline_step(name_ast, %{action: action, component_options: component_options}, caller) do
    name = Macro.unique_var(:step_name, __MODULE__)
    path = quote do: [host: Jido.Flow, step: unquote(name), role: :action]

    compiled =
      Inline.Compiler.compile!(path, action, caller,
        default_name: name,
        reserved_label: "Flow",
        module_label: "inline Step",
        emit: {InlineStep, :defer!},
        remove_imports: InlineStep.declaration_imports(caller)
      )

    options = [action: compiled.target_ast, params: action.params_ast] ++ component_options

    declaration =
      entity(name, options, extension_module(["Flow", "Step"]), :__step__, caller)

    quote line: caller.line do
      unquote(name) = unquote(ModuleCompiler).register_step!(unquote(name_ast), __ENV__)
      unquote(compiled.declaration_ast)
      unquote(declaration)
      unquote(InlineStep).emit!(__ENV__)
    end
  end

  defmacro map(name, options) do
    named_entity(name, options, "Map", :__map__, __CALLER__)
  end

  defmacro parallel(name, options) do
    caller = __CALLER__
    evaluated_name = Macro.unique_var(:declaration_name, __MODULE__)

    declaration =
      block_entity(
        evaluated_name,
        options,
        extension_module(["Flow", "Parallel"]),
        :__parallel__,
        caller
      )

    quote line: caller.line do
      import Jido.Flow.DSL.Macros, except: unquote(@parallel_forbidden_imports)
      import Jido.Flow.DSL.Extension, except: [flow: 1]

      unquote(evaluated_name) =
        unquote(ModuleCompiler).declaration_name!(unquote(name), __ENV__)

      Module.put_attribute(
        __MODULE__,
        :__jido_flow_parallel_name__,
        unquote(evaluated_name)
      )

      unquote(declaration)
      import Jido.Flow.DSL.Macros
      import Jido.Flow.DSL.Extension
      Module.delete_attribute(__MODULE__, :__jido_flow_parallel_name__)
    end
  end

  defmacro reduce(name, options) do
    named_entity(
      name,
      options,
      "Reduce",
      :__reduce__,
      __CALLER__
    )
  end

  defmacro choice(name, options) do
    named_block_entity(name, options, "Choice", :__choice__, __CALLER__)
  end

  defmacro iterate(name, options) do
    named_block_entity(name, options, "Iterate", :__iterate__, __CALLER__)
  end

  defp named_entity(name, options, segment, function, caller) do
    evaluated_name = Macro.unique_var(:declaration_name, __MODULE__)

    declaration =
      entity(
        evaluated_name,
        options,
        extension_module(["Flow", segment]),
        function,
        caller
      )

    named_declaration(name, evaluated_name, declaration, caller)
  end

  defp named_block_entity(name, options, segment, function, caller) do
    evaluated_name = Macro.unique_var(:declaration_name, __MODULE__)

    declaration =
      block_entity(evaluated_name, options, extension_module(["Flow", segment]), function, caller)

    named_declaration(name, evaluated_name, declaration, caller)
  end

  defp named_declaration(name, evaluated_name, declaration, caller) do
    quote line: caller.line do
      unquote(evaluated_name) = unquote(ModuleCompiler).declaration_name!(unquote(name), __ENV__)
      unquote(declaration)
    end
  end

  defmacro timer(name, options), do: named_entity(name, options, "Timer", :__timer__, __CALLER__)
  defmacro await(name, options), do: named_entity(name, options, "Await", :__await__, __CALLER__)

  defmacro selection(name, options),
    do: named_block_entity(name, options, "Selection", :__selection__, __CALLER__)

  defmacro invoke(name, options) do
    named_entity(name, options, "Invoke", :__invoke__, __CALLER__)
  end

  defmacro handoff(name, options) do
    named_entity(name, options, "Handoff", :__handoff__, __CALLER__)
  end

  defmacro output(value) do
    caller = __CALLER__
    module = extension_module(["Flow", "Output"])
    source = MacroSupport.source(caller)

    quote generated: true, line: caller.line, file: caller.file do
      require unquote(module)
      unquote(module).__output__(unquote(value), unquote(source))
    end
  end

  defp entity(name, options, module, function, caller) do
    MacroSupport.entity(
      [name],
      options,
      module,
      function,
      caller,
      {"Flow declaration", "one declaration"}
    )
  end

  defp block_entity(name, options, module, function, caller) do
    MacroSupport.validate_options!(
      options,
      caller,
      "Flow declaration options must be a keyword list",
      "Flow declaration field"
    )

    source = MacroSupport.source(caller)

    case options do
      [do: block] ->
        quote generated: true, line: caller.line, file: caller.file do
          require unquote(module)

          unquote(module).unquote(function)(unquote(name), unquote(source)) do
            unquote(block)
          end
        end

      _options ->
        MacroSupport.compile_error!(caller, "this Flow declaration requires a do block")
    end
  end

  defp extension_module(segments) do
    Module.concat(["Jido", "Flow", "DSL", "Extension" | segments])
  end
end

defmodule Jido.Flow.DSL.ParallelMacros do
  @moduledoc false

  alias Jido.Action.Inline
  alias Jido.Flow.DSL.{InlineStep, MacroSupport, ModuleCompiler}

  defmacro action(name, target_or_bindings, options) do
    if inline_bindings?(target_or_bindings) do
      inline_action(
        name,
        InlineStep.parse_parallel_action!(target_or_bindings, options, __CALLER__),
        __CALLER__
      )
    else
      explicit_action(name, target_or_bindings, options, __CALLER__)
    end
  end

  defmacro action(name, bindings, options, body_options) do
    inline_action(
      name,
      InlineStep.parse_parallel_action!(bindings, options, body_options, __CALLER__),
      __CALLER__
    )
  end

  defp explicit_action(name, target, options, caller) do
    MacroSupport.validate_options!(
      options,
      caller,
      "Parallel action options must be a keyword list",
      "Parallel action field"
    )

    declaration(name, [action: target] ++ options, caller)
  end

  defp inline_action(name_ast, %{action: action}, caller) do
    name = Macro.unique_var(:parallel_action_name, __MODULE__)

    path =
      quote do
        [
          host: Jido.Flow,
          parallel:
            Module.get_attribute(
              unquote(caller.module),
              :__jido_flow_parallel_name__
            ),
          action: unquote(name),
          role: :action
        ]
      end

    compiled =
      Inline.Compiler.compile!(path, action, caller,
        default_name: name,
        reserved_label: "Flow",
        module_label: "inline Parallel Action",
        emit: {InlineStep, :defer!},
        remove_imports: InlineStep.declaration_imports(caller)
      )

    entity =
      entity(name, [action: compiled.target_ast, params: action.params_ast], caller)

    quote line: caller.line do
      unquote(name) = unquote(ModuleCompiler).declaration_name!(unquote(name_ast), __ENV__)
      unquote(compiled.declaration_ast)
      unquote(entity)
      unquote(InlineStep).emit!(__ENV__)
    end
  end

  defp declaration(name_ast, options, caller) do
    evaluated_name = Macro.unique_var(:parallel_action_name, __MODULE__)
    declaration = entity(evaluated_name, options, caller)

    quote line: caller.line do
      unquote(evaluated_name) =
        unquote(ModuleCompiler).declaration_name!(unquote(name_ast), __ENV__)

      unquote(declaration)
    end
  end

  defp entity(name, options, caller) do
    MacroSupport.entity(
      [name],
      options,
      Jido.Flow.DSL.Extension.Flow.Parallel.ParallelAction,
      :__parallel_action__,
      caller,
      {"Parallel action", "one Parallel action"}
    )
  end

  defp inline_bindings?({:<-, _metadata, [_pattern, _source]}), do: true
  defp inline_bindings?(bindings) when is_list(bindings), do: true
  defp inline_bindings?(_target), do: false
end

defmodule Jido.Flow.DSL.ChoiceMacros do
  @moduledoc false

  alias Jido.Flow.DSL.MacroSupport

  defmacro option(name, options) do
    evaluated_name = Macro.unique_var(:option_name, __MODULE__)

    declaration =
      nested_entity(
        [evaluated_name],
        options,
        extension_module(["Flow", "Choice", "Option"]),
        :__option__,
        __CALLER__
      )

    quote line: __CALLER__.line do
      unquote(evaluated_name) = unquote(name)
      unquote(declaration)
    end
  end

  defmacro otherwise(options) do
    nested_entity(
      [],
      options,
      extension_module(["Flow", "Choice", "Otherwise"]),
      :__otherwise__,
      __CALLER__
    )
  end

  defp nested_entity(arguments, options, module, function, caller) do
    MacroSupport.entity(
      arguments,
      options,
      module,
      function,
      caller,
      {"Choice declaration", "one Choice target"}
    )
  end

  defp extension_module(segments) do
    Module.concat(["Jido", "Flow", "DSL", "Extension" | segments])
  end
end

defmodule Jido.Flow.DSL.IterateMacros do
  @moduledoc false

  alias Jido.Flow.DSL.MacroSupport

  defmacro state(schema, options) do
    MacroSupport.entity(
      [schema],
      options,
      extension_module(["Flow", "Iterate", "State"]),
      :__state__,
      __CALLER__,
      {"Iterate state", "Iterate state"}
    )
  end

  defp extension_module(segments) do
    Module.concat(["Jido", "Flow", "DSL", "Extension" | segments])
  end
end

defmodule Jido.Flow.DSL.SelectionMacros do
  @moduledoc false
  alias Jido.Flow.DSL.MacroSupport

  defmacro timer(name, options) do
    MacroSupport.entity(
      [name],
      options,
      Jido.Flow.DSL.Extension.Flow.Selection.TimerOption,
      :__timer_option__,
      __CALLER__,
      {"Selection timer", "one Selection timer"}
    )
  end

  defmacro await(name, options) do
    MacroSupport.entity(
      [name],
      options,
      Jido.Flow.DSL.Extension.Flow.Selection.AwaitOption,
      :__await_option__,
      __CALLER__,
      {"Selection await", "one Selection await"}
    )
  end
end
