defmodule Jido.Flow.DSL.Macros do
  @moduledoc false

  alias Jido.Action.Inline
  alias Jido.Instruction.Config
  alias Jido.Flow.DSL.{Authoring, InlineStep}

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
      unquote(step_name) = unquote(Authoring).register_step!(unquote(name), __ENV__)
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
      unquote(name) = unquote(Authoring).register_step!(unquote(name_ast), __ENV__)
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
    macros_module = __MODULE__
    extension = extension_module([])

    declaration =
      block_entity(
        evaluated_name,
        options,
        extension_module(["Flow", "Parallel"]),
        :__parallel__,
        caller
      )

    quote line: caller.line do
      import unquote(macros_module), except: unquote(@parallel_forbidden_imports)
      import unquote(extension), except: [flow: 1]

      unquote(evaluated_name) =
        unquote(Authoring).declaration_name!(unquote(name), __ENV__)

      Module.put_attribute(
        __MODULE__,
        :__jido_flow_parallel_name__,
        unquote(evaluated_name)
      )

      unquote(declaration)
      import unquote(macros_module)
      import unquote(extension)
      Module.delete_attribute(__MODULE__, :__jido_flow_parallel_name__)
    end
  end

  defmacro reduce(name, options) do
    named_entity(name, options, "Reduce", :__reduce__, __CALLER__)
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
      unquote(evaluated_name) = unquote(Authoring).declaration_name!(unquote(name), __ENV__)
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
    source = Authoring.source(caller)

    quote generated: true, line: caller.line, file: caller.file do
      require unquote(module)
      unquote(module).__output__(unquote(value), unquote(source))
    end
  end

  defp entity(name, options, module, function, caller) do
    Authoring.entity(
      [name],
      options,
      module,
      function,
      caller,
      {"Flow declaration", "one declaration"}
    )
  end

  defp block_entity(name, options, module, function, caller) do
    Config.validate_options!(
      options,
      caller,
      "Flow declaration options must be a keyword list",
      "Flow declaration field"
    )

    source = Authoring.source(caller)

    case options do
      [do: block] ->
        quote generated: true, line: caller.line, file: caller.file do
          require unquote(module)

          unquote(module).unquote(function)(unquote(name), unquote(source)) do
            unquote(block)
          end
        end

      _options ->
        Config.compile_error!(caller, "this Flow declaration requires a do block")
    end
  end

  defp extension_module(segments) do
    Module.concat(["Jido", "Flow", "DSL", "Extension" | segments])
  end
end
