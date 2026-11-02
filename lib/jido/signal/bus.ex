defmodule Jido.Signal.Bus do
  @moduledoc """
  Provides ordered local publish and subscribe delivery for Signals.

  A normal subscription receives `{:signal, signal}` messages while its target
  process is alive. It selects by type path and can add exact `source` and
  `subject` matching with the `:selector` option. See `subscribe/3`.

  A durable subscription has a stable string ID. It receives one
  `{:signal, durable_id, recorded_signal}` message at a time. The target must
  acknowledge the record cursor before the Bus sends the next record. If the
  target exits, the Bus keeps the cursor and sends the unacknowledged record
  again when a new process attaches with the same durable ID.

  The Bus stores every record before it sends a message. Delivery is ordered
  and at least once. The Bus does not own retry timers, dead-letter queues,
  leases, or competing-consumer policy.

  `Jido.Signal.Bus.Store.Memory` is the only included store. Its state does not
  survive a Bus or VM restart. An application can provide a store that
  implements `Jido.Signal.Bus.Store` when records must survive a restart.
  """

  alias Jido.Signal
  alias Jido.Signal.Bus.RecordedSignal
  alias Jido.Signal.Bus.Server
  alias Jido.Signal.Router

  @type server ::
          pid() | atom() | binary() | {name :: atom() | binary(), registry :: module()}
  @type path :: Router.path()
  @type subscription_id :: String.t()
  @type durable_id :: String.t()

  @typedoc "Exact source and/or subject equality tests for an ordinary subscription."
  @type selector :: [source: String.t(), subject: String.t()]

  @start_options_schema Zoi.keyword(
                          [
                            name:
                              Zoi.union([Zoi.atom(), Zoi.string()])
                              |> Zoi.refine({__MODULE__, :validate_name, []})
                              |> Zoi.required(),
                            jido: Zoi.atom() |> Zoi.nullable() |> Zoi.optional(),
                            registry:
                              Zoi.atom()
                              |> Zoi.refine({__MODULE__, :not_nil, []})
                              |> Zoi.optional(),
                            store:
                              Zoi.atom()
                              |> Zoi.refine({__MODULE__, :not_nil, []})
                              |> Zoi.optional(),
                            store_opts: Zoi.keyword(Zoi.any()) |> Zoi.default([]),
                            max_log_size: Zoi.integer() |> Zoi.min(1) |> Zoi.optional()
                          ],
                          unrecognized_keys: :error
                        )

  @doc "Returns a child specification for a named Bus."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts = validate_start_options!(opts)
    name = Keyword.fetch!(opts, :name)

    %{
      id: child_id(name, opts),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @doc """
  Starts a Bus linked to the caller.

  Options:

  - `:name` is required and sets the Registry key.
  - `:jido` adds an isolated namespace to the Registry key.
  - `:registry` selects a Registry. The package Registry is the default.
  - `:store` selects a `Jido.Signal.Bus.Store` module.
  - `:store_opts` configures the selected store.
  - `:max_log_size` sets the memory-store record bound. The default is 100,000.

  Unknown options return an `:invalid_options` error.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    with {:ok, opts} <- validate_start_options(opts) do
      name = Keyword.fetch!(opts, :name)
      GenServer.start_link(Server, {name, opts}, name: via_tuple(name, opts))
    end
  end

  @doc "Returns the Registry tuple for a Bus name."
  @spec via_tuple(server(), keyword()) :: {:via, Registry, {module(), term()}}
  def via_tuple(name_or_tuple, opts \\ [])

  def via_tuple({name, registry}, _opts) when is_atom(registry) do
    {:via, Registry, {registry, normalize_name(name)}}
  end

  def via_tuple(name, opts) do
    {:via, Registry, {registry(opts), registry_key(name, opts)}}
  end

  @doc "Finds a Bus by PID, name, or `{name, registry}` tuple."
  @spec whereis(server(), keyword()) :: {:ok, pid()} | {:error, :not_found}
  def whereis(server, opts \\ [])

  def whereis(pid, _opts) when is_pid(pid) do
    if node(pid) == node() and Process.alive?(pid),
      do: {:ok, pid},
      else: {:error, :not_found}
  end

  def whereis({name, registry}, _opts) when is_atom(registry) do
    registry_lookup(registry, normalize_name(name))
  end

  def whereis(name, opts) do
    registry_lookup(registry(opts), registry_key(name, opts))
  end

  @doc """
  Adds a subscription for a signal-type path.

  The calling process is the default `:target`.

  The path selects the Signal type, using exact or wildcard Router matching.
  Set `:selector` to a non-empty keyword list with `:source`, `:subject`, or
  both. The option and each field key can appear once. All fields must match
  the Signal envelope with exact, case-sensitive equality. For example:

      subscribe(bus, "inventory.stock.changed",
        selector: [source: "/warehouses/east", subject: "sku-42"]
      )

  Values must be non-empty strings with at most 4,096 bytes. A source must be
  a valid URI-reference. A subject must be valid CloudEvents context text.
  A missing subject does not match a selected subject. Other envelope fields,
  data, and extensions do not affect selection. The Bus sends the original
  Signal in Router order.

  Omit `:selector` for the default type-path-only subscription. Empty lists,
  `nil`, duplicate keys, unsupported fields, invalid values, functions, and
  MFAs return `{:error, {:invalid_selector, message}}` without adding a
  subscription. The Bus compiles a fixed pattern-matching predicate once at
  subscription time. It does not execute application selector callbacks.

  Set `durable: "stable-id"` to keep a cursor when the target exits. A new
  durable subscription starts at the current cursor by default. Set
  `start_from: :origin` or a retained cursor to read older records.
  `:selector` with `:durable` returns
  `{:error, {:conflicting_options, [:selector, :durable]}}` without changing
  the stored definition or cursor. Replay selects only by type path and does
  not accept `:selector`.
  """
  @spec subscribe(server(), path(), keyword()) ::
          {:ok, subscription_id()} | {:error, term()}
  def subscribe(bus, path, opts \\ [])

  def subscribe(bus, path, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts = Keyword.put_new(opts, :target, self())

      bus_call(bus, {:subscribe, path, opts})
    else
      {:error, :invalid_options}
    end
  end

  def subscribe(_bus, _path, _opts), do: {:error, :invalid_options}

  @doc """
  Detaches a subscription target.

  A normal subscription is removed. A durable subscription stays in the Store
  and can attach again through `subscribe/3` with the same durable ID.
  """
  @spec unsubscribe(server(), subscription_id(), keyword()) :: :ok | {:error, term()}
  def unsubscribe(bus, subscription_id, opts \\ [])

  def unsubscribe(bus, subscription_id, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      bus_call(bus, {:unsubscribe, subscription_id, opts})
    else
      {:error, :invalid_options}
    end
  end

  def unsubscribe(_bus, _subscription_id, _opts), do: {:error, :invalid_options}

  @doc "Permanently removes a subscription and its durable cursor."
  @spec delete_subscription(server(), subscription_id()) :: :ok | {:error, term()}
  def delete_subscription(bus, subscription_id) do
    bus_call(bus, {:delete_subscription, subscription_id})
  end

  @doc "Publishes Signals after the Store accepts all records."
  @spec publish(server(), [Signal.t()]) ::
          {:ok, [RecordedSignal.t()]} | {:error, term()}
  def publish(_bus, []), do: {:ok, []}

  def publish(bus, signals) when is_list(signals) and is_integer(length(signals)) do
    bus_call(bus, {:publish, signals})
  end

  def publish(_bus, _signals), do: {:error, :invalid_signals}

  @doc """
  Reads retained records that match a signal-type path.

  Use `:after` for an exclusive cursor and `:limit` for a positive record count
  or `:infinity`.
  """
  @spec replay(server(), path(), keyword()) ::
          {:ok, [RecordedSignal.t()]} | {:error, term()}
  def replay(bus, path \\ "**", opts \\ [])

  def replay(bus, path, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      bus_call(bus, {:replay, path, opts})
    else
      {:error, :invalid_options}
    end
  end

  def replay(_bus, _path, _opts), do: {:error, :invalid_options}

  @doc "Acknowledges the current record for a durable subscription."
  @spec ack(server(), durable_id(), non_neg_integer()) :: :ok | {:error, term()}
  def ack(bus, durable_id, cursor) do
    bus_call(bus, {:ack, durable_id, cursor})
  end

  @doc false
  def validate_name(name, _opts) when is_atom(name) and not is_nil(name), do: :ok

  def validate_name(name, _opts) when is_binary(name) and byte_size(name) > 0, do: :ok
  def validate_name(_name, _opts), do: {:error, "must be a non-empty atom or string"}

  @doc false
  def not_nil(nil, _opts), do: {:error, "must not be nil"}
  def not_nil(_value, _opts), do: :ok

  defp validate_start_options(opts) do
    with true <- Keyword.keyword?(opts),
         store_opts <- opts |> Keyword.get_values(:store_opts) |> List.last([]),
         true <- is_nil(store_opts) or Keyword.keyword?(store_opts) do
      case Zoi.parse(@start_options_schema, opts) do
        {:ok, validated_opts} -> {:ok, validated_opts}
        {:error, errors} -> {:error, {:invalid_options, Zoi.prettify_errors(errors)}}
      end
    else
      false -> {:error, {:invalid_options, "options and store_opts must be keyword lists"}}
    end
  end

  defp validate_start_options!(opts) do
    case validate_start_options(opts) do
      {:ok, validated_opts} -> validated_opts
      {:error, {:invalid_options, message}} -> raise ArgumentError, message
    end
  end

  defp child_id(name, opts) do
    {__MODULE__, registry(opts), registry_key(name, opts)}
  end

  defp registry(opts), do: Keyword.get(opts, :registry, Jido.Signal.Registry)

  defp registry_key(name, opts) do
    name = normalize_name(name)

    case Keyword.get(opts, :jido) do
      nil -> name
      scope -> {scope, name}
    end
  end

  defp normalize_name(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize_name(name) when is_binary(name), do: name

  defp registry_lookup(registry, key) do
    case Registry.lookup(registry, key) do
      [{pid, _value} | _rest] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  rescue
    ArgumentError -> {:error, :not_found}
  catch
    :exit, _reason -> {:error, :not_found}
  end

  defp bus_call(bus, message) do
    GenServer.call(bus_call_target(bus), message, :infinity)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
    :exit, {:shutdown, _} -> {:error, :not_found}
    :exit, {:normal, _} -> {:error, :not_found}
    :exit, {{:shutdown, _reason}, _call} -> {:error, :not_found}
    :exit, :noproc -> {:error, :not_found}
    :exit, :shutdown -> {:error, :not_found}
    :exit, :normal -> {:error, :not_found}
  end

  defp bus_call_target(pid) when is_pid(pid), do: pid
  defp bus_call_target({name, registry}) when is_atom(registry), do: via_tuple({name, registry})

  defp bus_call_target(name) when is_atom(name) or is_binary(name),
    do: via_tuple(name)
end
