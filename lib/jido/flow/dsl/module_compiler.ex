defmodule Jido.Flow.DSL.ModuleCompiler do
  @moduledoc false

  alias Jido.Authoring.Registry
  alias Jido.Flow.Config, as: FlowConfig
  alias Jido.Flow.DSL.{Builder, MacroSupport, Name}
  alias Jido.Flow.Error

  @config_fields [:name, :description, :schema, :output_schema]
  @module_config_fields [:id, :vsn | @config_fields]

  @doc false
  @spec __using__(Macro.t()) :: Macro.t()
  defmacro __using__(opts_ast) do
    module_compiler = __MODULE__

    quote location: :keep do
      use Jido.Flow.DSL
      @before_compile Jido.Flow.DSL.ModuleCompiler
      Jido.Action.Inline.setup!(__ENV__)
      unquote(module_compiler).reserve_function!(__ENV__, {:step_action, 1})

      @behaviour Jido.Flow
      @__jido_authoring_config__ Jido.Flow.DSL.ModuleCompiler.prepare_config!(
                                   unquote(opts_ast),
                                   __ENV__
                                 )
      @__jido_authoring_contract__ Jido.Authoring.Compiler.compile_contract(
                                     :flow,
                                     @__jido_authoring_config__
                                   )

      @doc "Returns the name of the Flow."
      @spec name() :: String.t()
      def name, do: @__jido_authoring_config__[:name]

      @doc "Returns the description of the Flow."
      @spec description() :: String.t() | nil
      def description, do: @__jido_authoring_config__[:description]

      @doc "Returns the input schema of the Flow."
      @spec schema() :: Jido.Action.schema()
      def schema, do: @__jido_authoring_config__[:schema]

      @doc "Returns the output schema of the Flow."
      @spec output_schema() :: Jido.Action.schema()
      def output_schema, do: @__jido_authoring_config__[:output_schema]

      @doc "Returns the compile-time Flow authoring contract as JSON-safe data."
      @spec authoring_contract() :: map()
      def authoring_contract,
        do: Jido.Authoring.Compiler.contract!(@__jido_authoring_contract__)

      @doc "Validates input parameters for the Flow."
      @impl Jido.Flow
      @spec validate_params(term()) :: {:ok, map()} | {:error, term()}
      def validate_params(params), do: Jido.Flow.validate_params_for(params, __MODULE__)

      @doc "Validates a Flow output value."
      @impl Jido.Flow
      @spec validate_output(map() | Jido.Action.Output.t()) ::
              {:ok, map() | Jido.Action.Output.t()} | {:error, term()}
      def validate_output(output), do: Jido.Flow.validate_output_for(output, __MODULE__)

      @doc false
      @spec __jido_kind__() :: :flow
      def __jido_kind__, do: :flow

      @doc false
      @spec __jido_authoring__() :: Jido.Authoring.Manifest.t()
      def __jido_authoring__ do
        %{
          id: @__jido_authoring_config__[:id],
          kind: :flow,
          vsn: @__jido_authoring_config__[:vsn],
          target: __MODULE__,
          name: name(),
          description: description()
        }
      end

      @doc "Returns the canonical Flow data for this module."
      @spec flow() :: Jido.Flow.t()
      def flow()

      @doc "Returns the Action target of a named Step."
      @spec step_action(String.t() | atom()) :: module()
      @__jido_inline_generated__ {:step_action, 1}
      def step_action(name)
      Module.delete_attribute(__MODULE__, :__jido_inline_generated__)

      @doc false
      @spec __jido_flow_source_map__() :: Jido.Flow.source_map()
      def __jido_flow_source_map__()
    end
  end

  @doc false
  @spec prepare_config!(term(), Macro.Env.t()) :: map() | no_return()
  def prepare_config!(raw_options, env) do
    options =
      raw_options
      |> normalize_options()
      |> module_defaults(env.module)

    case validate_module_config(options) do
      {:ok, options} ->
        ensure_escapable_schema!(options.schema, :schema, env)
        ensure_escapable_schema!(options.output_schema, :output_schema, env)
        options

      {:error, error} ->
        raise CompileError,
          description: "Flow configuration validation failed: #{Exception.message(error)}",
          file: env.file,
          line: env.line
    end
  end

  @doc false
  @spec register_step!(term(), Macro.Env.t()) :: String.t() | no_return()
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
  @spec declaration_name!(term(), Macro.Env.t()) :: String.t() | no_return()
  def declaration_name!(value, env) do
    case Name.normalize(value) do
      {:ok, name} -> name
      {:error, message} -> MacroSupport.compile_error!(env, message)
    end
  end

  @doc false
  @spec reserve_function!(Macro.Env.t(), {atom(), arity()}) :: term()
  def reserve_function!(env, function) do
    Jido.Action.Inline.Owner.reserve_function!(env, function, "Flow")
  end

  @doc false
  @spec __before_compile__(Macro.Env.t()) :: Macro.t()
  defmacro __before_compile__(env), do: before_compile(env)

  @doc false
  @spec before_compile(Macro.Env.t()) :: Macro.t()
  def before_compile(env) do
    config = Module.get_attribute(env.module, :__jido_authoring_config__)
    {flow, source_map} = build_flow!(env, config)
    escaped_flow = Macro.escape(flow)
    escaped_source_map = Macro.escape(source_map)

    step_actions =
      flow.forms
      |> Enum.flat_map(fn {name, form} ->
        if match?(%Jido.Flow.Call{}, form) and
             Jido.Instruction.target_kind(form.instruction) == {:ok, :action},
           do: [{name, form.instruction.target}],
           else: []
      end)
      |> Map.new()

    quote generated: true do
      @impl Jido.Flow
      def flow, do: unquote(escaped_flow)
      def __jido_flow_source_map__, do: unquote(escaped_source_map)

      @__jido_inline_generated__ {:step_action, 1}
      def step_action(name) do
        with {:ok, normalized} <- Jido.Flow.DSL.Name.normalize(name),
             {:ok, action} <- Map.fetch(unquote(Macro.escape(step_actions)), normalized) do
          action
        else
          _other ->
            raise ArgumentError,
                  "expected an Action-backed Step name in #{inspect(__MODULE__)}, got: #{inspect(name)}"
        end
      end

      Module.delete_attribute(__MODULE__, :__jido_inline_generated__)
    end
  end

  defp build_flow!(env, config) do
    case Builder.build(env.module, config, env.file) do
      {:ok, flow, source_map} -> {flow, source_map}
      {:error, error} -> raise_compile_error!(env, error)
    end
  end

  defp raise_compile_error!(env, error) do
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

  defp validate_module_config(%{} = options) when not is_struct(options) do
    case options |> Map.keys() |> Kernel.--(@module_config_fields) |> Enum.sort() do
      [] ->
        with :ok <- validate_identifier(options.id),
             :ok <- validate_vsn(options.vsn),
             {:ok, config} <- FlowConfig.validate(Map.take(options, @config_fields)) do
          {:ok, Map.merge(config, Map.take(options, [:id, :vsn]))}
        end

      [key | _rest] ->
        {:error,
         Error.validation_error("unknown Flow configuration key: #{inspect(key)}", %{key: key})}
    end
  end

  defp validate_module_config(_options),
    do: {:error, Error.validation_error("flow configuration must be a map")}

  defp validate_identifier(value) do
    case Registry.validate_identifier(value) do
      :ok ->
        :ok

      {:error, _error} ->
        {:error, Error.validation_error("id must be a valid authoring identifier")}
    end
  end

  defp validate_vsn(value) do
    case Registry.validate_vsn(value) do
      :ok -> :ok
      {:error, _error} -> {:error, Error.validation_error("vsn must be a positive integer")}
    end
  end

  defp normalize_options(raw_options) when is_list(raw_options) do
    if Keyword.keyword?(raw_options), do: Map.new(raw_options), else: raw_options
  end

  defp normalize_options(raw_options), do: raw_options

  defp module_defaults(%{} = options, module) when not is_struct(options) do
    options
    |> Map.put_new(:id, Atom.to_string(module))
    |> Map.put_new(:vsn, 1)
  end

  defp module_defaults(options, _module), do: options

  defp ensure_escapable_schema!(schema, option, env) do
    Macro.escape(schema)
    schema
  rescue
    ArgumentError ->
      raise CompileError,
        description:
          "#{inspect(option)} must be static module data that can be stored in the Flow module. " <>
            "Use named MFA effects such as {Module, :function, args}",
        file: env.file,
        line: env.line
  end
end
