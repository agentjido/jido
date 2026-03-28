defmodule Jido.Pod.Definition do
  @moduledoc false

  alias Jido.Agent.DefaultPlugins
  alias Jido.Plugin.Instance, as: PluginInstance
  alias Jido.Pod.Plugin
  alias Jido.Pod.Topology

  @pod_state_key Plugin.state_key_atom()
  @pod_capability Plugin.capability()

  def expand_aliases_in_ast(ast, caller_env) do
    Macro.prewalk(ast, fn
      {:__aliases__, _, _} = alias_node -> Macro.expand(alias_node, caller_env)
      other -> other
    end)
  end

  def expand_and_eval_literal_option(value, caller_env) do
    case value do
      nil ->
        nil

      value when is_atom(value) or is_binary(value) or is_number(value) or is_map(value) ->
        value

      value when is_list(value) ->
        value
        |> expand_aliases_in_ast(caller_env)
        |> Code.eval_quoted([], caller_env)
        |> elem(0)

      value when is_tuple(value) ->
        value
        |> expand_aliases_in_ast(caller_env)
        |> Code.eval_quoted([], caller_env)
        |> elem(0)

      other ->
        other
    end
  end

  def resolve_topology!(name, raw_topology, caller_env) do
    resolved = expand_and_eval_literal_option(raw_topology, caller_env)

    case resolved do
      %Topology{} = topology ->
        case Topology.with_name(topology, name) do
          {:ok, updated} ->
            updated

          {:error, reason} ->
            raise CompileError,
              description: inspect(reason),
              file: caller_env.file,
              line: caller_env.line
        end

      topology when is_map(topology) ->
        Topology.from_nodes!(name, topology)

      other ->
        raise CompileError,
          description:
            "Invalid Jido.Pod topology for #{inspect(caller_env.module)}: expected a map or %Jido.Pod.Topology{}, got: #{inspect(other)}",
          file: caller_env.file,
          line: caller_env.line
    end
  end

  def split_pod_plugins!(default_plugins, caller_env) do
    pod_override =
      if is_map(default_plugins) do
        Map.take(default_plugins, [@pod_state_key])
      else
        %{}
      end

    pod_plugins = DefaultPlugins.apply_agent_overrides([Plugin], pod_override)

    if pod_plugins == [] do
      raise CompileError,
        description:
          "Jido.Pod requires a singleton pod plugin under #{@pod_state_key}. " <>
            "Replace it with `default_plugins: %{#{@pod_state_key}: YourPlugin}` instead of disabling it.",
        file: caller_env.file,
        line: caller_env.line
    end

    Enum.each(pod_plugins, &validate_pod_plugin_decl!(&1, caller_env))

    remaining_default_plugins =
      if is_map(default_plugins) do
        Map.delete(default_plugins, @pod_state_key)
      else
        default_plugins
      end

    {pod_plugins, remaining_default_plugins}
  end

  defp validate_pod_plugin_decl!(decl, caller_env) do
    mod =
      case decl do
        {module, _config} -> module
        module -> module
      end

    case Code.ensure_compiled(mod) do
      {:module, _compiled} ->
        :ok

      {:error, reason} ->
        raise CompileError,
          description: "Pod plugin #{inspect(mod)} could not be compiled: #{inspect(reason)}",
          file: caller_env.file,
          line: caller_env.line
    end

    instance =
      try do
        PluginInstance.new(decl)
      rescue
        error in [ArgumentError] ->
          raise CompileError,
            description: "Invalid pod plugin #{inspect(mod)}: #{Exception.message(error)}",
            file: caller_env.file,
            line: caller_env.line
      end

    cond do
      not instance.manifest.singleton ->
        raise CompileError,
          description: "#{inspect(mod)} must be a singleton plugin to replace the pod plugin.",
          file: caller_env.file,
          line: caller_env.line

      instance.state_key != @pod_state_key ->
        raise CompileError,
          description:
            "#{inspect(mod)} must use state_key #{@pod_state_key} to replace the pod plugin.",
          file: caller_env.file,
          line: caller_env.line

      @pod_capability not in (instance.manifest.capabilities || []) ->
        raise CompileError,
          description:
            "#{inspect(mod)} must advertise capability #{@pod_capability} to replace the pod plugin.",
          file: caller_env.file,
          line: caller_env.line

      true ->
        :ok
    end
  end
end
