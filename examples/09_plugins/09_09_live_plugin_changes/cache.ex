defmodule Jido.Examples.LivePluginChanges.Cache do
  @moduledoc "Owns a committed value and a bounded, replaceable cache runtime."
  use Jido.Plugin
  alias Jido.Examples.LivePluginChanges.CacheRuntime

  @impl true
  def validate_options(opts) do
    if is_integer(opts[:capacity]) and opts[:capacity] > 0,
      do: :ok,
      else: {:error, :invalid_capacity}
  end

  @impl true
  def state_spec(_), do: {:cache, Zoi.integer() |> Zoi.default(5)}
  @impl true
  def child_spec(init), do: %{id: __MODULE__, start: {CacheRuntime, :start_link, [init]}}
  @impl true
  def quiesce(runtime, _), do: GenServer.call(runtime, :quiesce)
  @impl true
  def resume(runtime, _), do: GenServer.call(runtime, :resume)
  @impl true
  def after_commit(runtime, commit, _), do: GenServer.call(runtime, {:commit, commit})
end

defmodule Jido.Examples.LivePluginChanges.CacheRuntime do
  @moduledoc "Rebuilds its bounded cache from the exact accepted Plugin value and revision."
  use GenServer
  def start_link(init), do: GenServer.start_link(__MODULE__, init)
  def snapshot(runtime), do: GenServer.call(runtime, :snapshot)
  @impl true
  def init(init),
    do:
      {:ok,
       %{
         capacity: init.options[:capacity],
         value: init.plugin_state,
         revision: init.state_version,
         entries: [{init.state_version, init.plugin_state}],
         paused: false,
         notifications: 0
       }}

  @impl true
  def handle_call(:snapshot, _, state), do: {:reply, state, state}
  def handle_call(:quiesce, _, state), do: {:reply, :ok, %{state | paused: true}}
  def handle_call(:resume, _, state), do: {:reply, :ok, %{state | paused: false}}

  def handle_call({:commit, commit}, _, state),
    do:
      {:reply, :ok,
       %{
         state
         | value: commit.plugin_state,
           revision: commit.state_version,
           entries:
             Enum.take(
               [{commit.state_version, commit.plugin_state} | state.entries],
               state.capacity
             ),
           notifications: state.notifications + 1
       }}
end
