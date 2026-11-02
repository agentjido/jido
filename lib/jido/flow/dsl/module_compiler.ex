defmodule Jido.Flow.DSL.ModuleCompiler do
  @moduledoc false

  alias Jido.Flow.DSL.{Lowerer, MacroSupport}
  alias Jido.Flow.Definition

  @doc false
  defmacro __using__(opts_ast) do
    module_compiler = __MODULE__
    {flow_opts_ast, extensions} = split_options!(opts_ast, __CALLER__)

    quote location: :keep do
      use Jido.Flow.DSL, extensions: unquote(Macro.escape(extensions))
      @before_compile Jido.Flow.DSL.ModuleCompiler
      Jido.Action.Inline.setup!(__ENV__)
      unquote(module_compiler).reserve_function!(__ENV__, {:step_action, 1})

      use Jido.Authoring.Compiler,
        kind: :flow,
        config: Jido.Authoring.Config.prepare!(:flow, unquote(flow_opts_ast), __ENV__)

      @doc "Returns the canonical Flow data for this module."
      @spec flow() :: Jido.Flow.t()
      def flow()

      @doc """
      Returns the Action target of a named Step.

      Accepts a string or atom name. Raises `ArgumentError` for invalid names,
      unknown names, and non-Step components, including Subflows. The result
      does not include the original Step's params, dependencies, or metadata.

      Works for inline and explicit Action-backed Steps. Call it after this
      Flow module has compiled, not from its unfinished DSL block. Lookup
      does not run the body or create atoms. Supply new Step fields when
      reusing the target through map-based definitions. For stored JSON,
      register the target with an application-owned Action identifier
      and register the required parameter atom keys.

      Deploy the owning module and generated Actions together. The target
      can remain unchanged after a body edit; it is not a code version.
      """
      @spec step_action(String.t() | atom()) :: module()
      @__jido_inline_generated__ {:step_action, 1}
      def step_action(name)
      Module.delete_attribute(__MODULE__, :__jido_inline_generated__)

      @doc false
      @spec __jido_flow_source_map__() :: Jido.Flow.source_map()
      def __jido_flow_source_map__()

      @doc "Returns the derived execution plan for this module's canonical Flow."
      @spec compiled() :: Runic.Workflow.t()
      def compiled()

      @doc "Runs this Flow through Jido.Exec with default execution options."
      @impl Jido.Action
      @spec run(map(), map()) :: Jido.Exec.exec_result()
      def run(params, context)
    end
  end

  @doc false
  @spec validate_options!(term(), Macro.Env.t()) :: :ok
  def validate_options!(options, caller) do
    {flow_options, _extensions} = split_options!(options, caller)
    Jido.Authoring.Config.prepare!(:flow, flow_options, caller)
    :ok
  end

  defp split_options!(opts_ast, caller) when is_list(opts_ast) do
    if Keyword.keyword?(opts_ast) do
      case Keyword.get_values(opts_ast, :extensions) do
        [] ->
          {opts_ast, []}

        [extensions_ast] ->
          {Keyword.delete(opts_ast, :extensions), extensions!(extensions_ast, caller)}

        [_first | _rest] ->
          extension_error!(caller, "Flow extensions can be configured only once")
      end
    else
      {opts_ast, []}
    end
  end

  defp split_options!(opts_ast, _caller), do: {opts_ast, []}

  defp extensions!(extensions, caller) when is_list(extensions) do
    if List.improper?(extensions) or Enum.any?(extensions, &improper_list_ast?/1) do
      extension_error!(caller, "Flow extensions must be a proper list")
    end

    modules = Enum.map(extensions, &extension!(&1, caller))

    if length(modules) != length(Enum.uniq(modules)) do
      extension_error!(caller, "duplicate Flow extension")
    end

    modules
  end

  defp extensions!(_extensions, caller),
    do: extension_error!(caller, "Flow extensions must be a list")

  defp improper_list_ast?({:|, _meta, [_head, _tail]}), do: true
  defp improper_list_ast?(_extension), do: false

  defp extension!(extension_ast, caller) do
    extension = Macro.expand(extension_ast, caller)

    with true <- is_atom(extension) and extension not in [nil, true, false],
         {:module, ^extension} <- Code.ensure_compiled(extension),
         true <- Spark.implements_behaviour?(extension, Jido.Flow.Extension),
         true <- Spark.implements_behaviour?(extension, Spark.Dsl.Extension),
         true <- function_exported?(extension, :__jido_flow_extension__, 0) do
      extension
    else
      _ -> extension_error!(caller, "Flow extension must use Jido.Flow.Extension")
    end
  end

  defp extension_error!(caller, description) do
    raise CompileError, file: caller.file, line: caller.line, description: description
  end

  @doc false
  @spec register_step!(term(), Macro.Env.t()) :: String.t()
  def register_step!(value, env) do
    name = declaration_name!(value, env)

    names = Module.get_attribute(env.module, :__jido_flow_step_names__) || MapSet.new()

    if MapSet.member?(names, name) do
      MacroSupport.compile_error!(env, "duplicate Step name: #{inspect(name)}")
    end

    Module.put_attribute(env.module, :__jido_flow_step_names__, MapSet.put(names, name))
    name
  end

  @doc false
  # Declarations normalize names as data definitions do.
  @spec declaration_name!(term(), Macro.Env.t()) :: String.t()
  def declaration_name!(value, env) do
    case Definition.name(value) do
      {:ok, name} -> name
      {:error, error} -> MacroSupport.compile_error!(env, Exception.message(error))
    end
  end

  @doc false
  @spec reserve_function!(Macro.Env.t(), {atom(), non_neg_integer()}) :: :ok
  def reserve_function!(env, function) do
    Jido.Action.Inline.Owner.reserve_function!(env, function, "Flow")
  end

  @doc false
  defmacro __before_compile__(env), do: before_compile(env)

  @doc false
  @spec before_compile(Macro.Env.t()) :: Macro.t()
  def before_compile(env) do
    config = Module.get_attribute(env.module, :__jido_authoring_config__)

    {flow, source_map} = compile_flow!(env, config)
    escaped_flow = Macro.escape(flow)
    escaped_source_map = Macro.escape(source_map)

    step_actions =
      for {name, %{kind: :call, call: %{kind: :action, target: action}}} <-
            flow.components,
          into: %{},
          do: {name, action}

    quote generated: true do
      def flow, do: unquote(escaped_flow)
      def __jido_flow_source_map__, do: unquote(escaped_source_map)

      @__jido_inline_generated__ {:step_action, 1}
      def step_action(name) do
        with {:ok, normalized} <- Jido.Flow.Definition.name(name),
             {:ok, action} <- Map.fetch(unquote(Macro.escape(step_actions)), normalized) do
          action
        else
          _ ->
            raise ArgumentError,
                  "expected an Action-backed Step name in #{inspect(__MODULE__)}, got: #{inspect(name)}"
        end
      end

      Module.delete_attribute(__MODULE__, :__jido_inline_generated__)

      def compiled,
        do: Jido.Exec.compile!(flow(), source_map: __jido_flow_source_map__())

      def run(params, context), do: Jido.Exec.run(__MODULE__, params, context)
    end
  end

  defp compile_flow!(env, config) do
    case Lowerer.lower(env.module, config, env.file) do
      {:ok, flow, source_map} ->
        case Jido.Exec.Compiler.validate_targets(flow) do
          {:ok, flow} ->
            {flow, source_map}

          {:error, error} ->
            raise_compile_error!(env, error, source_map)
        end

      {:error, error} ->
        raise_compile_error!(env, error, %{})
    end
  end

  @spec raise_compile_error!(
          Macro.Env.t(),
          Exception.t(),
          Jido.Flow.source_map()
        ) ::
          no_return()
  defp raise_compile_error!(env, error, source_map) do
    error = Jido.Flow.DSL.SourceMap.attach_error(error, source_map)
    details = Map.get(error, :details, %{})

    raise CompileError,
      description: Exception.message(error),
      file: source_file(details, env),
      line: source_line(details, env)
  end

  defp source_file(%{file: file}, _env) when is_binary(file), do: file
  defp source_file(_details, env), do: env.file

  defp source_line(%{line: line}, _env) when is_integer(line) and line > 0, do: line
  defp source_line(_details, env), do: env.line
end
