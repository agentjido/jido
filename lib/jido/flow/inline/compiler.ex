defmodule Jido.Flow.Inline.Compiler do
  @moduledoc false

  alias Jido.Flow.Inline.Owner

  @doc false
  @spec compile!(Macro.t(), Macro.t(), Macro.t(), Macro.Env.t()) ::
          Jido.Flow.Inline.compilation()
  def compile!(path_ast, options_ast, body_ast, caller) do
    Owner.ensure_compiling!(caller)
    target = Macro.unique_var(:inline_flow, __MODULE__)
    path = Macro.unique_var(:inline_flow_path, __MODULE__)
    options = Macro.unique_var(:inline_flow_options, __MODULE__)

    declaration =
      quote line: caller.line do
        unquote(path) = unquote(path_ast)
        unquote(options) = unquote(options_ast)

        unquote(target) =
          unquote(__MODULE__).create!(
            unquote(path),
            unquote(options),
            unquote(Macro.escape(body_ast)),
            __ENV__
          )
      end

    %{target_ast: target, declaration_ast: declaration}
  end

  @doc false
  @spec create!(term(), term(), Macro.t(), Macro.Env.t()) :: module()
  def create!(path, options, body_ast, caller) do
    Owner.setup!(caller)
    path = Owner.validate_path!(path, caller)
    Owner.check_identity!(path, caller)

    target = identity(caller.module, path)
    ensure_owner!(target, {caller.module, path}, caller)
    Jido.Flow.DSL.ModuleCompiler.validate_options!(options, caller)
    reset_target!(target)
    create_flow!(target, caller.module, path, options, body_ast, caller)
    Owner.register!(path, target, caller)
    target
  end

  defp identity(owner, path) do
    digest =
      :crypto.hash(:sha256, :erlang.term_to_binary({owner, path}))
      |> Base.encode16(case: :lower)

    Module.concat(Jido.Flow.Generated.Inline, "F" <> digest)
  end

  defp ensure_owner!(target, identity, caller) do
    if Code.ensure_loaded?(target) and not owned_target?(target, identity) do
      error!(
        caller,
        "generated inline Flow module #{inspect(target)} already belongs to another definition"
      )
    end
  end

  defp owned_target?(target, identity) do
    function_exported?(target, :__jido_inline_flow__, 0) and
      target.__jido_inline_flow__() == identity
  rescue
    _error -> false
  catch
    _kind, _reason -> false
  end

  defp reset_target!(target) do
    if Code.loaded?(target) do
      :code.delete(target)
      :code.soft_purge(target)
    end

    :ok
  end

  defp create_flow!(target, owner, path, options, body_ast, caller) do
    definition =
      quote generated: true do
        @moduledoc false
        use Jido.Flow, unquote(Macro.escape(options))

        flow do
          unquote(body_ast)
        end

        @doc false
        @spec __jido_inline_flow__() :: {module(), Jido.Flow.Inline.path()}
        def __jido_inline_flow__(), do: unquote(Macro.escape({owner, path}))
      end

    env = %{caller | file: caller.file, line: caller.line}
    Module.create(target, definition, env)
  end

  defp error!(caller, description) do
    raise CompileError, file: caller.file, line: caller.line, description: description
  end
end
