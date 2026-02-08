defmodule Jido.Scheduler do
  @moduledoc """
  Per-instance cron scheduling using SchedEx.

  This module provides a thin wrapper around SchedEx for scheduling recurring
  cron jobs that are scoped to individual agents. Unlike a global scheduler,
  each cron job is supervised as part of the agent's process tree.

  ## Usage

  Jobs are typically created via the `%Directive.Cron{}` directive, which
  internally uses this module. You can also use it directly:

      # Start a cron job that calls a function every minute
      {:ok, pid} = Jido.Scheduler.run_every(MyModule, :tick, [arg1], "* * * * *")

      # Cancel the job
      Jido.Scheduler.cancel(pid)

  ## Cron Expressions

  Standard 5-field cron expressions are supported:

  - `"* * * * *"` - Every minute
  - `"*/5 * * * *"` - Every 5 minutes
  - `"0 * * * *"` - Every hour
  - `"0 0 * * *"` - Daily at midnight
  - `"0 0 * * MON"` - Every Monday at midnight

  Extended 7-field expressions (with seconds and year) are also supported.

  ## Aliases

  - `@yearly` / `@annually` - Once a year at midnight Jan 1
  - `@monthly` - Once a month at midnight on the 1st
  - `@weekly` - Once a week at midnight on Sunday
  - `@daily` / `@midnight` - Once a day at midnight
  - `@hourly` - Once an hour at the beginning of the hour

  See `Jido.Agent.Directive.Cron` for directive-based usage.
  """

  @doc """
  Starts a recurring cron job.

  Returns `{:ok, pid}` where `pid` is the SchedEx process that can be
  used to cancel the job later.

  ## Options

  - `:timezone` - Timezone for the cron expression (default: "Etc/UTC")

  ## Examples

      {:ok, pid} = Jido.Scheduler.run_every(MyModule, :work, [], "*/5 * * * *")
      {:ok, pid} = Jido.Scheduler.run_every(fn -> IO.puts("tick") end, "* * * * *")
  """
  @spec run_every(module(), atom(), list(), String.t(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def run_every(module, function, args, cron_expr, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "Etc/UTC")

    SchedEx.run_every(
      module,
      function,
      args,
      cron_expr,
      timezone: timezone
    )
  end

  @doc """
  Starts a recurring cron job with a function.

  ## Examples

      {:ok, pid} = Jido.Scheduler.run_every(fn -> IO.puts("tick") end, "* * * * *")
  """
  @spec run_every((-> any()), String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def run_every(fun, cron_expr, opts \\ []) when is_function(fun, 0) do
    timezone = Keyword.get(opts, :timezone, "Etc/UTC")

    SchedEx.run_every(
      fun,
      cron_expr,
      timezone: timezone
    )
  end

  @doc """
  Cancels a running cron job.

  ## Examples

      {:ok, pid} = Jido.Scheduler.run_every(MyModule, :work, [], "* * * * *")
      :ok = Jido.Scheduler.cancel(pid)
  """
  @spec cancel(pid()) :: :ok
  def cancel(pid) when is_pid(pid) do
    SchedEx.cancel(pid)
  catch
    :exit, _ -> :ok
  end

  @doc """
  Checks if a cron job process is still alive.
  """
  @spec alive?(pid()) :: boolean()
  def alive?(pid) when is_pid(pid) do
    Process.alive?(pid)
  end
end
