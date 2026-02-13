defmodule JidoTest.Support.FSMRuntimeHelper do
  @moduledoc false

  alias Jido.Agent.Directive
  alias Jido.AgentServer.{DirectiveExec, Options, State}
  alias Jido.Signal

  @doc false
  @spec run_cmd(module(), struct(), term()) :: {struct(), [struct()]}
  def run_cmd(agent_module, agent, action) do
    {agent, directives} = agent_module.cmd(agent, action)
    run_directives(agent_module, agent, directives)
  end

  @doc false
  @spec run_directives(module(), struct(), [struct()]) :: {struct(), [struct()]}
  def run_directives(agent_module, agent, directives) when is_list(directives) do
    state = build_state(agent_module, agent)

    input_signal =
      Signal.new!(%{
        type: "test.runtime",
        source: "/test/runtime",
        data: %{}
      })

    {:ok, state} = State.enqueue_all(state, input_signal, directives)
    {state, buffered_directives} = drain_run_instructions(state, [])
    {state.agent, Enum.reverse(buffered_directives)}
  end

  defp build_state(agent_module, agent) do
    opts =
      Options.new!(%{
        agent: agent,
        id: agent.id || "test-agent"
      })

    {:ok, state} = State.from_options(opts, agent_module, agent)
    state
  end

  defp drain_run_instructions(state, buffered_directives) do
    case State.dequeue(state) do
      {:empty, state} ->
        {state, buffered_directives}

      {{:value, {signal, %Directive.RunInstruction{} = directive}}, state} ->
        case DirectiveExec.exec(directive, signal, state) do
          {:ok, state} ->
            drain_run_instructions(state, buffered_directives)

          {:async, _ref, state} ->
            drain_run_instructions(state, buffered_directives)

          {:stop, reason, _state} ->
            raise "RunInstruction unexpectedly stopped: #{inspect(reason)}"
        end

      {{:value, {_signal, directive}}, state} ->
        drain_run_instructions(state, [directive | buffered_directives])
    end
  end
end
