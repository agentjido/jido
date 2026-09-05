defmodule Jido.AgentServer.Options do
  @moduledoc false

  alias Jido.Agent
  alias Jido.AgentServer.ParentRef

  @default_max_postponed_signals 1_000
  @default_directive_timeout 5_000

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
              max_directives_per_turn:
                Zoi.any(description: "Directive count limit") |> Zoi.default(:infinity),
              directive_timeout:
                Zoi.any(description: "Plugin and external Directive timeout")
                |> Zoi.default(@default_directive_timeout),
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
    with :ok <- reject_custom_directive_handler(attrs),
         {:ok, agent} <- build_agent(attrs),
         {:ok, parent} <- build_parent(Map.get(attrs, :parent)),
         :ok <- validate_registration(attrs),
         :ok <- validate_parent_policy(Map.get(attrs, :on_parent_death, :stop)),
         :ok <- validate_spawn_fun(Map.get(attrs, :spawn_fun)),
         :ok <- validate_error_policy(Map.get(attrs, :error_policy, :log_only)),
         {:ok, persistence} <- resolve_persistence(attrs),
         :ok <- validate_restore(Map.get(attrs, :restore, :if_found)),
         :ok <- validate_state_version(Map.get(attrs, :state_version, 0)),
         :ok <-
           validate_directive_timeout(
             Map.get(attrs, :directive_timeout, @default_directive_timeout)
           ),
         :ok <- validate_lifecycle(attrs),
         :ok <- reject_native_scheduler(attrs) do
      jido = Map.get(attrs, :jido)
      register = Map.get(attrs, :register, not is_nil(jido))

      normalized = %{
        agent: agent,
        name: Map.get(attrs, :name),
        jido: jido,
        partition: Map.get(attrs, :partition),
        registry: Map.get(attrs, :registry, registry(jido)),
        register: register,
        exec_module: Map.get(attrs, :exec_module, Jido.Exec),
        exec_opts: Map.get(attrs, :exec_opts, []),
        max_postponed_signals:
          Map.get(attrs, :max_postponed_signals, @default_max_postponed_signals),
        max_directives_per_turn: Map.get(attrs, :max_directives_per_turn, :infinity),
        directive_timeout: Map.get(attrs, :directive_timeout, @default_directive_timeout),
        default_dispatch: Map.get(attrs, :default_dispatch),
        error_policy: Map.get(attrs, :error_policy, :log_only),
        parent: parent,
        on_parent_death: Map.get(attrs, :on_parent_death, :stop),
        spawn_fun: Map.get(attrs, :spawn_fun),
        pool: Map.get(attrs, :pool),
        pool_key: Map.get(attrs, :pool_key),
        idle_timeout: Map.get(attrs, :idle_timeout, :infinity),
        persistence: persistence,
        restore: Map.get(attrs, :restore, :if_found),
        state_version: Map.get(attrs, :state_version, 0),
        debug: Map.get(attrs, :debug, false),
        debug_max_events: Map.get(attrs, :debug_max_events, 500)
      }

      Zoi.parse(@schema, normalized)
    end
  end

  def new(_value), do: invalid("options must be a map or keyword list")

  defp reject_custom_directive_handler(attrs) do
    if Map.has_key?(attrs, :directive_handler) do
      invalid("does not support custom Directive handlers; use an Agent Plugin")
    else
      :ok
    end
  end

  defp reject_native_scheduler(attrs) do
    if Map.has_key?(attrs, :cron_specs) do
      invalid("does not support cron_specs; use Jido.Plugin.Scheduler")
    else
      :ok
    end
  end

  defp build_agent(attrs) do
    agent = Map.get(attrs, :agent)
    id = Map.get(attrs, :id)
    initial_state = Map.get(attrs, :initial_state)

    with {:ok, agent} <- instantiate_agent(agent, id, initial_state) do
      Agent.validate_instance(agent)
    end
  end

  defp instantiate_agent(%Agent{} = agent, id, initial_state) do
    cond do
      Agent.definition?(agent) ->
        Agent.instantiate(agent, instance_overrides(id, initial_state))

      Agent.instance?(agent) and is_nil(id) and is_nil(initial_state) ->
        {:ok, agent}

      Agent.instance?(agent) ->
        invalid("cannot override an Agent instance with Server options", %{
          agent_id: agent.id,
          id: id,
          initial_state: initial_state
        })

      true ->
        Agent.validate(agent)
    end
  end

  defp instantiate_agent(module, id, initial_state) when is_atom(module) and not is_nil(module) do
    overrides = instance_overrides(id, initial_state)

    with {:module, ^module} <- Code.ensure_loaded(module) do
      cond do
        function_exported?(module, :new, 1) ->
          normalize_agent_result(module.new(overrides), module)

        function_exported?(module, :new, 0) ->
          normalize_agent_result(module.new(), module)

        true ->
          invalid("Agent module must implement new/0 or new/1", %{module: module})
      end
    else
      {:error, reason} ->
        invalid("Agent module could not be loaded", %{module: module, reason: reason})
    end
  rescue
    error -> {:error, error}
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
  defp build_parent(%ParentRef{} = parent), do: {:ok, parent}
  defp build_parent(parent), do: ParentRef.new(parent)

  defp validate_registration(attrs) do
    register = Map.get(attrs, :register, not is_nil(Map.get(attrs, :jido)))
    registry = Map.get(attrs, :registry, registry(Map.get(attrs, :jido)))

    cond do
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

  defp validate_directive_timeout(:infinity), do: :ok

  defp validate_directive_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok

  defp validate_directive_timeout(timeout) do
    invalid("directive_timeout must be :infinity or a positive integer", %{
      directive_timeout: timeout
    })
  end

  defp validate_lifecycle(attrs) do
    pool = Map.get(attrs, :pool)
    idle_timeout = Map.get(attrs, :idle_timeout, :infinity)

    cond do
      not is_nil(pool) and not is_atom(pool) ->
        invalid("pool must be an atom", %{pool: pool})

      idle_timeout == :infinity ->
        :ok

      is_integer(idle_timeout) and idle_timeout > 0 ->
        :ok

      true ->
        invalid("idle_timeout must be :infinity or a positive integer", %{
          idle_timeout: idle_timeout
        })
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

  defp registry(nil), do: nil
  defp registry(jido), do: Jido.registry_name(jido)

  defp invalid(message, details \\ %{}) do
    {:error,
     Jido.Error.validation_error("Agent Server #{message}", kind: :config, details: details)}
  end
end
