defmodule Jido.AgentServer do
  @moduledoc """
  Runs one resident Agent activation.

  All Signal request modes use one serialized Turn path. Direct server handles
  address only the current activation. Use `Jido.Agent.Address` through the Jido
  Instance when work must survive passivation or worker replacement.
  """

  alias Jido.AgentServer.{Pending, Snapshot, Status, Topology, TurnResult, Worker}
  alias Jido.Signal

  @typedoc "A local handle for one resident Agent activation."
  @type server :: :gen_statem.server_ref()

  @doc """
  Returns a child specification for one complete Agent activation.

  Pass a complete Agent instance as `:agent`. Pass `:jido` to register the
  activation with a local Jido instance and use its Runner. Start Agents on
  a clustered instance with `Jido.start_agent/3` or `Jido.activate_agent/3`
  so the home owns their supervision. A standalone
  activation needs a compatible named `:runner`.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts), do: Worker.child_spec(opts)

  @doc """
  Runs one Signal and waits for its accepted Turn result.

  The third argument is a caller timeout or a keyword list with `:timeout`,
  `:admission_timeout`, and `:context`. Both timeouts default to 5,000 ms.
  For a durable Agent, use `:turn_id` and `result_handoff: true` to retain
  the exact terminal result for lookup by Address.
  The admission timeout limits the wait before execution starts. A finite
  admission deadline requires a caller on the worker's node. Pass
  `admission_timeout: :infinity` for a caller on a different node.

  Context can be a map, a keyword list, or `nil`. It applies to one request.
  The command context keys, including `:turn_id` and `:trace_context`, are
  reserved.

  Accepted work returns `{:ok, turn_result}`, including accepted failures.
  A rejected request returns `{:error, reason}`. An OTP call can exit on
  timeout or process loss. A caller timeout leaves accepted work running.
  """
  @spec call(server(), Signal.t(), timeout() | keyword()) ::
          {:ok, TurnResult.t()} | {:error, term()}
  def call(server, signal, timeout_or_opts \\ 5_000),
    do: Worker.call(server, signal, timeout_or_opts)

  @doc """
  Sends one Signal through the same Turn path and discards its result.

  Accepts `:context` as in `call/3`. A cast has no admission deadline.
  Delivery is best effort. The worker can drop a request when the queue is
  full or admission is closed.
  """
  @spec cast(server(), Signal.t(), keyword()) :: :ok | {:error, term()}
  def cast(server, signal, opts \\ []), do: Worker.cast(server, signal, opts)

  @doc """
  Submits one Signal and returns an owner-bound pending Turn.

  Accepts `:admission_timeout` and `:context` as in `call/3`. The handle
  confirms submission. Use `await/2` to read acceptance or rejection.

  Set `:turn_id` to a nonempty string when durable product data must name the Turn before
  submission. Set `result_handoff: true` when a process-neutral result must
  survive caller or Instance loss. Read and acknowledge that result through
  the stable Address functions on `Jido`.
  """
  @spec submit(server(), Signal.t(), keyword()) :: Pending.t() | {:error, term()}
  def submit(server, signal, opts \\ []), do: Worker.submit(server, signal, opts)

  @doc """
  Waits for one pending Turn result in the process that submitted the request.

  The default wait is 5,000 ms. A timeout returns `{:error, :timeout}`.
  You can wait again. Collect the result once. If the worker exits before
  the reply, the result is a transport error.
  """
  @spec await(Pending.t(), timeout()) :: {:ok, TurnResult.t()} | {:error, term()}
  def await(pending, timeout \\ 5_000), do: Worker.await(pending, timeout)

  @doc """
  Discards reply tracking for one pending Turn.

  Call from the submitting process. The Turn can continue. The handle can
  no longer be used after abandonment.
  """
  @spec abandon(Pending.t()) :: :ok | {:error, term()}
  def abandon(pending), do: Worker.abandon(pending)

  @doc """
  Cancels the matching active or waiting Turn and confirms cleanup.

  The match also covers a pending Handoff in the active chain. A distinct
  queued ID returns `{:error, :stale_turn}` while another Turn is active.
  Use `quiesce/2` to reject queued requests.

  The default caller wait is 5,000 ms. An OTP timeout leaves the
  cancellation request in effect. A faulted worker returns
  `{:error, :reconciliation_required}`.
  """
  @spec cancel_turn(server(), String.t(), timeout()) :: :ok | {:error, term()}
  def cancel_turn(server, turn_id, timeout \\ 5_000),
    do: Worker.cancel_turn(server, turn_id, timeout)

  @doc """
  Closes admission, rejects queued requests, and returns a settled status.

  The default `active: :finish` lets accepted work settle. Use
  `active: :cancel` to cancel pre-commit work. Wait for saves and effects
  already in progress. Set `:timeout` to a finite drain budget. The default
  is 5,000 ms. If the budget expires, admission stays closed. Call
  `resume/2` after the worker settles.
  """
  @spec quiesce(server(), keyword()) :: {:ok, Status.t()} | {:error, term()}
  def quiesce(server, opts \\ []), do: Worker.quiesce(server, opts)

  @doc """
  Reopens admission after the resident activation settles.

  The caller wait defaults to 5,000 ms. Rejected requests must be submitted
  again. Admission stays closed while a stop or other control is in progress.
  """
  @spec resume(server(), timeout()) :: {:ok, Status.t()} | {:error, term()}
  def resume(server, timeout \\ 5_000), do: Worker.resume(server, timeout)

  @doc """
  Removes one declared topology member slot from the current activation.

  The operation closes admission for the selected member and all of its owned
  descendants. It then finishes accepted Turns by default and stops
  descendants before their parent. Use `active: :cancel` to cancel pre-commit
  work. `timeout:` is a finite budget and defaults to 5,000 ms.

  The root stays active. The declared topology and durable child records stay
  unchanged. A replacement root activation creates the declared member again
  and restores its saved state when persistence is enabled.

  A repeated call for the same removed slot returns `:ok`. If a timeout or
  shutdown error occurs after removal starts, the function returns
  `{:error, {:topology_removal_incomplete, reason}}`. Admission stays closed
  for members that entered removal, and a repeated call continues cleanup.
  """
  @spec remove_topology_member(server(), atom(), pos_integer(), keyword()) ::
          :ok | {:error, term()}
  def remove_topology_member(server, name, slot, opts \\ []),
    do: Topology.remove_member(server, name, slot, opts)

  @doc """
  Closes admission and finishes accepted work before stopping the activation.

  Returns the final committed snapshot after the activation exits. The
  default reason is `:shutdown`. Pass a finite timeout in milliseconds.
  The default is 5,000 ms. If the drain times out, admission stays closed.
  """
  @spec stop(server(), term(), timeout()) :: {:ok, Snapshot.t()} | {:error, term()}
  def stop(server, reason \\ :shutdown, timeout \\ 5_000),
    do: Worker.stop(server, reason, timeout)

  @doc "Returns the committed Agent and both revisions in one read. The default wait is 5,000 ms."
  @spec snapshot(server(), timeout()) :: Snapshot.t() | {:error, term()}
  def snapshot(server, timeout \\ 5_000), do: Worker.snapshot(server, timeout)

  @doc "Returns the semantic state of the resident activation. The default wait is 5,000 ms."
  @spec status(server(), timeout()) :: Status.t() | {:error, term()}
  def status(server, timeout \\ 5_000), do: Worker.status(server, timeout)

  @doc """
  Waits for restore and Plugin startup. The default wait is 5,000 ms.

  Expiry returns `{:error, :timeout}` and startup can continue. Read
  `status/2` to check whether admission is open.
  """
  @spec await_ready(server(), timeout()) :: :ok | {:error, term()}
  def await_ready(server, timeout \\ 5_000), do: Worker.await_ready(server, timeout)
end
