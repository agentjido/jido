defmodule Jido.Runtime.Tasking do
  @moduledoc """
  Shared helpers for resolving and running async work under task supervisors.

  This module centralizes task supervisor lookup so runtime components use a
  consistent resolution order and error semantics.
  """

  @system_task_supervisor Jido.SystemTaskSupervisor

  @type task_supervisor :: atom()
  @type resolve_error :: :task_supervisor_not_found
  @type start_error :: :task_supervisor_not_found | term()

  @doc """
  Resolves the first alive task supervisor from the configured candidates.

  ## Options

  - `:candidates` - Explicit list of supervisor names to check in order
  - `:jido` - Jido instance name used to derive `Jido.task_supervisor_name/1`
  - `:include_system?` - Include the system supervisor fallback (default: `true`)
  - `:system_supervisor` - Override the system supervisor name
  """
  @spec resolve_task_supervisor(keyword()) :: {:ok, task_supervisor()} | {:error, resolve_error()}
  def resolve_task_supervisor(opts \\ []) do
    opts
    |> supervisor_candidates()
    |> Enum.find_value({:error, :task_supervisor_not_found}, fn supervisor ->
      if supervisor_alive?(supervisor), do: {:ok, supervisor}, else: false
    end)
  end

  @doc """
  Starts a child task under the first resolved supervisor.

  Returns `{:error, :task_supervisor_not_found}` when no candidate supervisor
  is currently running.
  """
  @spec start_child((-> any()), keyword()) :: {:ok, pid()} | {:error, start_error()}
  def start_child(fun, opts \\ []) when is_function(fun, 0) do
    with {:ok, task_supervisor} <- resolve_task_supervisor(opts) do
      Task.Supervisor.start_child(task_supervisor, fun)
    end
  end

  defp supervisor_candidates(opts) do
    case Keyword.get(opts, :candidates) do
      candidates when is_list(candidates) ->
        normalize_candidates(candidates)

      _ ->
        jido = Keyword.get(opts, :jido)
        include_system? = Keyword.get(opts, :include_system?, true)
        system_supervisor = Keyword.get(opts, :system_supervisor, @system_task_supervisor)

        []
        |> maybe_put_jido_supervisor(jido)
        |> maybe_put_system_supervisor(include_system?, system_supervisor)
        |> normalize_candidates()
    end
  end

  defp maybe_put_jido_supervisor(candidates, jido) when is_atom(jido) do
    candidates ++ [Jido.task_supervisor_name(jido)]
  end

  defp maybe_put_jido_supervisor(candidates, _), do: candidates

  defp maybe_put_system_supervisor(candidates, true, supervisor), do: candidates ++ [supervisor]
  defp maybe_put_system_supervisor(candidates, false, _supervisor), do: candidates

  defp normalize_candidates(candidates) do
    candidates
    |> Enum.filter(&is_atom/1)
    |> Enum.uniq()
  end

  defp supervisor_alive?(supervisor) when is_atom(supervisor) do
    case Process.whereis(supervisor) do
      pid when is_pid(pid) -> true
      _ -> false
    end
  end
end
