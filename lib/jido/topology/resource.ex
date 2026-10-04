defmodule Jido.Topology.Resource do
  @moduledoc false

  alias Jido.Agent.Authoring
  alias Jido.Signal.Bus

  @kinds [:bus]
  @reserved_bus_options [:name, :jido, :registry]

  @doc false
  def kinds, do: @kinds

  @doc false
  def resource?(%{kind: kind}), do: kind in @kinds
  def resource?(_value), do: false

  @doc false
  def validate(:bus, config) do
    with {:ok, config} <- Authoring.options(config),
         :ok <- reserved_bus_options(config),
         do: {:ok, config}
  end

  def validate(kind, _config),
    do: Authoring.error("Unsupported topology option", %{field: :kind, value: kind})

  @doc false
  def ensure(%{kind: :bus} = spec, context) do
    case Bus.whereis(spec.id, jido: context.jido) do
      {:ok, pid} ->
        if Process.alive?(pid),
          do: owned_bus(pid, spec, context),
          else: start_bus(spec, context)

      _other ->
        start_bus(spec, context)
    end
  end

  defp start_bus(spec, context) do
    options = Keyword.merge(spec.config, name: spec.id, jido: context.jido)
    child = Bus.child_spec(options)

    child = %{
      child
      | start: {__MODULE__, :start_bus_link, [options, Map.get(context, :parent_gate)]}
    }

    case DynamicSupervisor.start_child(context.pool, child) do
      {:error, {:already_started, pid}} -> owned_bus(pid, spec, context)
      result -> result
    end
  end

  @doc false
  def start_bus_link(options, parent_gate) do
    with {:ok, pid} <- Bus.start_link(options) do
      case Jido.Topology.Runtime.Gate.attach_bus(parent_gate, pid) do
        {:ok, _subscription} ->
          {:ok, pid}

        {:error, reason} ->
          GenServer.stop(pid)
          {:error, reason}
      end
    end
  end

  defp owned_bus(pid, spec, context),
    do: if(owned?(pid, spec, context), do: {:ok, pid}, else: {:error, :bus_identity_in_use})

  @doc false
  def whereis(%{kind: :bus} = spec, context) do
    with {:ok, pid} <- Bus.whereis(spec.id, jido: context.jido),
         true <- Process.alive?(pid),
         true <- owned?(pid, spec, context) do
      pid
    else
      _ -> nil
    end
  end

  @doc false
  def owned?(pid, %{kind: :bus} = spec, context) when is_pid(pid) do
    Map.get(context, :ready, %{})[spec.key] == pid or
      Enum.any?(DynamicSupervisor.which_children(context.pool), &(elem(&1, 1) == pid))
  end

  def owned?(_pid, _spec, _context), do: false

  defp reserved_bus_options(config) do
    if Enum.any?(@reserved_bus_options, &Keyword.has_key?(config, &1)),
      do: Authoring.error("Topology owns Bus name, Registry, and Jido scope"),
      else: :ok
  end
end
