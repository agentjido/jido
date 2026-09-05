defmodule Jido.Examples.BurstBuncher do
  @moduledoc """
  Collects short bursts into stable batches.

  The Agent owns buffer and deduplication policy. Its Timer Plugin owns only
  keyed OTP timers. Each accepted item replaces the pending flush timer. A
  size or timeout flush commits the empty buffer before it emits the batch.
  """

  use Jido.Agent,
    name: "examples_burst_buncher",
    description: "Collects ordered items and flushes stable batches"

  agent do
    schema Zoi.object(%{
             buffer: Zoi.list(Zoi.map()) |> Zoi.default([]),
             handled_item_ids: Zoi.list(Zoi.string()) |> Zoi.default([]),
             max_size: Zoi.integer() |> Zoi.min(1) |> Zoi.default(3),
             flush_delay_ms: Zoi.integer() |> Zoi.min(0) |> Zoi.default(50),
             timer_generation: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
             next_batch_number: Zoi.integer() |> Zoi.min(1) |> Zoi.default(1),
             last_flush_reason: Zoi.enum([:size, :timeout]) |> Zoi.nullable() |> Zoi.default(nil)
           })

    plugin Jido.Examples.BurstBuncher.Timer
  end

  routes do
    signal_source "/examples/burst_buncher"

    route "examples.buncher.add", Jido.Examples.BurstBuncher.Add do
      define :add_item, args: [:item_id, :item]
    end

    route "examples.buncher.flush", Jido.Examples.BurstBuncher.Flush do
      define :flush, args: [:generation]
    end
  end

  alias Jido.Signal

  @doc "Builds one timer flush Signal for a known generation."
  @spec timer_flush_signal!(non_neg_integer()) :: Signal.t()
  def timer_flush_signal!(generation) when is_integer(generation) and generation >= 0 do
    flush_signal!(generation, signal: [source: "/examples/burst_buncher/timer"])
  end

  @doc false
  @spec batch_signal!(pos_integer(), [map()], :size | :timeout) :: Signal.t()
  def batch_signal!(number, items, reason) do
    Signal.new!(
      "examples.buncher.batch",
      %{batch_id: "batch-#{number}", items: items, reason: reason},
      source: "/examples/burst_buncher"
    )
  end
end

defmodule Jido.Examples.BurstBuncher.Add do
  @moduledoc false

  use Jido.Action,
    name: "examples_burst_buncher_add",
    schema:
      Zoi.object(%{
        item_id: Zoi.string() |> Zoi.min(1),
        item: Zoi.any()
      })

  alias Jido.Agent.Directive
  alias Jido.Examples.BurstBuncher
  alias Jido.Examples.BurstBuncher.Timer

  @impl Jido.Action
  def run(%{item_id: item_id} = input, %{agent_state: state}) do
    if item_id in state.handled_item_ids do
      {:ok, state}
    else
      append_and_schedule(input, state)
    end
  end

  defp append_and_schedule(%{item_id: item_id, item: item}, state) do
    entry = %{id: item_id, value: item}
    buffer = state.buffer ++ [entry]
    generation = state.timer_generation + 1

    next_state = %{
      state
      | buffer: buffer,
        handled_item_ids: state.handled_item_ids ++ [item_id],
        timer_generation: generation
    }

    if length(buffer) >= state.max_size do
      flush_by_size(next_state)
    else
      signal = BurstBuncher.timer_flush_signal!(generation)

      {:ok, next_state, [Timer.replace(:flush, state.flush_delay_ms, signal)]}
    end
  end

  defp flush_by_size(state) do
    batch = BurstBuncher.batch_signal!(state.next_batch_number, state.buffer, :size)

    next_state = %{
      state
      | buffer: [],
        next_batch_number: state.next_batch_number + 1,
        last_flush_reason: :size
    }

    {:ok, next_state, [Timer.cancel(:flush), Directive.emit(batch)]}
  end
end

defmodule Jido.Examples.BurstBuncher.Flush do
  @moduledoc false

  use Jido.Action,
    name: "examples_burst_buncher_flush",
    schema: Zoi.object(%{generation: Zoi.integer() |> Zoi.min(0)})

  alias Jido.Agent.Directive
  alias Jido.Examples.BurstBuncher
  alias Jido.Examples.BurstBuncher.Timer

  @impl Jido.Action
  def run(%{generation: generation}, %{agent_state: state}) do
    if generation == state.timer_generation and state.buffer != [] do
      batch = BurstBuncher.batch_signal!(state.next_batch_number, state.buffer, :timeout)

      next_state = %{
        state
        | buffer: [],
          next_batch_number: state.next_batch_number + 1,
          last_flush_reason: :timeout
      }

      {:ok, next_state, [Timer.cancel(:flush), Directive.emit(batch)]}
    else
      {:ok, state}
    end
  end
