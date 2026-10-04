defmodule Jido.Topology.Runtime.Gate do
  @moduledoc false
  use Supervisor
  alias Jido.Topology.{Child, Controller, Runtime}
  alias Jido.Topology.Runtime.{Gateway, GateServer}

  def child_spec({_config, child} = args) do
    %{
      id: {__MODULE__, child.key},
      start: {__MODULE__, :start_link, [args]},
      type: :supervisor,
      restart: :transient,
      shutdown: :infinity
    }
  end

  def start_link({config, child} = args),
    do:
      Supervisor.start_link(__MODULE__, args,
        name: Controller.name(config.jido, config.id, {:gate_supervisor, child.key})
      )

  @impl true
  def init({config, child}) do
    children = [
      Supervisor.child_spec(
        {DynamicSupervisor,
         strategy: :one_for_one,
         max_restarts: child.max_restarts,
         max_seconds: child.max_seconds,
         name: Controller.name(config.jido, config.id, {:gate_children, child.key})},
        restart: :temporary,
        significant: true
      ),
      {Task.Supervisor, name: Controller.name(config.jido, config.id, {:gate_tasks, child.key})},
      {GateServer, {config, child}}
    ]

    Supervisor.init(children, strategy: :rest_for_one, auto_shutdown: :any_significant)
  end

  def call(jido, id, key, signal, opts) do
    with {:ok, key} <- Jido.Topology.Validation.key(key),
         {:ok, timeout} <- Gateway.timeout(opts) do
      case Runtime.lookup(jido, id, {:gate, key}) do
        nil ->
          missing(jido, id, key)

        pid ->
          Gateway.bounded_call(
            pid,
            {:call, signal, Gateway.deadline(timeout), Gateway.options(opts)},
            timeout
          )
      end
    end
  end

  defp missing(jido, id, key) do
    case Runtime.lookup(jido, id, :gateway) do
      nil ->
        {:error, :topology_not_running}

      pid ->
        config = GenServer.call(pid, :config)

        if Enum.any?(config.instance.definition.children, &(&1.key == key)),
          do: {:error, :child_restart_limit},
          else: {:error, :unknown_child}
    end
  end

  def status(jido, id, key) do
    case Runtime.lookup(jido, id, {:gate, key}) do
      nil -> %{id: Child.id(id, key), status: :failed}
      pid -> GenServer.call(pid, :status)
    end
  catch
    :exit, _ -> %{id: Child.id(id, key), status: :failed}
  end

  def whereis_child(jido, id, key) do
    with {:ok, key} <- Jido.Topology.Validation.key(key),
         pid when is_pid(pid) <- Runtime.lookup(jido, id, {:gate_children, key}) do
      Enum.find_value(DynamicSupervisor.which_children(pid), fn
        {_, child, _, _} when is_pid(child) -> child
        _ -> nil
      end)
    else
      _ -> nil
    end
  catch
    :exit, _ -> nil
  end

  def await_idle(jido, id, key, timeout) do
    with {:ok, key} <- Jido.Topology.Validation.key(key) do
      case Runtime.lookup(jido, id, {:gate, key}) do
        nil -> missing(jido, id, key)
        pid -> Gateway.bounded_call(pid, :idle, timeout)
      end
    end
  end

  def await_children(jido, id, children, timeout) do
    deadline = Gateway.deadline(timeout)

    Enum.reduce_while(children, :ok, fn {key, child}, :ok ->
      result =
        case child.status do
          :dormant ->
            :ok

          :failed ->
            {:error, Map.get(child, :error) || :child_restart_limit}

          _ ->
            with :ok <- await_idle(jido, id, key, Gateway.remaining(deadline)),
                 do: Runtime.await_ready(jido, child.id, Gateway.remaining(deadline))
        end

      if result == :ok, do: {:cont, :ok}, else: {:halt, result}
    end)
  end
end
