defmodule Jido.AI.ToolSource do
  @moduledoc """
  Defines the runtime extension point for dynamic AI tools.

  An Agent's declared Actions remain its protected static Toolset. Trusted
  execution hosts can add dynamic sources in the Action context:

      %{
        jido_ai_tool_sources: [
          MyApp.ToolSource,
          {Jido.Connect.ToolSource, %{server: "docs"}}
        ]
      }

  A source lists model tool definitions and executes calls for those tools.
  Source specifications and returned definitions must be portable because a
  durable Agent turn can store them. Request data cannot add tool sources.
  The normal request tool policy can only reduce the combined tool set.
  """

  @typedoc "A portable source module with optional portable configuration."
  @type spec :: module() | {module(), term()}

  @typedoc "A ReqLLM tool or the fields needed to build one."
  @type definition ::
          ReqLLM.Tool.t()
          | %{
              required(:name) => String.t(),
              optional(:description) => String.t(),
              optional(:parameter_schema) => keyword() | map(),
              optional(:strict) => boolean(),
              optional(:provider_options) => keyword() | map()
            }

  @typedoc "A portable dynamic tool loaded from a source."
  @type tool :: %{
          required(:kind) => :source,
          required(:name) => String.t(),
          required(:description) => String.t(),
          required(:parameter_schema) => keyword() | map(),
          required(:strict) => boolean(),
          required(:provider_options) => keyword() | map(),
          required(:source) => %{module: module(), config: term()}
        }

  @typedoc "The portable tool call passed to a source."
  @type call :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:arguments) => map()
        }

  @callback list_tools(config :: term(), context :: map()) ::
              {:ok, [definition()]} | {:error, term()}

  @callback run_tool(call(), config :: term(), context :: map()) ::
              {:ok, term()}
              | {:ok, term(), [term()]}
              | {:error, term()}
              | {:error, term(), [term()]}

  @doc "Returns dynamic source specifications from the trusted execution context."
  @spec from_context(map()) :: [spec()]
  def from_context(context) when is_map(context) do
    case Map.get(context, :jido_ai_tool_sources, []) do
      sources when is_list(sources) -> sources
      _other -> []
    end
  end

  @doc "Loads and validates all tools from the trusted execution context."
  @spec load(map()) :: {:ok, [tool()]} | {:error, term()}
  def load(context) when is_map(context) do
    case Map.get(context, :jido_ai_tool_sources, []) do
      sources when is_list(sources) -> load_sources(sources, context)
      _other -> {:error, :invalid_tool_sources}
    end
  end

  @doc "Executes one resolved dynamic tool call through its source."
  @spec run(map(), call(), map()) ::
          {:ok, term()} | {:ok, term(), [term()]} | {:error, term()}
  def run(%{kind: :source, module: module, config: config}, call, context)
      when is_atom(module) and is_map(call) and is_map(context) do
    invoke_source(module, call, config, context)
  end

  @doc false
  @spec validate_input(tool(), map()) :: {:ok, map()} | {:error, term()}
  def validate_input(%{kind: :source} = tool, arguments) when is_map(arguments) do
    with {:ok, definition} <- definition(tool) do
      ReqLLM.Tool.validate_input(definition, arguments)
    end
  end

  @doc false
  @spec identity(tool()) :: map()
  def identity(%{kind: :source, name: name, source: %{module: module}}) do
    %{kind: :source, name: name, source: Atom.to_string(module)}
  end

  @doc false
  @spec executor(tool()) :: map()
  def executor(%{kind: :source, source: source}), do: Map.put(source, :kind, :source)

  @doc false
  @spec definition(tool()) :: {:ok, ReqLLM.Tool.t()} | {:error, term()}
  def definition(%{kind: :source} = tool), do: build_definition(tool)

  @doc false
  @spec execution_boundary(map()) :: {:error, atom()}
  def execution_boundary(_arguments), do: {:error, :tool_must_run_in_agent_graph}

  defp load_source(source, context) do
    with :ok <- portable_source(source),
         {:ok, module, config} <- normalize_source(source),
         :ok <- source_module(module),
         {:ok, definitions} <- module.list_tools(config, context),
         {:ok, tools} <- normalize_definitions(definitions, module, config) do
      {:ok, tools}
    else
      {:error, _reason} = error -> error
      other -> {:error, {:invalid_tool_source_result, source_module_name(source), other}}
    end
  rescue
    error -> {:error, {:tool_source_failed, source_module_name(source), Exception.message(error)}}
  catch
    kind, reason -> {:error, {:tool_source_failed, source_module_name(source), {kind, reason}}}
  end

  defp load_sources(sources, context) do
    Enum.reduce_while(sources, {:ok, []}, fn source, {:ok, tools} ->
      case load_source(source, context) do
        {:ok, loaded} -> {:cont, {:ok, tools ++ loaded}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_definitions(definitions, module, config) when is_list(definitions) do
    if List.improper?(definitions) do
      {:error, :invalid_tool_source_definitions}
    else
      definitions
      |> Enum.reduce_while({:ok, []}, fn definition, {:ok, tools} ->
        case normalize_definition(definition, module, config) do
          {:ok, normalized} -> {:cont, {:ok, [normalized | tools]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, tools} -> {:ok, Enum.reverse(tools)}
        error -> error
      end
    end
  end

  defp normalize_definitions(_definitions, _module, _config),
    do: {:error, :invalid_tool_source_definitions}

  defp normalize_definition(%ReqLLM.Tool{} = definition, module, config) do
    definition
    |> portable_tool(module, config)
    |> validate_runtime_tool()
  end

  defp normalize_definition(definition, module, config) when is_map(definition) do
    with {:ok, normalized} <- build_definition(definition) do
      normalized
      |> portable_tool(module, config)
      |> validate_runtime_tool()
    end
  end

  defp normalize_definition(_definition, _module, _config),
    do: {:error, :invalid_tool_source_definition}

  defp portable_tool(definition, module, config) do
    %{
      kind: :source,
      name: definition.name,
      description: definition.description,
      parameter_schema: definition.parameter_schema,
      strict: definition.strict,
      provider_options: definition.provider_options,
      source: %{module: module, config: config}
    }
  end

  defp build_definition(definition) do
    ReqLLM.Tool.new(
      name: field(definition, :name),
      description: field(definition, :description) || "",
      parameter_schema: field(definition, :parameter_schema) || [],
      callback: {__MODULE__, :execution_boundary},
      strict: field(definition, :strict) != false,
      provider_options: field(definition, :provider_options) || %{}
    )
  end

  defp invoke_source(module, call, config, context) do
    case module.run_tool(call, config, context) do
      {:ok, value} ->
        {:ok, value}

      {:ok, value, effects} when is_list(effects) ->
        if List.improper?(effects),
          do: {:error, :invalid_tool_source_effects},
          else: {:ok, value, effects}

      {:error, reason} ->
        {:error, reason}

      {:error, reason, _effects} ->
        {:error, reason}

      other ->
        {:error, {:invalid_tool_source_result, other}}
    end
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp normalize_source(module) when is_atom(module) and module not in [nil, true, false],
    do: {:ok, module, %{}}

  defp normalize_source({module, config})
       when is_atom(module) and module not in [nil, true, false],
       do: {:ok, module, config}

  defp normalize_source(_source), do: {:error, :invalid_tool_source}

  defp source_module(module) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :list_tools, 2),
         true <- function_exported?(module, :run_tool, 3) do
      :ok
    else
      _other -> {:error, {:invalid_tool_source, module}}
    end
  end

  defp portable_source(source) do
    with :ok <- portable_term(source), do: canonical_term(source, :invalid_tool_source_config)
  end

  defp portable_term(source) do
    case Jido.PortableTerm.validate(source, :tool_source) do
      :ok -> :ok
      {:error, path} -> {:error, {:nonportable_tool_source, path}}
    end
  end

  defp validate_runtime_tool(tool) do
    with :ok <- portable_term(tool),
         :ok <- canonical_term(tool, :invalid_tool_source_definition) do
      {:ok, tool}
    end
  end

  defp canonical_term(term, reason) do
    Runic.Identity.Canonical.encode!(term)
    :ok
  rescue
    _error -> {:error, reason}
  end

  defp source_module_name(module) when is_atom(module), do: module
  defp source_module_name({module, _config}) when is_atom(module), do: module
  defp source_module_name(_source), do: :unknown

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
