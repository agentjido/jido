defmodule Jido.Flow.DSL.ParallelMacros do
  @moduledoc false

  alias Jido.Action.Inline
  alias Jido.Instruction.Config
  alias Jido.Flow.DSL.{Authoring, InlineStep}

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
    Config.validate_options!(
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
      unquote(name) = unquote(Authoring).declaration_name!(unquote(name_ast), __ENV__)
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
        unquote(Authoring).declaration_name!(unquote(name_ast), __ENV__)

      unquote(declaration)
    end
  end

  defp entity(name, options, caller) do
    Authoring.entity(
      [name],
      options,
      extension_module(["Flow", "Parallel", "ParallelAction"]),
      :__parallel_action__,
      caller,
      {"Parallel action", "one Parallel action"}
    )
  end

  defp extension_module(segments),
    do: Module.concat(["Jido", "Flow", "DSL", "Extension" | segments])

  defp inline_bindings?({:<-, _metadata, [_pattern, _source]}), do: true
  defp inline_bindings?(bindings) when is_list(bindings), do: true
  defp inline_bindings?(_target), do: false
end
