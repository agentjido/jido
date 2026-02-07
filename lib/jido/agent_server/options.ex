defmodule Jido.AgentServer.Options do
  @moduledoc """
  Options for starting an AgentServer.

  > #### Internal Module {: .warning}
  > This module is internal to the AgentServer implementation. Its API may
  > change without notice.

  Validates and normalizes startup options including agent configuration,
  hierarchy settings, error policies, and dispatch configuration.
  """

  alias Jido.AgentServer.ParentRef

  @type error_policy ::
          :log_only
          | :stop_on_error
          | {:emit_signal, dispatch_cfg :: term()}
          | {:max_errors, pos_integer()}
          | (error :: term(), state :: map() -> {:ok, map()} | {:stop, term(), map()})

  @type on_parent_death :: :stop | :continue | :emit_orphan

  @schema Zoi.struct(
            __MODULE__,
            %{
              agent: Zoi.any(description: "Agent module (atom) or instantiated agent struct"),
              agent_module:
                Zoi.atom(description: "Agent module for pre-built structs") |> Zoi.optional(),
              jido:
                Zoi.atom(description: "Jido instance name for registry scoping (default: Jido)")
                |> Zoi.optional(),
              id:
                Zoi.string(description: "Instance ID (auto-generated if not provided)")
                |> Zoi.optional(),
              initial_state: Zoi.map(description: "Initial agent state") |> Zoi.default(%{}),
              registry: Zoi.atom(description: "Registry module") |> Zoi.default(Jido.Registry),
              default_dispatch:
                Zoi.any(description: "Default dispatch config for Emit directives")
                |> Zoi.optional(),
              error_policy:
                Zoi.any(description: "Error handling policy") |> Zoi.default(:log_only),
              max_queue_size:
                Zoi.integer(description: "Max directive queue size")
                |> Zoi.min(1)
                |> Zoi.default(10_000),
              parent: Zoi.any(description: "Parent reference for hierarchy") |> Zoi.optional(),
              on_parent_death:
                Zoi.atom(description: "Behavior when parent dies")
                |> Zoi.default(:stop),
              spawn_fun:
                Zoi.any(description: "Custom function for spawning children") |> Zoi.optional(),
              skip_schedules:
                Zoi.boolean(description: "Skip registering plugin schedules (useful for tests)")
                |> Zoi.default(false),

              # InstanceManager integration (set by Jido.Agent.InstanceManager)
              lifecycle_mod:
                Zoi.atom(description: "Lifecycle module implementing Jido.AgentServer.Lifecycle")
                |> Zoi.default(Jido.AgentServer.Lifecycle.Noop),
              pool:
                Zoi.atom(description: "Manager name if started via Jido.Agent.InstanceManager")
                |> Zoi.optional(),
              pool_key:
                Zoi.any(description: "Manager key if started via Jido.Agent.InstanceManager")
                |> Zoi.optional(),
              idle_timeout:
                Zoi.any(
                  description: "Idle timeout in ms before hibernate/stop (:infinity to disable)"
                )
                |> Zoi.default(:infinity),
              persistence:
                Zoi.any(description: "Persistence config [store: {Module, opts}]")
                |> Zoi.optional(),

              # Debug mode
              debug:
                Zoi.boolean(description: "Enable debug mode with event buffer")
                |> Zoi.default(false)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Creates validated Options from a keyword list or map.

  Normalizes and validates all options, including:
  - Generating an ID if not provided
  - Validating the agent module/struct
  - Validating error policy
  - Parsing parent reference

  Returns `{:ok, options}` or `{:error, reason}`.
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    opts |> Map.new() |> new()
  end

  def new(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, _} <- validate_agent(attrs[:agent]),
         {:ok, _} <- validate_error_policy(attrs[:error_policy]),
         {:ok, parent} <- validate_parent(attrs[:parent]) do
      attrs = Map.put(attrs, :parent, parent)
      Zoi.parse(@schema, attrs)
    end
  end

  def new(_), do: {:error, Jido.Error.validation_error("Options requires a keyword list or map")}

  @doc """
  Creates validated Options from a keyword list or map, raising on error.
  """
  @spec new!(keyword() | map()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, options} -> options
      {:error, reason} -> raise Jido.Error.validation_error("Invalid Options", details: reason)
    end
  end

  # Normalize attributes with defaults
  defp normalize_attrs(attrs) do
    id =
      case Map.get(attrs, :id) do
        nil -> extract_agent_id(attrs[:agent]) || Jido.Util.generate_id()
        "" -> extract_agent_id(attrs[:agent]) || Jido.Util.generate_id()
        id when is_binary(id) -> id
        id when is_atom(id) -> Atom.to_string(id)
      end

    jido_instance = Map.get(attrs, :jido, Jido)
    registry = Jido.registry_name(jido_instance)
    attrs = Map.put(attrs, :jido, jido_instance)

    attrs
    |> Map.put(:id, id)
    |> Map.put(:registry, registry)
  end

  defp extract_agent_id(%{id: id}) when is_binary(id) and id != "", do: id
  defp extract_agent_id(_), do: nil

  defp validate_agent(nil), do: {:error, Jido.Error.validation_error("agent is required")}

  defp validate_agent(agent) when is_atom(agent) do
    case Code.ensure_loaded(agent) do
      {:module, _} ->
        if function_exported?(agent, :new, 0) or function_exported?(agent, :new, 1) or
             function_exported?(agent, :new, 2) do
          {:ok, agent}
        else
          {:error,
           Jido.Error.validation_error("agent module must implement new/0, new/1, or new/2")}
        end

      {:error, _} ->
        {:error, Jido.Error.validation_error("agent module not found: #{inspect(agent)}")}
    end
  end

  defp validate_agent(%{__struct__: _} = agent), do: {:ok, agent}

  defp validate_agent(_),
    do: {:error, Jido.Error.validation_error("agent must be a module or struct")}

  @doc """
  Validates an error policy value.
  """
  @spec validate_error_policy(term()) :: {:ok, error_policy()} | {:error, term()}
  def validate_error_policy(nil), do: {:ok, :log_only}
  def validate_error_policy(:log_only), do: {:ok, :log_only}
  def validate_error_policy(:stop_on_error), do: {:ok, :stop_on_error}
  def validate_error_policy({:emit_signal, _cfg} = policy), do: {:ok, policy}

  def validate_error_policy({:max_errors, n} = policy) when is_integer(n) and n > 0,
    do: {:ok, policy}

  def validate_error_policy(fun) when is_function(fun, 2), do: {:ok, fun}

  def validate_error_policy(other) do
    {:error, Jido.Error.validation_error("invalid error_policy: #{inspect(other)}")}
  end

  defp validate_parent(nil), do: {:ok, nil}

  defp validate_parent(%ParentRef{} = parent), do: {:ok, parent}

  defp validate_parent(attrs) when is_map(attrs) do
    ParentRef.new(attrs)
  end

  defp validate_parent(_) do
    {:error, Jido.Error.validation_error("parent must be nil or a ParentRef")}
  end
end
