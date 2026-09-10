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
