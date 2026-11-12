defmodule Jido.AgentServer do
  @moduledoc """
  Runs one resident Agent activation.

  All Signal request modes use one serialized Turn path. Direct server handles
  address only the current activation. Use `Jido.Agent.Ref` through the Jido
  Instance when work must survive passivation or worker replacement.
  """

  alias Jido.AgentServer.{Pending, Snapshot, Status, TurnResult, Worker}
  alias Jido.Signal

  @typedoc "A local handle for one resident Agent activation."
  @type server :: :gen_statem.server_ref()

  @doc "Returns a child specification for one complete Agent activation."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts), do: Worker.child_spec(opts)

  @doc "Runs one Signal and waits for its accepted Turn result."
  @spec call(server(), Signal.t(), timeout() | keyword()) ::
          {:ok, TurnResult.t()} | {:error, term()}
  def call(server, signal, timeout_or_opts \\ 5_000),
    do: Worker.call(server, signal, timeout_or_opts)

  @doc "Sends one Signal through the same Turn path without waiting for its result."
  @spec cast(server(), Signal.t(), keyword()) :: :ok | {:error, term()}
  def cast(server, signal, opts \\ []), do: Worker.cast(server, signal, opts)

  @doc "Submits one Signal and returns an owner-bound pending Turn."
  @spec submit(server(), Signal.t(), keyword()) :: Pending.t() | {:error, term()}
  def submit(server, signal, opts \\ []), do: Worker.submit(server, signal, opts)

  @doc "Waits for one pending Turn result."
  @spec await(Pending.t(), timeout()) :: {:ok, TurnResult.t()} | {:error, term()}
  def await(pending, timeout \\ 5_000), do: Worker.await(pending, timeout)

  @doc "Stops local waiting for one pending Turn without cancelling the Turn."
  @spec abandon(Pending.t()) :: :ok | {:error, term()}
  def abandon(pending), do: Worker.abandon(pending)

  @doc "Cancels the exact queued, running, or waiting Turn."
  @spec cancel_turn(server(), String.t(), timeout()) :: :ok | {:error, term()}
  def cancel_turn(server, turn_id, timeout \\ 5_000),
    do: Worker.cancel_turn(server, turn_id, timeout)

  @doc "Closes admission and returns a stable resident status."
  @spec quiesce(server(), keyword()) :: {:ok, Status.t()} | {:error, term()}
  def quiesce(server, opts \\ []), do: Worker.quiesce(server, opts)

  @doc "Reopens admission when the resident activation is safe."
  @spec resume(server(), timeout()) :: {:ok, Status.t()} | {:error, term()}
  def resume(server, timeout \\ 5_000), do: Worker.resume(server, timeout)

  @doc "Stops one resident activation and returns its committed snapshot."
  @spec stop(server(), term(), timeout()) :: {:ok, Snapshot.t()} | {:error, term()}
  def stop(server, reason \\ :shutdown, timeout \\ 5_000),
    do: Worker.stop(server, reason, timeout)

  @doc "Returns the complete committed Agent snapshot for this activation."
  @spec snapshot(server(), timeout()) :: Snapshot.t() | {:error, term()}
  def snapshot(server, timeout \\ 5_000), do: Worker.snapshot(server, timeout)

  @doc "Returns the semantic state of this resident activation."
  @spec status(server(), timeout()) :: Status.t() | {:error, term()}
  def status(server, timeout \\ 5_000), do: Worker.status(server, timeout)

  @doc "Waits until this resident activation is ready for input."
  @spec await_ready(server(), timeout()) :: :ok | {:error, term()}
  def await_ready(server, timeout \\ 5_000), do: Worker.await_ready(server, timeout)
end
