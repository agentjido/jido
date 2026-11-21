defmodule Jido.Flow.Inline do
  @moduledoc """
  Compiles an embedded Flow declaration for another module DSL.

  This module is for compile-time host DSLs. A host should call
  `use Jido.Flow.Inline` in each owner. It creates a normal `Jido.Flow` module
  from standard Flow options and a standard `flow do` body. The host stores the
  returned target as it would store any other Flow module.

  A host macro must emit `declaration_ast` before it uses `target_ast`:

      defmacro operation(path, options, do: body) do
        compiled =
          Jido.Flow.Inline.compile!(path, options, body, __CALLER__)

        quote do
          unquote(compiled.declaration_ast)
          unquote(compiled.target_ast)
        end
      end

  `path` is a compile-time identity owned by the host. It is a proper list of
  at least three typed segments. It starts with a `:host` segment and ends
  with `role: :flow`. The host owns the middle segment names. The generated
  module name is an implementation detail. Deploy the owner and generated
  Flow BEAM files together.

  The path and Flow options evaluate once in the owner at the declaration
  site. The embedded body then uses the normal Flow compiler in the generated
  module. It does not capture owner attributes or functions. Put reusable code
  in Actions or Flow extensions.

  An inline Flow does not add a Flow type, execution path, authoring form, or
  serialization format. After compilation it is an ordinary Flow module.
  """

  alias Jido.Flow.Inline.{Compiler, Owner}

  @typedoc "One non-nil value in a typed host identity."
  @type path_value :: atom() | String.t() | integer()

  @typedoc "A typed host identity that starts with `:host` and ends with `role: :flow`."
  @type path :: [{atom(), path_value()}]

  @typedoc "AST returned to a host. Emit the declaration before using the target."
  @type compilation :: %{target_ast: Macro.t(), declaration_ast: Macro.t()}

  @doc "Installs owner lookup and compile hooks. Repeated use preserves declarations."
  defmacro __using__(_options) do
    quote do
      Jido.Flow.Inline.setup!(__ENV__)
    end
  end

  @doc "Installs owner hooks during module construction. Usually called through `use`."
  @spec setup!(Macro.Env.t()) :: :ok
  def setup!(caller), do: Owner.setup!(caller)

  @doc """
  Compiles one embedded Flow declaration.

  `options_ast` accepts the same options as `use Jido.Flow`, including Flow
  extensions. The path and options evaluate once in the owner when the emitted
  declaration runs. `body_ast` is the contents of a normal `flow do` block and
  compiles in the generated Flow module. It can use configured extensions, but
  it cannot use owner attributes or functions. All three inputs are trusted
  compile-time source. Do not pass runtime or stored code.

  Raises `CompileError` for an invalid owner, identity, Flow option, or Flow
  body. Owner, path, identity, and option checks run before target module
  replacement. After those checks pass, recompilation removes the previous
  generated module before it compiles the new body. This prevents old Flow DSL
  state from leaking into the new graph. Processes that already run the old
  code can finish under normal BEAM code-version rules. A body compilation
  failure does not restore the previous target for new calls.
  """
  @spec compile!(Macro.t(), Macro.t(), Macro.t(), Macro.Env.t()) :: compilation()
  def compile!(path_ast, options_ast, body_ast, caller) do
    Compiler.compile!(path_ast, options_ast, body_ast, caller)
  end

  @doc """
  Returns the generated Flow module for an owner's exact typed path.

  Lookup is available only after the owner compiles. It does not compile or run
  the Flow. It verifies that the indexed target has the matching generated
  ownership marker.
  """
  @spec target!(module(), path()) :: module()
  def target!(owner, path), do: Owner.target!(owner, path)
end
