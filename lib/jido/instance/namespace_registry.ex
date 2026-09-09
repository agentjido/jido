defmodule Jido.Instance.NamespaceRegistry do
  @moduledoc false

  use GenServer

  alias Jido.Error

  @table Module.concat(__MODULE__, Table)

  @type claim :: reference() | :existing | nil

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc false
  @spec claim(String.t() | nil, atom()) ::
          {:ok, claim()} | {:error, Error.ValidationError.t()}
  def claim(nil, _instance), do: {:ok, nil}

  def claim(namespace, instance) when is_binary(namespace) and is_atom(instance) do
    GenServer.call(__MODULE__, {:claim, namespace, instance, self()})
  end

  @doc false
  @spec bind(claim(), String.t() | nil, atom(), pid()) ::
          :ok | {:error, Error.ValidationError.t()}
  def bind(nil, nil, _instance, _owner), do: :ok

  def bind(claim, namespace, instance, owner)
      when is_reference(claim) and is_binary(namespace) and is_atom(instance) and is_pid(owner) do
    GenServer.call(__MODULE__, {:bind, claim, namespace, instance, owner})
  end

  def bind(:existing, namespace, instance, owner)
      when is_binary(namespace) and is_atom(instance) and is_pid(owner) do
    GenServer.call(__MODULE__, {:bind_existing, namespace, instance, owner})
  end

  @doc false
  @spec release(claim()) :: :ok
  def release(nil), do: :ok
  def release(:existing), do: :ok
  def release(claim) when is_reference(claim), do: GenServer.call(__MODULE__, {:release, claim})

  @doc false
  @spec namespace(atom()) :: String.t() | nil
  def namespace(instance) when is_atom(instance) do
    GenServer.call(__MODULE__, {:namespace, instance})
  end

  @doc false
  @spec lookup(String.t()) :: {atom(), pid()} | nil
  def lookup(namespace) when is_binary(namespace) do
    GenServer.call(__MODULE__, {:lookup, namespace})
  end

  @impl true
  def init(_opts) do
    ensure_table()

    {bindings, monitors} =
      @table
      |> :ets.tab2list()
      |> Enum.reduce({%{}, %{}}, fn
        {namespace, token, instance, owner}, {bindings, monitors} ->
          if Process.alive?(owner) do
            monitor = Process.monitor(owner)
            binding = %{token: token, instance: instance, owner: owner, monitor: monitor}

            {
              Map.put(bindings, namespace, binding),
              Map.put(monitors, monitor, namespace)
            }
          else
            :ets.delete(@table, namespace)
            {bindings, monitors}
          end
      end)

    {:ok, %{bindings: bindings, monitors: monitors}}
  end

  @impl true
  def handle_call({:claim, namespace, instance, owner}, _from, state) do
    case Map.get(state.bindings, namespace) do
      nil ->
        token = make_ref()
        monitor = Process.monitor(owner)
        binding = %{token: token, instance: instance, owner: owner, monitor: monitor}
        put_binding(namespace, binding)

        {:reply, {:ok, token},
         %{
           state
           | bindings: Map.put(state.bindings, namespace, binding),
             monitors: Map.put(state.monitors, monitor, namespace)
         }}

      %{instance: ^instance, owner: current_owner} when is_pid(current_owner) ->
        {:reply, {:ok, :existing}, state}

      %{owner: current_owner} ->
        {:reply, {:error, already_bound(namespace, current_owner)}, state}
    end
  end

  def handle_call({:bind, token, namespace, instance, owner}, _from, state) do
    case Map.get(state.bindings, namespace) do
      %{token: ^token, instance: ^instance} = binding ->
        old_monitor = binding.monitor
        Process.demonitor(old_monitor, [:flush])
        monitor = Process.monitor(owner)
        binding = %{binding | owner: owner, monitor: monitor}
        put_binding(namespace, binding)

        {:reply, :ok,
         %{
           state
           | bindings: Map.put(state.bindings, namespace, binding),
             monitors:
               state.monitors
               |> Map.delete(old_monitor)
               |> Map.put(monitor, namespace)
         }}

      %{owner: current_owner} ->
        {:reply, {:error, already_bound(namespace, current_owner)}, state}

      nil ->
        {:reply, {:error, already_bound(namespace, nil)}, state}
    end
  end

  def handle_call({:release, token}, _from, state) do
    case Enum.find(state.bindings, fn {_namespace, binding} -> binding.token == token end) do
      {namespace, binding} ->
        Process.demonitor(binding.monitor, [:flush])
        {:reply, :ok, delete_binding(state, namespace, binding.monitor)}

      nil ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:bind_existing, namespace, instance, owner}, _from, state) do
    case Map.get(state.bindings, namespace) do
      %{instance: ^instance, owner: ^owner} ->
        {:reply, :ok, state}

      %{owner: current_owner} ->
        {:reply, {:error, already_bound(namespace, current_owner)}, state}

      nil ->
        token = make_ref()
        monitor = Process.monitor(owner)
        binding = %{token: token, instance: instance, owner: owner, monitor: monitor}
        put_binding(namespace, binding)

        {:reply, :ok,
         %{
           state
           | bindings: Map.put(state.bindings, namespace, binding),
             monitors: Map.put(state.monitors, monitor, namespace)
         }}
    end
  end

  def handle_call({:namespace, instance}, _from, state) do
    namespace =
      Enum.find_value(state.bindings, fn
        {namespace, %{instance: ^instance, owner: owner}} ->
          if Process.alive?(owner), do: namespace

        _binding ->
          nil
      end)

    {:reply, namespace, state}
  end

  def handle_call({:lookup, namespace}, _from, state) do
    result =
      case Map.get(state.bindings, namespace) do
        %{instance: instance, owner: owner} -> {instance, owner}
        nil -> nil
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case Map.get(state.monitors, monitor) do
      nil -> {:noreply, state}
      namespace -> {:noreply, delete_binding(state, namespace, monitor)}
    end
  end

  defp delete_binding(state, namespace, monitor) do
    :ets.delete(@table, namespace)

    %{
      state
      | bindings: Map.delete(state.bindings, namespace),
        monitors: Map.delete(state.monitors, monitor)
    }
  end

  defp put_binding(namespace, binding) do
    true =
      :ets.insert(
        @table,
        {namespace, binding.token, binding.instance, binding.owner}
      )

    :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        [parent | _ancestors] = Process.get(:"$ancestors")
        heir = if is_pid(parent), do: parent, else: Process.whereis(parent)

        _table =
          :ets.new(@table, [
            :named_table,
            :set,
            :public,
            {:heir, heir, :namespace_registry},
            read_concurrency: true,
            write_concurrency: true
          ])

        :ok

      _table ->
        :ok
    end
  end

  defp already_bound(namespace, owner) do
    Error.validation_error("Jido instance namespace is already bound",
      kind: :config,
      subject: namespace,
      details: %{
        code: :jido_namespace_already_bound,
        namespace: namespace,
        owner: owner
      }
    )
  end
end