end

defmodule Jido.Examples.BurstBuncher.Timer do
  @moduledoc "A keyed timer capability used only by the Burst Buncher example."

  use Jido.Plugin

  alias Jido.Examples.BurstBuncher.Timer.{Cancel, Replace, Runtime}
  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Signal

  @doc "Creates or replaces one keyed timer."
  @spec replace(term(), non_neg_integer(), Signal.t()) :: Replace.t()
  def replace(timer_id, delay_ms, %Signal{} = signal) do
    struct!(Replace, timer_id: timer_id, delay_ms: delay_ms, signal: signal)
  end

  @doc "Cancels one keyed timer when it exists."
  @spec cancel(term()) :: Cancel.t()
  def cancel(timer_id), do: struct!(Cancel, timer_id: timer_id)

  @impl Jido.Plugin
  def directives(_opts), do: [Replace, Cancel]

  @impl Jido.Plugin
  def validate_directive(%{__struct__: Replace} = directive, _opts) do
    Zoi.parse(Replace.schema(), Map.from_struct(directive))
  end

  def validate_directive(%{__struct__: Cancel} = directive, _opts) do
    Zoi.parse(Cancel.schema(), Map.from_struct(directive))
  end

  @impl Jido.Plugin
  def dispatch(runtime, directive, %DirectiveContext{}, opts) do
    GenServer.call(runtime, {:directive, directive}, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:buncher_timer_unavailable, reason}}
  end

  @impl Jido.Plugin
  def await_ready(runtime, opts) do
    GenServer.call(runtime, :await_ready, Keyword.get(opts, :timeout, 5_000))
  catch
    :exit, reason -> {:error, {:buncher_timer_unavailable, reason}}
  end

  @doc false
  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  end
end

defmodule Jido.Examples.BurstBuncher.Timer.Replace do
  @moduledoc "Replaces one keyed timer and its pending Signal."

  @schema Zoi.struct(
            __MODULE__,
            %{
              timer_id: Zoi.any(),
              delay_ms: Zoi.integer() |> Zoi.min(0),
              signal: Zoi.struct(Jido.Signal)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end

defmodule Jido.Examples.BurstBuncher.Timer.Cancel do
  @moduledoc "Cancels one keyed timer."

  @schema Zoi.struct(__MODULE__, %{timer_id: Zoi.any()}, coerce: true)

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end

defmodule Jido.Examples.BurstBuncher.Timer.Runtime do
  @moduledoc false

  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.BurstBuncher.Timer.{Cancel, Replace}
  alias Jido.Plugin.Init

  @spec start_link(Init.t()) :: GenServer.on_start()
  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  @doc false
  @spec fire(GenServer.server(), term()) :: :ok | {:error, :not_found}
  def fire(runtime, timer_id), do: GenServer.call(runtime, {:fire, timer_id})

  @impl GenServer
  def init(%Init{} = init) do
    {:ok, %{agent_server: init.agent_server, timers: %{}}}
  end

  @impl GenServer
  def handle_call(:await_ready, _from, state), do: {:reply, :ok, state}

  def handle_call({:directive, %Replace{} = directive}, _from, state) do
    state = cancel_timer(state, directive.timer_id)
    token = make_ref()

    timer =
      Process.send_after(
        self(),
        {:deliver, directive.timer_id, token, directive.signal},
        directive.delay_ms
      )

    timers = Map.put(state.timers, directive.timer_id, {token, timer, directive.signal})
    {:reply, :ok, %{state | timers: timers}}
  end

  def handle_call({:directive, %Cancel{timer_id: timer_id}}, _from, state) do
    {:reply, :ok, cancel_timer(state, timer_id)}
  end

  def handle_call({:fire, timer_id}, _from, state) do
    case Map.pop(state.timers, timer_id) do
      {{_token, timer, signal}, timers} ->
        _ = :erlang.cancel_timer(timer)
        Server.cast(state.agent_server, signal)
        {:reply, :ok, %{state | timers: timers}}

      {nil, _timers} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_info({:deliver, timer_id, token, signal}, state) do
    case Map.get(state.timers, timer_id) do
      {^token, _timer, _stored_signal} ->
        Server.cast(state.agent_server, signal)
        {:noreply, %{state | timers: Map.delete(state.timers, timer_id)}}

      _stale_or_cancelled ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    Enum.each(state.timers, fn {_timer_id, {_token, timer, _signal}} ->
      _ = :erlang.cancel_timer(timer)
    end)

    :ok
  end

  defp cancel_timer(state, timer_id) do
    case Map.pop(state.timers, timer_id) do
      {{_token, timer, _signal}, timers} ->
        _ = :erlang.cancel_timer(timer)
        %{state | timers: timers}

      {nil, _timers} ->
        state
    end
  end
end
