defmodule Jido.AgentServer.Plugin.Callbacks do
  @moduledoc false

  alias Jido.Agent.Command
  alias Jido.AgentServer.Plugin.{Admission, Commit, Spec}
  alias Jido.Plugin.{DirectiveContext, Init, Input, SignalContext}
  alias Jido.Plugin.Error, as: PluginError
  alias Jido.Plugin.Normalizer

  @doc false
  @spec commit_modules([Jido.Plugin.Spec.t()]) :: [module()]
  def commit_modules(specs), do: callback_packages(specs, :after_commit, 3)

  @doc false
  @spec after_commit(Jido.Plugin.Spec.t(), term(), Commit.t()) :: :ok | {:error, term()}
  def after_commit(
        %{agent_server: %Spec{} = spec},
        runtime_ref,
        %Commit{plugin: package} = commit
      )
      when package == spec.package do
    PluginError.safe_apply(
      spec.package,
      spec.module,
      :after_commit,
      [runtime_ref, commit, spec.options],
      "Agent Server Plugin commit notification failed"
    )
    |> validate_status_result(
      spec,
      "Agent Server Plugin after_commit/3 returned an invalid result"
    )
  end

  @doc false
  @spec admits?([Jido.Plugin.Spec.t()]) :: boolean()
  def admits?(specs), do: Enum.any?(specs, &callback?(&1, :admit, 3))

  @doc false
  @spec admission_modules([Jido.Plugin.Spec.t()]) :: [module()]
  def admission_modules(specs), do: callback_packages(specs, :admit, 3)

  @doc false
  @spec dispatch_modules([Jido.Plugin.Spec.t()]) :: [module()]
  def dispatch_modules(specs), do: callback_packages(specs, :prepare_dispatch, 4)

  @doc false
  @spec admit(Command.t(), [Jido.Plugin.Spec.t()], %{optional(module()) => term() | nil}) ::
          {:ok, Command.t()} | {:error, term()}
  def admit(%Command{} = command, specs, runtime_refs)
      when is_list(specs) and is_map(runtime_refs) do
    admit(command, specs, runtime_refs, 0)
  end

  @doc false
  @spec admit(
          Command.t(),
          [Jido.Plugin.Spec.t()],
          %{optional(module()) => term() | nil},
          non_neg_integer()
        ) :: {:ok, Command.t()} | {:error, term()}
  def admit(%Command{} = command, specs, runtime_refs, state_version)
      when is_list(specs) and is_map(runtime_refs) and is_integer(state_version) and
             state_version >= 0 do
    with {:ok, specs} <- Normalizer.normalize_all(specs) do
      Enum.reduce_while(specs, {:ok, command}, fn plugin_spec, {:ok, current} ->
        case admit_one(
               current,
               plugin_spec,
               Map.get(runtime_refs, plugin_spec.module),
               state_version
             ) do
          {:ok, admitted} -> {:cont, {:ok, admitted}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  @doc false
  @spec prepare_dispatch(
          Jido.Signal.t(),
          [Jido.Plugin.Spec.t()],
          %{optional(module()) => term() | nil},
          SignalContext.t(),
          map()
        ) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def prepare_dispatch(%Jido.Signal{} = signal, specs, runtime_refs, context, agent_state)
      when is_list(specs) and is_map(runtime_refs) and is_map(agent_state) do
    with {:ok, specs} <- Normalizer.normalize_all(specs) do
      specs
      |> Enum.reverse()
      |> Enum.reduce_while({:ok, signal}, fn plugin_spec, {:ok, current} ->
        plugin_context = %{
          context
          | plugin_state: owned_state(agent_state, plugin_spec)
        }

        case prepare_dispatch_one(
               current,
               plugin_spec,
               Map.get(runtime_refs, plugin_spec.module),
               plugin_context
             ) do
          {:ok, prepared} -> {:cont, {:ok, prepared}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  @doc false
  @spec child_specs(Init.t(), [Jido.Plugin.declaration()] | [Jido.Plugin.Spec.t()]) ::
          {:ok, [Supervisor.child_spec()]} | {:error, term()}
  def child_specs(%Init{} = init, declarations) do
    with {:ok, specs} <- Normalizer.normalize_all(declarations) do
      specs
      |> Enum.reduce_while({:ok, []}, fn plugin_spec, {:ok, child_specs} ->
        facet_init = %{
          init
          | module: plugin_spec.module,
            options: server_options(plugin_spec)
        }

        case child_spec(plugin_spec, facet_init) do
          :none -> {:cont, {:ok, child_specs}}
          {:ok, child_spec} -> {:cont, {:ok, [child_spec | child_specs]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, child_specs} -> {:ok, Enum.reverse(child_specs)}
        error -> error
      end
    end
  end

  @doc false
  @spec dispatch(Jido.Plugin.Spec.t(), term(), struct(), DirectiveContext.t()) ::
          :ok | {:error, term()}
  def dispatch(
        %Jido.Plugin.Spec{} = plugin_spec,
        runtime_ref,
        directive,
        %DirectiveContext{} = context
      ) do
    with {:ok, [%{agent_server: %Spec{} = spec}]} <-
           Normalizer.normalize_all([plugin_spec]) do
      PluginError.safe_apply(
        spec.package,
        spec.module,
        :dispatch,
        [runtime_ref, directive, context, spec.options],
        "Agent Server Plugin Directive dispatch failed"
      )
      |> validate_status_result(
        spec,
        "Agent Server Plugin dispatch/4 returned an invalid result"
      )
    end
  end

  @doc false
  @spec await_ready(Jido.Plugin.Spec.t(), term()) :: :ok | {:error, term()}
  def await_ready(%Jido.Plugin.Spec{} = plugin_spec, runtime_ref) do
    with {:ok, [plugin_spec]} <- Normalizer.normalize_all([plugin_spec]) do
      do_await_ready(plugin_spec, runtime_ref)
    end
  end

  defp do_await_ready(%{agent_server: nil}, _runtime_ref), do: :ok
  defp do_await_ready(%{agent_server: %Spec{runtime?: false}}, _runtime_ref), do: :ok

  defp do_await_ready(%{agent_server: %Spec{} = spec}, runtime_ref) do
    if function_exported?(spec.module, :await_ready, 2) do
      PluginError.safe_apply(
        spec.package,
        spec.module,
        :await_ready,
        [runtime_ref, spec.options],
        "Agent Server Plugin readiness check failed"
      )
      |> validate_status_result(
        spec,
        "Agent Server Plugin await_ready/2 returned an invalid result"
      )
    else
      :ok
    end
  end

  defp admit_one(command, %{agent_server: nil}, _runtime_ref, _state_version),
    do: {:ok, command}

  defp admit_one(
         command,
         %{agent_server: %Spec{} = spec} = plugin_spec,
         runtime_ref,
         state_version
       ) do
    if function_exported?(spec.module, :admit, 3) do
      package_input = Map.get(command.plugin_inputs, spec.package, %Input{})

      admission = %Admission{
        plugin: spec.package,
        agent_id: command.agent.id,
        agent_module: command.agent.module,
        signal: command.signal,
        caller_context: command.context,
        plugin_state: owned_state(command.agent.state, plugin_spec),
        prepared_input: package_input.prepared,
        state_version: state_version
      }

      PluginError.safe_apply(
        spec.package,
        spec.module,
        :admit,
        [runtime_ref, admission, spec.options],
        "Agent Server Plugin admission failed"
      )
      |> validate_runtime_input(command, spec)
    else
      {:ok, command}
    end
  end

  defp prepare_dispatch_one(signal, %{agent_server: nil}, _runtime_ref, _context),
    do: {:ok, signal}

  defp prepare_dispatch_one(signal, %{agent_server: %Spec{} = spec}, runtime_ref, context) do
    if function_exported?(spec.module, :prepare_dispatch, 4) do
      PluginError.safe_apply(
        spec.package,
        spec.module,
        :prepare_dispatch,
        [runtime_ref, signal, context, spec.options],
        "Agent Server Plugin outbound Signal preparation failed"
      )
      |> case do
        {:ok, %Jido.Signal{} = prepared} ->
          validate_signal(prepared, spec)

        {:error, _reason} = error ->
          error

        result ->
          PluginError.invalid_callback(
            "Agent Server Plugin prepare_dispatch/4 returned an invalid result",
            spec.package,
            spec.module,
            %{result: result}
          )
      end
    else
      {:ok, signal}
    end
  end

  defp validate_runtime_input({:ok, runtime_input}, command, spec) do
    {:ok, Command.put_plugin_runtime_input(command, spec.package, runtime_input)}
  end

  defp validate_runtime_input({:error, _reason} = error, _command, _spec), do: error

  defp validate_runtime_input(result, _command, spec) do
    PluginError.invalid_callback(
      "Agent Server Plugin admit/3 returned an invalid result",
      spec.package,
      spec.module,
      %{result: result}
    )
  end

  defp validate_signal(signal, spec) do
    case Zoi.parse(Jido.Signal.schema(), signal) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, errors} ->
        PluginError.invalid_callback(
          "Agent Server Plugin prepare_dispatch/4 returned an invalid Signal",
          spec.package,
          spec.module,
          %{errors: errors}
        )
    end
  end

  defp child_spec(%{agent_server: nil}, _init), do: :none
  defp child_spec(%{agent_server: %Spec{runtime?: false}}, _init), do: :none

  defp child_spec(%{agent_server: %Spec{} = spec}, %Init{} = init) do
    {spec.module, init}
    |> Supervisor.child_spec(id: spec.package)
    |> validate_child_spec(spec)
  rescue
    error ->
      PluginError.validation(
        "Agent Server Plugin child_spec/1 raised",
        %{
          plugin: spec.package,
          facet: spec.module,
          error: error
        }
      )
  catch
    kind, reason ->
      PluginError.validation(
        "Agent Server Plugin child_spec/1 failed",
        %{
          plugin: spec.package,
          facet: spec.module,
          kind: kind,
          reason: reason
        }
      )
  end

  defp validate_child_spec(%{} = child_spec, spec) do
    with :ok <- validate_otp_child_spec(child_spec, spec),
         :ok <- validate_child_start(child_spec, spec) do
      case Map.get(child_spec, :restart, :permanent) do
        :permanent ->
          {:ok, child_spec}

        restart ->
          PluginError.validation(
            "Agent Server Plugin runtime root must use :permanent restart",
            %{
              plugin: spec.package,
              facet: spec.module,
              restart: restart
            }
          )
      end
    end
  end

  defp validate_otp_child_spec(child_spec, spec) do
    case :supervisor.check_childspecs([child_spec]) do
      :ok -> :ok
      {:error, reason} -> invalid_child_spec(child_spec, spec, reason)
    end
  end

  defp validate_child_start(%{start: {module, function, args}} = child_spec, spec) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         true <- function_exported?(module, function, length(args)) do
      :ok
    else
      {:error, reason} ->
        invalid_child_spec(child_spec, spec, {:module_not_loaded, module, reason})

      false ->
        invalid_child_spec(
          child_spec,
          spec,
          {:function_not_exported, module, function, length(args)}
        )
    end
  end

  defp invalid_child_spec(child_spec, spec, reason) do
    PluginError.validation(
      "Agent Server Plugin child_spec/1 returned an invalid child specification",
      %{plugin: spec.package, facet: spec.module, child_spec: child_spec, reason: reason}
    )
  end

  defp validate_status_result(:ok, _spec, _message), do: :ok
  defp validate_status_result({:error, _reason} = error, _spec, _message), do: error

  defp validate_status_result(result, spec, message) do
    PluginError.invalid_callback(message, spec.package, spec.module, %{result: result})
  end

  defp callback?(%{agent_server: %Spec{} = spec}, function, arity),
    do: function_exported?(spec.module, function, arity)

  defp callback?(_plugin_spec, _function, _arity), do: false

  defp callback_packages(specs, function, arity) do
    specs
    |> Enum.filter(&callback?(&1, function, arity))
    |> Enum.map(& &1.module)
  end

  defp server_options(%{agent_server: %Spec{options: options}}), do: options
  defp server_options(_plugin_spec), do: []

  defp owned_state(_agent_state, %{agent: %{state_key: nil}}), do: nil
  defp owned_state(agent_state, %{agent: %{state_key: key}}), do: Map.get(agent_state, key)
  defp owned_state(_agent_state, _plugin_spec), do: nil
end
