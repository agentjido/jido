defmodule Jido.Action.Inline do
  @moduledoc """
  Compile-time inline Action support for host DSLs.

  Call `use Jido.Action.Inline` in each owner module. A host macro then:

  1. Calls `parse_bound!/3` or `parse_callback!/3` for the slot's input mode.
  2. Parses and validates `params_ast` with its own expression adapter in bound mode.
  3. Calls `compile!/4` and emits `declaration_ast` at the declaration site.
  4. Uses `target_ast` after that declaration AST to store an ordinary Action target.

  For example, a host can use the path
  `[host: MyApp.DSL, declaration: "greet", role: :action]`. It can later call
  `target!(Owner, path)` to retrieve only the target, without the source mapping.
  A host with nested declarations can add its own typed segments, such as
  `group: "billing"` and `operation: "charge"`.

  Paths and Action metadata are separate. The host supplies a default metadata
  name; a declaration can override it with `name:`. Generated module names are
  implementation details, not public names or code versions.

  Bodies keep the owner's lexical scope and private helpers. Deploy the owner
  and generated Action BEAM files together. Lookup is available only after the
  owner compiles. It does not execute work or create atoms. Do not pass runtime
  or stored code to the compile-time APIs.

  See
  [Building DSLs With Inline Actions](building-dsls-with-inline-actions.md) for a complete public-only host
  with bound input, callback input, schemas, execution context, and lookup.
  """

  alias Jido.Action.Inline.{Compiler, Owner, Parser}

  @enforce_keys [:mode, :params_ast, :pattern_ast, :body_ast, :options, :context_ast]
  defstruct @enforce_keys ++ [clauses: nil]

  @typedoc "The input contract selected by the host slot."
  @type mode :: :bound | :callback

  @typedoc "A typed host identity. It starts with `:host` and ends with `:role`."
  @type path :: [{atom(), atom() | String.t() | integer()}]

  @typedoc "One owner-function head: parameter pattern, optional guard, and body."
  @type clause :: {Macro.t(), Macro.t() | nil, Macro.t()}

  @typedoc """
  Parsed compile-time code, not a runtime model.

  `params_ast` contains the source AST in bound mode and is `nil` only in
  callback mode. `pattern_ast` matches validated Action input for a single
  expression body. `body_ast` is the original `do` AST. `clauses` is set when
  the body is a list of `->` heads; the compiler then emits one owner `def`
  per clause and ignores `pattern_ast` as the function head. `options`
  contains metadata and schema AST; the parser extracts `do` and `context`
  into `body_ast` and `context_ast`. Hosts must parse and validate source AST
  before they compile a declaration.
  """
  @type t :: %__MODULE__{
          mode: mode(),
          params_ast: Macro.t() | nil,
          pattern_ast: Macro.t() | nil,
          body_ast: Macro.t(),
          options: keyword(Macro.t()),
          context_ast: Macro.t() | nil,
          clauses: [clause()] | nil
        }

  @typedoc "AST returned to a host. Emit the declaration before using the target."
  @type compilation :: %{target_ast: Macro.t(), declaration_ast: Macro.t()}

  @typedoc "Declaration-only imports to remove from the body, by module and exact arity."
  @type remove_imports :: [{module(), [{atom(), non_neg_integer()}]}]

  @typedoc "Action declaration options. Values are source AST evaluated or compiled in the owner."
  @type action_option ::
          {:do, Macro.t()}
          | {:name, Macro.t()}
          | {:description, Macro.t()}
          | {:schema, Macro.t()}
          | {:output_schema, Macro.t()}
          | {:context, Macro.t()}

  @typedoc "Host compiler options. `default_name` is AST; the import list is an exact value."
  @type compiler_option :: {:default_name, Macro.t()} | {:remove_imports, remove_imports()}

  @doc "Installs owner hooks. Repeated use preserves declarations and host hooks."
  defmacro __using__(_options) do
    quote do
      Jido.Action.Inline.setup!(__ENV__)
    end
  end

  @doc """
  Installs owner hooks during module construction. Usually called through `use`.

  Repeated setup preserves existing inline declarations and the host's hooks.
  Raises `CompileError` outside a compiling module or for reserved function
  conflicts. Setup does not run an inline body.
  """
  @spec setup!(Macro.Env.t()) :: :ok
  def setup!(caller), do: Owner.setup!(caller)

  @doc """
  Parses named bindings, a binding list, a sole map binding, or `[]`.

  A named binding is `value <- source`. A list groups named bindings. A sole
  map binding, such as `%{name: name} <- source`, uses the complete source as
  Action params. `[]` produces an empty parameter map. Duplicate names, mixed
  map and named bindings, bare `_`, pins, header guards, and top-level struct
  patterns are not supported.

  A `do` body of only `->` clauses compiles to several owner-function heads
  over the validated parameter map. Binding-header guards stay illegal.
  Each clause has one parameter pattern. Clause heads may use `when`; guards
  do not permit additional parameter patterns.

  Options:

  - `do:` is the required Action body, either expressions or `->` clauses.
  - `name:` overrides the host's default public Action name, not its identity.
  - `description:` sets public Action metadata; it defaults to `nil`.
  - `schema:` and `output_schema:` use static Action schemas. Both default to
    `Zoi.map()`. Schemas are not inferred from patterns. Input defaults apply
    before the body matches its parameters.
  - `context: named_variable` binds actual callback context without adding a
    parameter or a schema field. It must not collide with a pattern variable.

  Parsing checks header and option shape only. The host must parse and
  validate the returned source AST before calling `compile!/4`. The parser
  does not expand or evaluate source calls. Bindings belong to the host's
  parameter mapping; they are not retained by an extracted Action target.

  Raises `CompileError` for an invalid header or option, at the source location.
  """
  @spec parse_bound!(Macro.t(), [action_option()], Macro.Env.t()) :: t()
  def parse_bound!(bindings, options, caller), do: Parser.bound!(bindings, options, caller)

  @doc """
  Parses a named parameter variable or a map pattern for direct callback input.

  Accepts the same options as `parse_bound!/3`, but rejects source bindings.
  There is no host parameter mapping and `params_ast` is `nil`. Normal Action
  input validation still runs, including schema defaults before the callback
  pattern matches. Pass `nil` as the pattern when the body is a `->` clause
  list. A clause body cannot combine with a header pattern. Raises
  `CompileError` for invalid headers or options.
  """
  @spec parse_callback!(Macro.t() | nil, [action_option()], Macro.Env.t()) :: t()
  def parse_callback!(pattern, options, caller), do: Parser.callback!(pattern, options, caller)

  @doc """
  Builds declaration and target AST inside a compiling owner module.

  `path_ast` must evaluate to a typed path with a host namespace, one or more
  declaration segments, and a final role. Each segment is an atom key paired
  with a non-nil atom, string, or integer. The path is evaluated once, when the
  emitted declaration executes. A false compile-time branch creates no target.

  Options:

  - `default_name:` is metadata AST used when the parsed options omit `name:`.
    Supply it unless the declaration has an explicit name.
  - `remove_imports:` lists exact declaration-only imports to remove from the
    body. Other imports remain available. The default is `[]`.

  Metadata and schemas evaluate in the owner at the declaration site, under
  normal Action configuration and static-schema rules. `context:` binds the
  actual callback context without changing parameters or schemas.

  Raises `CompileError` for invalid configuration, paths, duplicate identities,
  reserved owner functions, or calls outside a compiling owner. The returned
  AST is a compile-time implementation detail; it is not a runtime model.
  """
  @spec compile!(Macro.t(), t(), Macro.Env.t(), [compiler_option()]) :: compilation()
  def compile!(path_ast, %__MODULE__{} = parsed, caller, options) do
    Parser.options!(options, [:default_name, :remove_imports], caller, "compiler")
    Compiler.compile!(path_ast, parsed, caller, options)
  end

  @doc "Compiles a declaration with an explicit `name:` and no compiler options. See `compile!/4`."
  @spec compile!(Macro.t(), t(), Macro.Env.t()) :: compilation()
  def compile!(path_ast, parsed, caller), do: compile!(path_ast, parsed, caller, [])

  @doc """
  Returns the compiled Action for the owner's exact typed path.

  Raises `ArgumentError` for an invalid or unknown path, an owner without inline
  targets, or an owner that is still compiling. Lookup does not create atoms,
  compile code, execute a body, or return the original source mapping.

  Deploy the owner and generated Action BEAM files together. Path identity
  identifies the declaration, not a code version. The returned module is an
  ordinary Action target for Exec or a trusted host Registry.
  """
  @spec target!(module(), path()) :: module()
  def target!(owner, path), do: Owner.target!(owner, path)
end
