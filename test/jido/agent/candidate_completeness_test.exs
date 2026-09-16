defmodule JidoTest.Agent.CandidateCompletenessTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  defmodule Partial do
    use Jido.Action, name: "candidate_completeness_partial"

    def run(_params, _context), do: {:ok, %{count: 1}}
  end

  defmodule ClearOptional do
    use Jido.Action, name: "candidate_completeness_clear_optional"

    def run(_params, _context), do: {:ok, %{count: 1, history: []}}
  end

  defmodule Counter do
    use Jido.Agent,
      name: "candidate_completeness_counter",
      schema:
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.default(0),
          history: Zoi.list(Zoi.string()) |> Zoi.default([]),
          note: Zoi.string() |> Zoi.optional()
        }),
      routes: [
        {"candidate.partial", Partial},
        {"candidate.clear", ClearOptional}
      ]
  end

  test "direct and live Turns reject a candidate that omits a defaulted field", %{jido: jido} do
    initial = Counter.new!(id: unique_id("partial"), state: %{history: ["old"]})
    signal = Signal.new!("candidate.partial", %{}, source: "/test")

    assert {:error, %Jido.Error.ValidationError{details: %{missing_keys: [:history]}}} =
             Counter.cmd(initial, signal)

    assert {:ok, server} = Jido.start_agent(jido, initial)
    before = Server.snapshot(server)

    assert {:error, %Jido.Error.ValidationError{details: %{missing_keys: [:history]}}} =
             Server.call(server, signal)

    assert Server.snapshot(server) == before
  end

  test "a candidate can omit a field that has no default", %{jido: jido} do
    initial = Counter.new!(id: unique_id("optional"), state: %{note: "old"})
    signal = Signal.new!("candidate.clear", %{}, source: "/test")

    assert {:ok, direct, []} = Counter.cmd(initial, signal)
    assert direct.state == %{count: 1, history: []}

    assert {:ok, server} = Jido.start_agent(jido, initial)
    assert {:ok, live} = Server.call(server, signal)
    assert live.state == direct.state
  end
end
