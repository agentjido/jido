defmodule Jido.AgentServer.Options do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Error
  alias Jido.AgentServer.ParentRef

  @default_max_postponed_signals 1_000
  @default_turn_timeout 5_000
  @default_directive_timeout 5_000
  @default_readiness_timeout 5_000

  @schema Zoi.struct(
            __MODULE__,
            %{
              agent: Zoi.any(description: "Validated Agent value"),
              name: Zoi.any(description: "Optional OTP process name") |> Zoi.optional(),
              jido: Zoi.any(description: "Optional Jido instance") |> Zoi.optional(),
              partition: Zoi.any(description: "Logical Agent partition") |> Zoi.optional(),
              registry: Zoi.any(description: "Optional Registry") |> Zoi.optional(),
              register:
                Zoi.boolean(description: "Register this Agent by id") |> Zoi.default(false),
              exec_module:
                Zoi.atom(description: "Executable runtime module") |> Zoi.default(Jido.Exec),
              exec_opts: Zoi.any(description: "Executable runtime options") |> Zoi.default([]),
              max_postponed_signals:
                Zoi.any(description: "Postponed Signal admission limit")
                |> Zoi.default(@default_max_postponed_signals),
              turn_timeout:
                Zoi.any(description: "Pre-commit Turn timeout")
                |> Zoi.default(@default_turn_timeout),
              max_directives_per_turn:
                Zoi.any(description: "Directive count limit") |> Zoi.default(:infinity),
              directive_timeout:
                Zoi.any(description: "Plugin and external Directive timeout")
                |> Zoi.default(@default_directive_timeout),
              readiness_timeout:
                Zoi.integer(description: "Plugin runtime readiness timeout")
                |> Zoi.default(@default_readiness_timeout),
              default_dispatch:
                Zoi.any(description: "Default outbound Signal dispatch") |> Zoi.optional(),
              error_policy:
                Zoi.any(description: "Agent Server error policy") |> Zoi.default(:log_only),
              parent: Zoi.any(description: "Optional logical parent") |> Zoi.optional(),
              on_parent_death: Zoi.atom(description: "Parent death policy") |> Zoi.default(:stop),
              spawn_fun:
                Zoi.any(description: "Optional process spawn function") |> Zoi.optional(),
              pool: Zoi.atom(description: "Owning Agent InstanceManager") |> Zoi.optional(),
              pool_key: Zoi.any(description: "Agent InstanceManager key") |> Zoi.optional(),
              idle_timeout:
                Zoi.any(description: "Idle timeout in milliseconds") |> Zoi.default(:infinity),
              persistence:
                Zoi.any(description: "Optional Agent persistence adapter") |> Zoi.optional(),
              restore:
                Zoi.any(description: "Persisted Agent restore policy") |> Zoi.default(:if_found),
              state_version:
                Zoi.integer(description: "Initial Agent commit revision")
                |> Zoi.default(0),
              debug:
                Zoi.boolean(description: "Enable the Agent event buffer") |> Zoi.default(false),
              debug_max_events:
                Zoi.integer(description: "Maximum event count") |> Zoi.default(500)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc false
  def new(opts) when is_list(opts) do
    if Keyword.keyword?(opts),
      do: opts |> Map.new() |> new(),
      else: invalid("options must be a keyword list")
  end

  def new(%{} = attrs) do
    with :ok <- validate_identity_options(attrs),
         :ok <-
           reject_option(
             attrs,
             :directive_handler,
             "does not support custom Directive handlers; use an Agent Plugin"
           ),
         {:ok, agent} <- build_agent(attrs),
         {:ok, parent} <- build_parent(Map.get(attrs, :parent)),
         :ok <- validate_registration(attrs),
         :ok <- validate_parent_policy(Map.get(attrs, :on_parent_death, :stop)),
         :ok <- validate_spawn_fun(Map.get(attrs, :spawn_fun)),
         :ok <- validate_error_policy(Map.get(attrs, :error_policy, :log_only)),
         {:ok, default_dispatch} <-
           normalize_default_dispatch(Map.get(attrs, :default_dispatch)),
         {:ok, persistence} <- resolve_persistence(attrs),
         :ok <- validate_restore(Map.get(attrs, :restore, :if_found)),
         :ok <- validate_state_version(Map.get(attrs, :state_version, 0)),
         :ok <- validate_debug(Map.get(attrs, :debug, false)),
         :ok <- validate_debug_max_events(Map.get(attrs, :debug_max_events, 500)),
         :ok <-
           validate_timeout(Map.get(attrs, :turn_timeout, @default_turn_timeout), :turn_timeout),
         :ok <-
           validate_timeout(
             Map.get(attrs, :directive_timeout, @default_directive_timeout),
             :directive_timeout
           ),
         :ok <-
           validate_timeout(
             Map.get(attrs, :readiness_timeout, @default_readiness_timeout),
             :readiness_timeout
           ),
         :ok <- validate_lifecycle(attrs),
         :ok <-
           reject_option(
             attrs,
             :cron_specs,
             "does not support cron_specs; use Jido.Plugin.Scheduler"
           ) do
      jido = Map.get(attrs, :jido)
      register = Map.get(attrs, :register, not is_nil(jido))

      normalized =
        attrs
        |> Map.take(Map.keys(%__MODULE__{agent: nil}) -- [:__struct__])
        |> Map.merge(%{
          agent: agent,
          registry: Map.get(attrs, :registry, registry(jido)),
          register: register,
          default_dispatch: default_dispatch,
          parent: parent,
          persistence: persistence
        })

      Zoi.parse(@schema, normalized)
    end
  end

  def new(_value), do: invalid("options must be a map or keyword list")

  defp reject_option(attrs, field, message) do
    if Map.has_key?(attrs, field), do: invalid(message), else: :ok
  end

  defp build_agent(attrs) do
    agent = Map.get(attrs, :agent)
    id = Map.get(attrs, :id)
    initial_state = Map.get(attrs, :initial_state)

    with {:ok, agent} <- instantiate_agent(agent, id, initial_state) do
      Agent.validate_instance(agent)
    end
  end

  defp instantiate_agent(%Agent{id: nil, state: nil} = definition, id, initial_state) do
    Agent.instantiate(definition, instance_overrides(id, initial_state))
  end

  defp instantiate_agent(%Agent{id: id, state: state} = agent, requested_id, initial_state)
       when is_binary(id) and is_map(state) and not is_struct(state) do
    with {:ok, agent} <- Agent.validate_instance(agent) do
      if is_nil(requested_id) and is_nil(initial_state) do
        {:ok, agent}
      else
        invalid("cannot override an Agent instance with Server options", %{
          agent_id: agent.id,
          id: requested_id,
          initial_state: initial_state
        })
      end
    end
  end

  defp instantiate_agent(%Agent{} = agent, _id, _initial_state), do: Agent.validate(agent)

  defp instantiate_agent(module, id, initial_state) when is_atom(module) and not is_nil(module) do
    overrides = instance_overrides(id, initial_state)

    with {:module, ^module} <- Code.ensure_loaded(module) do
      result =
        cond do
          function_exported?(module, :__agent_config__, 0) ->
            Agent.instantiate(module, overrides)

          function_exported?(module, :new, 1) ->
            module.new(overrides)

          function_exported?(module, :new, 0) ->
            module.new()

          true ->
            invalid("Agent module must implement new/0 or new/1", %{module: module})
        end

      with {:ok, agent} <- normalize_agent_result(result, module),
           :ok <- validate_requested_id(agent, id, module) do
        {:ok, agent}
      end
    else
      {:error, reason} ->
        invalid("Agent module could not be loaded", %{module: module, reason: reason})
    end
  rescue
    error -> constructor_failed(module, :error, error)
  catch
    kind, reason -> constructor_failed(module, kind, reason)
  end

  defp instantiate_agent(value, _id, _initial_state),
    do: invalid("agent is required", %{agent: value})

  defp normalize_agent_result({:ok, %Agent{} = agent}, _module), do: {:ok, agent}
  defp normalize_agent_result(%Agent{} = agent, _module), do: {:ok, agent}
  defp normalize_agent_result({:error, reason}, _module), do: {:error, reason}

  defp normalize_agent_result(value, module),
    do: invalid("Agent constructor returned an invalid value", %{module: module, value: value})

  defp instance_overrides(id, initial_state) do
    []
    |> maybe_put(:id, id)
    |> maybe_put(:state, initial_state)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp build_parent(nil), do: {:ok, nil}
  defp build_parent(parent), do: ParentRef.new(parent)

  defp validate_requested_id(_agent, nil, _module), do: :ok
  defp validate_requested_id(%Agent{id: id}, id, _module), do: :ok

  defp validate_requested_id(%Agent{id: actual}, expected, module) do
    invalid("Agent constructor ignored the requested id", %{
      module: module,
      expected_id: expected,
      actual_id: actual
    })
  end

  defp constructor_failed(module, kind, reason) do
    invalid("Agent constructor failed", %{module: module, kind: kind, reason: reason})
  end

  defp validate_identity_options(attrs) do
    with :ok <- validate_optional_atom(Map.get(attrs, :jido), :jido),
         :ok <- validate_optional_atom(Map.get(attrs, :registry), :registry),
         :ok <- validate_name(Map.get(attrs, :name)) do
      :ok
    end
  end

  defp validate_optional_atom(nil, _field), do: :ok

  defp validate_optional_atom(value, _field) when is_atom(value) and not is_nil(value), do: :ok

  defp validate_optional_atom(value, field) do
    invalid("#{field} must be an atom or nil", %{field => value})
  end

  defp validate_name(nil), do: :ok
  defp validate_name(name) when is_atom(name) and not is_nil(name), do: :ok
  defp validate_name({:global, _term}), do: :ok

  defp validate_name({:via, module, _term}) when is_atom(module) and not is_nil(module),
    do: :ok

  defp validate_name(name), do: invalid("name is invalid", %{name: name})

  defp validate_registration(attrs) do
    register = Map.get(attrs, :register, not is_nil(Map.get(attrs, :jido)))
    registry = Map.get(attrs, :registry, registry(Map.get(attrs, :jido)))

    cond do
      not is_boolean(register) ->
        invalid("register must be a boolean", %{register: register})

      register and not is_nil(Map.get(attrs, :name)) ->
        invalid("name and register: true cannot be used together", %{
          name: Map.get(attrs, :name),
          register: register
        })

      register and (not is_atom(registry) or is_nil(registry)) ->
        invalid("register: true requires an Agent Registry", %{
          registry: registry,
          register: register
        })

      true ->
        :ok
    end
  end

  defp validate_parent_policy(policy) when policy in [:stop, :continue, :emit_orphan], do: :ok

  defp validate_parent_policy(policy),
    do: invalid("on_parent_death is invalid", %{on_parent_death: policy})

  defp validate_spawn_fun(nil), do: :ok
  defp validate_spawn_fun(fun) when is_function(fun, 1), do: :ok
  defp validate_spawn_fun(fun), do: invalid("spawn_fun must have arity 1", %{spawn_fun: fun})

  defp validate_error_policy(policy)
       when policy in [:log_only, :stop_on_error],
       do: :ok

  defp validate_error_policy({:max_errors, count}) when is_integer(count) and count > 0, do: :ok

  defp validate_error_policy({:emit_signal, nil}) do
    invalid("emit_signal error policy requires an external dispatch target", %{
      error_policy: {:emit_signal, nil}
    })
  end

  defp validate_error_policy({:emit_signal, dispatch}) do
    case Jido.Signal.Dispatch.validate_opts(dispatch) do
      {:ok, _dispatch} -> :ok
      {:error, reason} -> invalid("emit_signal dispatch is invalid", %{reason: reason})
    end
  end

  defp validate_error_policy(fun) when is_function(fun, 2), do: :ok

  defp validate_error_policy(policy),
    do: invalid("error_policy is invalid", %{error_policy: policy})

  defp normalize_default_dispatch(nil), do: {:ok, nil}

  defp normalize_default_dispatch(dispatch) do
    case Jido.Signal.Dispatch.validate_opts(dispatch) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, reason} -> invalid("default_dispatch is invalid", %{reason: reason})
    end
  rescue
    error -> invalid("default_dispatch is invalid", %{reason: error})
  catch
    kind, reason -> invalid("default_dispatch is invalid", %{reason: {kind, reason}})
  end

  defp validate_timeout(:infinity, field) when field != :readiness_timeout, do: :ok
  defp validate_timeout(timeout, _field) when is_integer(timeout) and timeout > 0, do: :ok

  defp validate_timeout(timeout, field) do
    requirement =
      if field == :readiness_timeout,
        do: "a positive integer",
        else: ":infinity or a positive integer"

    invalid("#{field} must be #{requirement}", %{field => timeout})
  end

  defp validate_lifecycle(attrs) do
    pool = Map.get(attrs, :pool)

    if not is_nil(pool) and not is_atom(pool) do
      invalid("pool must be an atom", %{pool: pool})
    else
      validate_timeout(Map.get(attrs, :idle_timeout, :infinity), :idle_timeout)
    end
  end

  defp resolve_persistence(attrs) do
    config =
      if Map.has_key?(attrs, :persistence),
        do: Map.get(attrs, :persistence),
        else: :inherit

    case Jido.Persistence.resolve_config(config, Map.get(attrs, :jido)) do
      {:ok, persistence} ->
        {:ok, persistence}

      {:error, reason} ->
        invalid("persistence adapter is invalid", %{reason: reason})
    end
  end

  defp validate_restore(restore) when restore in [false, :if_found, :required], do: :ok

  defp validate_restore(restore) do
    invalid("restore must be false, :if_found, or :required", %{restore: restore})
  end

  defp validate_state_version(version) when is_integer(version) and version >= 0, do: :ok

  defp validate_state_version(version) do
    invalid("state_version must be a non-negative integer", %{state_version: version})
  end

  defp validate_debug(debug) when is_boolean(debug), do: :ok
  defp validate_debug(debug), do: invalid("debug must be a boolean", %{debug: debug})

  defp validate_debug_max_events(limit) when is_integer(limit) and limit > 0, do: :ok

  defp validate_debug_max_events(limit) do
    invalid("debug_max_events must be a positive integer", %{debug_max_events: limit})
  end

  defp registry(nil), do: nil
  defp registry(jido), do: Jido.registry_name(jido)

  defp invalid(message, details \\ %{}) do
    {:error,
     Jido.Error.validation_error("Agent Server #{message}", kind: :config, details: details)}
  end

  def validate_exec_module(module) when is_atom(module) do
    required = [run_async: 4, handle_message: 2, cancel: 1]

    with {:module, ^module} <- Code.ensure_loaded(module),
         true <-
           Enum.all?(required, fn {name, arity} -> function_exported?(module, name, arity) end) do
      {:ok, module}
    else
      _reason ->
        {:error,
         Error.validation_error("Agent Server Exec module has an invalid contract",
           kind: :config,
           details: %{module: module}
         )}
    end
  end

  def validate_exec_module(module) do
    {:error,
     Error.validation_error("Agent Server Exec module must be a module",
       kind: :config,
       details: %{module: module}
     )}
  end

  def validate_keyword(value, _field) when is_list(value) and value == [], do: {:ok, value}

  def validate_keyword(value, field) when is_list(value) do
    if Keyword.keyword?(value) do
      {:ok, value}
    else
      {:error, Error.validation_error("#{field} must be a keyword list", field: field)}
    end
  end

  def validate_keyword(_value, field) do
    {:error, Error.validation_error("#{field} must be a keyword list", field: field)}
  end

  def validate_limit(:infinity, _field), do: {:ok, :infinity}
  def validate_limit(value, _field) when is_integer(value) and value >= 0, do: {:ok, value}

  def validate_limit(value, field) do
    {:error,
     Error.validation_error("#{field} must be :infinity or a non-negative integer",
       field: field,
       details: %{value: value}
     )}
  end
end
