Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoTest.Authoring.Agents.ExecutionTest do
  use JidoTest.Case, async: false
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias JidoTest.Authoring.Agents.Corpus

  setup %{variant: variant} do
    Corpus.load!(variant)
    {:ok, spec: Corpus.spec(variant)}
  end

  for variant <- Corpus.variants(), form <- Corpus.forms() do
    @tag variant: variant, form: form
    test "#{variant}/#{form}: direct and live state sequence", %{
      spec: spec,
      form: form,
      jido: jido
    } do
      instance = Corpus.instance(spec, Corpus.definition(spec, form), "execution")
      assert {:ok, server} = Jido.start_agent(jido, instance)

      {_last, commits} =
        Enum.reduce(spec.steps, {instance, 0}, fn {type, data, expected}, {previous, commits} ->
          signal = Jido.Signal.new!(type, data, source: spec.source)

          case expected do
            {:error, error_module} ->
              before = Server.snapshot(server)
              assert {:error, direct_error} = Agent.cmd(previous, signal)
              assert direct_error.__struct__ == error_module
              assert {:error, live_error} = Server.call(server, signal)
              assert live_error.__struct__ == error_module
              assert Server.snapshot(server) === before
              {previous, commits}

            state when is_map(state) ->
              assert {:ok, candidate, []} = Agent.cmd(previous, signal)
              assert candidate.state === state
              assert {:ok, ^candidate} = Server.call(server, signal)
              {candidate, commits + 1}
          end
        end)

      assert Server.snapshot(server).state_version == commits
    end
  end
end
