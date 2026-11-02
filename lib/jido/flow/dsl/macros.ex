defmodule Jido.Flow.DSL.Macros do
  @moduledoc false

  alias Jido.Action.Inline
  alias Jido.Flow.DSL.{InlineStep, MacroSupport, ModuleCompiler}

  defmacro step(name, options) do
    caller = __CALLER__
    step_name = Macro.unique_var(:step_name, __MODULE__)
    declaration = entity(step_name, options, step_module(), :__step__, caller)

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

  defmacro output(value) do
    caller = __CALLER__
    module = output_module()
    source = MacroSupport.source(caller)

    quote generated: true, line: caller.line, file: caller.file do
      require unquote(module)
      unquote(module).__output__(unquote(value), unquote(source))
    end
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
    declaration = entity(name, options, step_module(), :__step__, caller)

    quote line: caller.line do
      unquote(name) = unquote(ModuleCompiler).register_step!(unquote(name_ast), __ENV__)
      unquote(compiled.declaration_ast)
      unquote(declaration)
      unquote(InlineStep).emit!(__ENV__)
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

  defp step_module, do: Module.concat(["Jido", "Flow", "DSL", "Core", "Flow", "Step"])
  defp output_module, do: Module.concat(["Jido", "Flow", "DSL", "Core", "Flow", "Output"])
end
