defmodule Jido.Agent.CandidateCompletenessTest do
  use Jido.Test.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  defmodule Partial do
    use Jido.Action,
      name: "candidate_completeness_partial"

    def run(_params, _context), do: {:ok, %{count: 1}}
  end

  defmodule ClearOptional do
    use Jido.Action,
      name: "candidate_completeness_clear_optional"

    def run(_params, _context), do: {:ok, %{count: 1, history: []}}
  end

  defmodule Counter do
    use Jido.Agent, name: "candidate_completeness_counter"

    state do
      schema Jido.Joi.object(%{
               count: Jido.Joi.integer() |> Jido.Joi.default(0),
               history: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([]),
               note: Jido.Joi.string() |> Jido.Joi.optional()
             })
    end

    routes do
      route "candidate.partial", Partial

      route "candidate.clear", ClearOptional
    end
  end

  test "direct and live Turns reject a candidate that omits a defaulted field", %{jido: jido} do
    initial = Counter.instantiate!(id: unique_id("partial"), state: %{history: ["old"]})
    signal = Signal.new!("candidate.partial", %{}, source: "/test")

    assert {:error,
            %Jido.Error.ValidationError{
              code: :incomplete_state,
              details: %{issues: [%{path: [:history]}]}
            }} =
             Counter.cmd(initial, signal)

    assert {:ok, server} = Jido.Test.AgentServer.Assertions.start_agent(jido, initial)
    before = Jido.Test.AgentServer.Assertions.committed(server)

    assert {:ok,
            %Jido.AgentServer.TurnResult{
              status: :failed,
              error: %Jido.Error.ValidationError{
                code: :incomplete_state,
                details: %{issues: [%{path: [:history]}]}
              }
            }} = Server.call(server, signal)

    assert Jido.Test.AgentServer.Assertions.committed(server) == before
  end

  test "a candidate can omit a field that has no default", %{jido: jido} do
    initial = Counter.instantiate!(id: unique_id("optional"), state: %{note: "old"})
    signal = Signal.new!("candidate.clear", %{}, source: "/test")

    assert {:ok, direct, []} = Counter.cmd(initial, signal)
    assert direct.state == %{count: 1, history: []}

    assert {:ok, server} = Jido.Test.AgentServer.Assertions.start_agent(jido, initial)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = Server.call(server, signal)
    live = Server.snapshot(server).agent
    assert live.state == direct.state
  end
end
