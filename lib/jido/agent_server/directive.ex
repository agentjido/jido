defmodule Jido.AgentServer.Directive do
  @moduledoc """
  Runtime requests. AgentServer runs them after it commits the Agent value.

  Topology edits belong to `Jido.Agent.Directive`. These records request
  runtime work after commit. Activation ownership is fixed at startup.
  """
  alias Jido.Agent.Directive.{AgentSend, Emit, ParentSend, Reply, ServerStop}
  alias Jido.AgentServer.Directive.ErrorReport
  alias Jido.AgentServer.Directive.AgentStart
  alias Jido.AgentServer.Directive.ProcessStart
  alias Jido.AgentServer.Directive.AgentStop
  alias Jido.Signal

  @typedoc "A built-in runtime Directive that AgentServer runs after commit."
  @type t ::
          Emit.t()
          | Reply.t()
          | AgentSend.t()
          | AgentStart.t()
          | AgentStop.t()
          | ErrorReport.t()
          | ParentSend.t()
          | ProcessStart.t()
          | ServerStop.t()

  @typedoc "An OTP restart policy for an Agent started by a runtime Directive."
  @type restart_policy :: :permanent | :temporary | :transient

  @typedoc "An option for `signal_send/3`."
  @type signal_send_option ::
          {:delivery_mode, Jido.Signal.Dispatch.PidAdapter.delivery_mode()}
          | {:timeout, 1..4_294_967_295}
          | {:message_format, Jido.Signal.Dispatch.PidAdapter.message_format()}

  @typedoc "An option for `agent_start/3`."
  @type agent_start_option ::
          {:node, node() | nil}
          | {:opts, map() | keyword()}
          | {:meta, map() | keyword()}
          | {:restart, restart_policy()}

  @doc """
  Builds an Emit Directive that sends one Signal to a local process.

  Options are `:delivery_mode`, `:timeout`, and `:message_format`. Unknown or
  duplicate options raise `ArgumentError`. The Signal and dispatch target are
  validated before the Agent commit.
  """
  @spec signal_send(Signal.t(), pid(), [signal_send_option()]) :: Emit.t()
  def signal_send(signal, pid, opts \\ []) when is_pid(pid),
    do: %Emit{
      signal: signal,
      dispatch: {:pid, Keyword.put(options(opts, [:delivery_mode, :timeout, :message_format]), :target, pid)}
    }

  @doc "Builds a Directive that applies the AgentServer error policy after commit."
  @spec error_report(term(), atom() | nil) :: ErrorReport.t()
  def error_report(error, context \\ nil), do: %ErrorReport{error: error, context: context}

  @doc "Builds a Directive that starts one independent OTP child under the Jido instance."
  @spec process_start(Supervisor.child_spec()) :: ProcessStart.t()
  def process_start(child_spec), do: %ProcessStart{child_spec: child_spec}

  @doc """
  Builds a Directive that starts and tracks one local Agent.

  Options are `:node`, `:opts`, `:meta`, and `:restart`. The `:opts` and `:meta`
  values can be plain maps or unique keyword lists. Unknown or duplicate
  options raise `ArgumentError`.
  """
  @spec agent_start(Jido.Agent.t() | module(), atom() | String.t(), [agent_start_option()]) ::
          AgentStart.t()
  def agent_start(agent, name, opts \\ []) do
    opts = options(opts, [:node, :opts, :meta, :restart])

    %AgentStart{
      agent: agent,
      name: name,
      node: Keyword.get(opts, :node),
      opts: option_map(opts, :opts),
      meta: option_map(opts, :meta),
      restart: Keyword.get(opts, :restart, :transient)
    }
  end

  @doc "Builds a Directive that stops and untracks one child Agent."
  @spec agent_stop(atom() | String.t(), term()) :: AgentStop.t()
  def agent_stop(name, reason \\ :normal), do: %AgentStop{name: name, reason: reason}

  defp options(opts, allowed) do
    unless Keyword.keyword?(opts) and Enum.uniq(Keyword.keys(opts)) == Keyword.keys(opts),
      do: raise(ArgumentError, "Expected unique keyword options")

    Keyword.validate!(opts, allowed)
  end

  defp option_map(opts, key) do
    case Jido.Agent.Schema.to_attrs(Keyword.get(opts, key, %{}), :reject) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "#{key} must be a plain Map or unique keyword list"
    end
  end
end
