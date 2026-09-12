defmodule Jido.AgentServer.Work do
  @moduledoc false

  defmodule Identity do
    @moduledoc false

    @enforce_keys [:id, :activation_id, :kind]
    defstruct [:id, :activation_id, :kind, :turn_id, :expected_version, :directive_index]

    @type t :: %__MODULE__{
            id: reference(),
            activation_id: String.t(),
            kind: atom(),
            turn_id: String.t() | nil,
            expected_version: non_neg_integer() | nil,
            directive_index: non_neg_integer() | nil
          }
  end

  defmodule Result do
    @moduledoc false

    @enforce_keys [:identity, :value]
    defstruct [:identity, :value]

    @type t :: %__MODULE__{identity: Identity.t(), value: term()}
  end

  @enforce_keys [:identity, :task]
  defstruct [:identity, :task, :timer, metadata: %{}]

  @type t :: %__MODULE__{
          identity: Identity.t(),
          task: Task.t(),
          timer: reference() | nil,
          metadata: map()
        }

  @doc false
  @spec start(Supervisor.supervisor(), String.t(), atom(), (-> term()), keyword()) :: t()
  def start(supervisor, activation_id, kind, fun, opts \\ [])
      when is_function(fun, 0) and is_list(opts) do
    identity = %Identity{
      id: make_ref(),
      activation_id: activation_id,
      kind: kind,
      turn_id: Keyword.get(opts, :turn_id),
      expected_version: Keyword.get(opts, :expected_version),
      directive_index: Keyword.get(opts, :directive_index)
    }

    task =
      Task.Supervisor.async(supervisor, fn ->
        %Result{identity: identity, value: fun.()}
      end)

    timer = start_timer(Keyword.get(opts, :timeout), Keyword.get(opts, :timeout_tag), task.ref)

    %__MODULE__{
      identity: identity,
      task: task,
      timer: timer,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc false
  @spec result(t(), reference(), Result.t()) :: {:ok, term()} | :stale
  def result(
        %__MODULE__{identity: identity, task: %Task{ref: ref}},
        ref,
        %Result{identity: identity, value: value}
      ),
      do: {:ok, value}

  def result(%__MODULE__{}, _ref, %Result{}), do: :stale

  @doc false
  @spec release(t()) :: :ok
  def release(%__MODULE__{task: %Task{ref: ref}, timer: timer}) do
    Process.demonitor(ref, [:flush])
    cancel_timer(timer)
  end

  @doc false
  @spec stop(t() | nil) :: :ok
  def stop(%__MODULE__{task: %Task{} = task, timer: timer}) do
    cancel_timer(timer)
    shutdown(task)
  end

  def stop(nil), do: :ok

  @doc false
  @spec shutdown(Task.t()) :: :ok
  def shutdown(%Task{} = task) do
    _result = Task.shutdown(task, :brutal_kill)
    :ok
  catch
    :exit, _reason -> :ok
  end

  @doc false
  @spec cancel_timer(reference() | nil) :: :ok
  def cancel_timer(nil), do: :ok

  def cancel_timer(timer) do
    _result = :erlang.cancel_timer(timer)
    :ok
  end

  defp start_timer(nil, _tag, _task_ref), do: nil
  defp start_timer(:infinity, _tag, _task_ref), do: nil

  defp start_timer(timeout, tag, task_ref) when is_integer(timeout) and is_atom(tag) do
    :erlang.start_timer(timeout, self(), {tag, task_ref})
  end
end
