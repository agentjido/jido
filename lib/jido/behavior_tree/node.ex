defmodule Jido.BehaviorTree.Node do
  @moduledoc """
  Defines the behavior for all behavior tree nodes.

  Every node in a behavior tree must implement this behavior to define
  how it responds to ticks and how it can be halted when necessary.

  ## Node Types

  There are three main categories of nodes:

  1. **Composite Nodes** - Control the execution of multiple child nodes
     - Sequence: Execute children in order until one fails
     - Selector: Execute children in order until one succeeds

  2. **Decorator Nodes** - Modify the behavior of a single child node
     - Inverter: Invert the child's success/failure status
     - Succeeder: Convert completion to success
     - Failer: Convert completion to failure
     - Repeat: Repeat the child a specified number of times

  3. **Leaf Nodes** - Perform actual work or conditions
     - Action: Execute a Jido action
     - Wait: Pause execution for a duration
     - SetBlackboard: Write values into the tick blackboard

  ## Implementation

  When implementing a node, you define a struct to hold the node's state
  and implement the two required callbacks:

      defmodule MyNode do
        @schema Zoi.struct(
          __MODULE__,
          %{
            my_data: Zoi.any(description: "Custom node data") |> Zoi.optional()
          },
          coerce: true
        )

        @type t :: unquote(Zoi.type_spec(@schema))
        @enforce_keys Zoi.Struct.enforce_keys(@schema)
        defstruct Zoi.Struct.struct_fields(@schema)

        def schema, do: @schema

        @behaviour Jido.BehaviorTree.Node

        @impl true
        def tick(node_state, tick) do
          # Your tick logic here
          {:success, updated_node_state}
        end

        @impl true
        def halt(node_state) do
          # Your halt logic here
          updated_node_state
        end
      end

  ## Telemetry

  Behavior tree nodes emit telemetry events via `:telemetry` for observability.
  Events use the `[:jido, :bt, :node, ...]` namespace to align with core Jido telemetry.

  ### Node Tick Events

  - `[:jido, :bt, :node, :tick, :start]` - Node tick started
  - `[:jido, :bt, :node, :tick, :stop]` - Node tick completed
  - `[:jido, :bt, :node, :tick, :exception]` - Node tick raised an exception

  ### Node Halt Events

  - `[:jido, :bt, :node, :halt, :start]` - Node halt started
  - `[:jido, :bt, :node, :halt, :stop]` - Node halt completed
  - `[:jido, :bt, :node, :halt, :exception]` - Node halt raised an exception

  ### Metadata

  All events include the following metadata:

  - `:node` - The node module being executed
  - `:sequence` - The tick sequence number (for tick events)

  When running in a Jido Agent, additional metadata is included from `Tick.context`:

  - `:agent_id` - The agent's unique identifier
  - `:agent_module` - The agent module name
  - `:plugin` - The Plugin module

  ### Measurements

  - `:duration` - Execution time in nanoseconds (on `:stop` and `:exception`)
  - `:system_time` - Start timestamp in nanoseconds (on `:start`)
  """

  alias Jido.BehaviorTree.{Error, Status, Tick}

  @typedoc "Any struct that represents a behavior tree node"
  @type t :: struct()

  @doc """
  Executes a single tick of the node.

  This callback is called when the behavior tree is executed and this node
  is reached. The node should perform its logic and return a status along
  with any updated state.

  ## Parameters

  - `node_state` - The current state of this node
  - `tick` - The current tick context containing blackboard and timing info

  ## Returns

  A tuple containing:
  - The status of the node execution (`:success`, `:failure`, `:running`, or `{:error, reason}`)
  - The updated node state (which may be unchanged)

  ## Examples

      def tick(node_state, tick) do
        case perform_work(node_state, tick) do
          {:ok, result} ->
            {:success, %{node_state | result: result}}
          {:error, reason} ->
            {{:error, reason}, node_state}
        end
      end

  """
  @callback tick(node_state :: t(), tick :: Tick.t()) :: {Status.t(), t()}

  @doc "Optionally returns an updated Tick with blackboard data or Directives."
  @callback tick_with_context(t(), Tick.t()) :: {Status.t(), t(), Tick.t()}
  @optional_callbacks tick_with_context: 2

  @doc """
  Halts the execution of the node.

  This callback is called when the node needs to stop execution, typically
  when a parent node has completed or the entire tree is being stopped.

  The node should clean up any resources, cancel any ongoing operations,
  and return to a clean state.

  ## Parameters

  - `node_state` - The current state of this node

  ## Returns

  The updated node state after halting

  ## Examples

      def halt(node_state) do
        # Cancel any timers, close connections, etc.
        cancel_timer(node_state.timer)
        %{node_state | timer: nil, status: :halted}
      end

  """
  @callback halt(node_state :: t()) :: t()

  @doc """
  Executes a tick on the given node with telemetry.

  This function wraps the node's tick callback with telemetry events
  via `:telemetry` and error handling.

  ## Examples

      {status, updated_node} = Jido.BehaviorTree.Node.execute_tick(node, tick)

  """
  @spec execute_tick(t(), Tick.t()) :: {Status.t(), t()}
  def execute_tick(node_state, tick) do
    {status, node, _tick} =
      instrument_tick(node_state, tick, fn ->
        {status, updated_node} = node_state.__struct__.tick(node_state, tick)
        {status, updated_node, tick}
      end)

    {status, node}
  end

  @doc """
  Executes a tick with context, threading tick through the node.

  This variant is used by the Behavior Tree Plugin to pass agent state
  and collect directives. It returns a 3-tuple including the updated tick.

  For nodes that implement `tick_with_context/2`, that callback is used.
  Otherwise, the standard `tick/2` is called and tick is passed through unchanged.

  ## Examples

      {status, updated_node, updated_tick} = Node.execute_tick_with_context(node, tick)

  """
  @spec execute_tick_with_context(t(), Tick.t()) :: {Status.t(), t(), Tick.t()}
  def execute_tick_with_context(node_state, tick) do
    instrument_tick(node_state, tick, fn ->
      node_module = node_state.__struct__

      if function_exported?(node_module, :tick_with_context, 2) do
        node_module.tick_with_context(node_state, tick)
      else
        {status, updated_node} = node_module.tick(node_state, tick)
        {status, updated_node, tick}
      end
    end)
  end

  @doc "Executes the node halt callback with telemetry."
  @spec execute_halt(t()) :: t()
  def execute_halt(node_state) do
    node_module = node_state.__struct__

    metadata = Map.put(Map.take(node_state, [:node_path]), :node, node_module)

    :telemetry.span([:jido, :bt, :node, :halt], metadata, fn ->
      {node_module.halt(node_state), metadata}
    end)
  rescue
    _error -> node_state
  end

  @doc """
  Checks if a value implements the Node behavior.

  ## Examples

      iex> Jido.BehaviorTree.Node.node?(%Jido.BehaviorTree.Nodes.Action{})
      true

      iex> Jido.BehaviorTree.Node.node?("not a node")
      false

  """
  @spec node?(term()) :: boolean()
  def node?(value) do
    is_struct(value) and Code.ensure_loaded?(value.__struct__) and
      function_exported?(value.__struct__, :tick, 2) and function_exported?(value.__struct__, :halt, 1)
  end

  defp instrument_tick(node_state, %Tick{} = tick, work) do
    metadata =
      tick.context
      |> Map.take([:agent_id, :agent_module, :plugin])
      |> Map.merge(Map.take(node_state, [:node_path]))
      |> Map.merge(%{node: node_state.__struct__, sequence: tick.sequence})

    :telemetry.span([:jido, :bt, :node, :tick], metadata, fn ->
      {status, _node, _tick} = result = work.()
      {result, Map.put(metadata, :status, status)}
    end)
  rescue
    error ->
      reason = Error.node_error(Exception.message(error), node_state.__struct__, %{original_error: error})
      {{:error, reason}, node_state, tick}
  end
end
