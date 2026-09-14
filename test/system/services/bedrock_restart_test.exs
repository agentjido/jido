defmodule JidoTest.System.Services.BedrockRestart do
  use ExUnit.Case, async: false

  alias Jido.Persistence
  alias Jido.Persistence.Bedrock
  alias JidoTest.BedrockIntegration
  alias JidoTest.BedrockIntegration.TestRepo
  alias JidoTest.Persistence.AdapterConformance

  @moduletag :tmp_dir
  @moduletag :service
  @moduletag adapter: :bedrock
  @moduletag skip: "Bedrock service suite paused pending upstream fixes (bedrock-kv/bedrock#319)"
  @moduletag timeout: 60_000

  defmodule Counter do
    use Jido.Agent, name: "bedrock_persistence_counter"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end
  end

  setup %{tmp_dir: tmp_dir} do
    :ok = BedrockIntegration.start!(tmp_dir, &on_exit/1)

    opts = [
      repo: TestRepo,
      prefix: "jido-v3-integration/",
      timeout_in_ms: 10_000
    ]

    {:ok, opts: opts, store: {Bedrock, opts}}
  end

  test "real Bedrock transactions satisfy CAS and Jido record lifecycle", %{
    opts: opts,
    store: store
  } do
    assert :ok = AdapterConformance.assert_binary_get_and_cas(Bedrock, opts, :real_bedrock)

    agent = Counter.new!(id: "counter")

    assert :ok = Persistence.save_agent(store, agent, revision: 0)
    assert :ok = BedrockIntegration.restart!()
    assert {:ok, restored} = Persistence.load_agent(store, Counter, agent.id)
    assert restored == agent

    assert :ok = Persistence.delete_agent(store, Counter, agent.id)
    assert {:error, :deleted} = Persistence.load_agent(store, Counter, agent.id)

    assert {:error, :outer_rollback} =
             TestRepo.transact(fn ->
               assert :ok =
                        Bedrock.compare_and_swap(
                          "isolated-write",
                          :not_found,
                          "committed",
                          opts
                        )

               TestRepo.rollback(:outer_rollback)
             end)

    assert {:ok, "committed"} = Bedrock.get("isolated-write", opts)
  end
end
