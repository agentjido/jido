defmodule Jido.Scheduler do
  @moduledoc """
  Per-agent cron scheduling with internal timer processes.

  `Jido.Scheduler` is intentionally lightweight and process-local:
  each registered cron job is backed by a dedicated process owned by the
  caller (typically the owning `Jido.AgentServer`).

  The runtime stores live job processes in `AgentServer.State.cron_jobs` and
  separately stores durable schedule definitions in `AgentServer.State.cron_specs`.
  The durable specs are persisted through `Jido.Persist` for InstanceManager-
  managed agents.
  """

  alias Jido.Scheduler.Job

  @cron_specs_state_key :__cron_specs__
  @default_timezone "Etc/UTC"

  @type cron_spec :: %{
          required(:cron_expression) => String.t(),
          required(:message) => term(),
          required(:timezone) => String.t()
        }

  @doc """
  Reserved internal agent-state key used to stage durable cron specs across
  hibernate/thaw boundaries.
  """
  @spec cron_specs_state_key() :: atom()
  def cron_specs_state_key, do: @cron_specs_state_key

  @doc """
  Build a normalized durable cron spec map.
  """
  @spec build_cron_spec(String.t(), term(), String.t() | nil) :: cron_spec()
  def build_cron_spec(cron_expression, message, timezone \\ nil)
      when is_binary(cron_expression) do
    %{
      cron_expression: cron_expression,
      message: message,
      timezone: normalize_timezone(timezone)
    }
  end

  @doc """
  Normalize a persisted cron-spec map, dropping malformed entries.
  """
  @spec normalize_cron_specs(term()) :: %{optional(term()) => cron_spec()}
  def normalize_cron_specs(specs) when is_map(specs) do
    Enum.reduce(specs, %{}, fn {job_id, spec}, acc ->
      case normalize_cron_spec(spec) do
        {:ok, normalized} -> Map.put(acc, job_id, normalized)
        :error -> acc
      end
    end)
  end

  def normalize_cron_specs(_), do: %{}

  @doc """
  Starts a recurring cron job.

  Returns `{:ok, pid}` where `pid` is the scheduler job process that can be
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
    run_every(fn -> apply(module, function, args) end, cron_expr, opts)
  end

  @doc """
  Starts a recurring cron job with a function.

  ## Examples

      {:ok, pid} = Jido.Scheduler.run_every(fn -> IO.puts("tick") end, "* * * * *")
  """
  @spec run_every((-> any()), String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def run_every(fun, cron_expr, opts \\ [])
      when is_function(fun, 0) and is_binary(cron_expr) and is_list(opts) do
    with {:ok, timezone} <- validate_timezone_opt(Keyword.get(opts, :timezone)) do
      try do
        Job.start(fun, cron_expr, timezone)
      catch
        :exit, reason ->
          {:error, reason}
      end
    end
  end

  @doc """
  Cancels a running cron job.

  ## Examples

      {:ok, pid} = Jido.Scheduler.run_every(MyModule, :work, [], "* * * * *")
      :ok = Jido.Scheduler.cancel(pid)
  """
  @spec cancel(pid()) :: :ok
  def cancel(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        GenServer.stop(pid, :normal, 5_000)
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  @doc """
  Checks if a cron job process is still alive.
  """
  @spec alive?(pid()) :: boolean()
  def alive?(pid) when is_pid(pid) do
    Process.alive?(pid)
  end

  @spec normalize_cron_spec(term()) :: {:ok, cron_spec()} | :error
  defp normalize_cron_spec(spec) when is_map(spec) do
    cron_expression = map_get(spec, :cron_expression)
    timezone = map_get(spec, :timezone)

    cond do
      not is_binary(cron_expression) ->
        :error

      true ->
        {:ok,
         %{
           cron_expression: cron_expression,
           message: map_get(spec, :message),
           timezone: normalize_timezone(timezone)
         }}
    end
  end

  defp normalize_cron_spec(_), do: :error

  defp map_get(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp normalize_timezone(nil), do: @default_timezone
  defp normalize_timezone(""), do: @default_timezone
  defp normalize_timezone(timezone) when is_binary(timezone), do: timezone
  defp normalize_timezone(_), do: @default_timezone

  @spec validate_timezone_opt(term()) :: {:ok, String.t()} | {:error, term()}
  defp validate_timezone_opt(nil), do: {:ok, @default_timezone}
  defp validate_timezone_opt(""), do: {:ok, @default_timezone}
  defp validate_timezone_opt(timezone) when is_binary(timezone), do: {:ok, timezone}
  defp validate_timezone_opt(_), do: {:error, :invalid_timezone}
end
