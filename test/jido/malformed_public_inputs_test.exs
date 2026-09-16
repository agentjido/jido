defmodule JidoTest.MalformedPublicInputsTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.{Builder, Extension, Turn}
  alias Jido.Error.ValidationError
  alias Jido.Persistence
  alias Jido.Signal
  alias JidoTest.AgentFixtures.Add

  defmodule BrokenDefinition do
    def __agent_config__, do: []
    def definition, do: raise("invalid generated definition")
  end

  test "a broken module definition returns a Builder error with its cause" do
    assert {:error, %ValidationError{details: details}} =
             BrokenDefinition |> Builder.new() |> Builder.build()

    assert details.module == BrokenDefinition
    assert %RuntimeError{message: "invalid generated definition"} = details.reason
  end

  test "extension lowering rejects improper lists and non-map config" do
    for {extensions, config, entities} <- [
          {[BrokenDefinition | :invalid], %{}, []},
          {[], %{}, [1 | :invalid]},
          {[], nil, []},
          {[], %URI{}, []}
        ] do
      assert {:error, %ValidationError{}} = Extension.lower(extensions, config, entities)
    end
  end

  test "direct command options must be a proper keyword list" do
    agent = Agent.new!(name: "malformed_command") |> Agent.instantiate!(id: "cmd")
    signal = Signal.new!("input.invalid", %{}, source: "/test")

    for opts <- [[1], [{:context, %{}}, 1], [{:context, %{}} | :invalid], nil] do
      assert {:error, %ValidationError{}} = Agent.cmd(agent, signal, opts)
    end
  end

  test "Turn input accepts maps and keyword lists but rejects malformed lists" do
    assert {:ok, %Turn{}} = Turn.new(Add, %{by: 1})
    assert {:ok, %Turn{}} = Turn.new(Add, by: 1)

    for input <- [[1], [{:by, 1}, 2], [{:by, 1} | :invalid]] do
      assert {:error, %ValidationError{subject: :input}} = Turn.new(Add, input)
    end
  end

  test "Persistence rejects wrong Agent, module, and ID inputs" do
    source = {Jido.Persistence.ETS, table: :malformed_public_inputs}

    assert {:error, %ValidationError{}} = Persistence.save_agent(source, :not_an_agent)

    for operation <- [:load_agent, :load_agent_with_revision, :delete_agent] do
      assert {:error, %ValidationError{}} = apply(Persistence, operation, [source, 123, "id"])
      assert {:error, %ValidationError{}} = apply(Persistence, operation, [source, Agent, 123])
    end
  end

  test "Ref creation rejects wrong ID and unknown options" do
    instance = :"malformed_ref_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: instance, namespace: "malformed/ref"}, id: instance)

    assert {:ok, _ref} = Jido.agent_ref(instance, "agent-1", partition: nil)
    assert {:error, %ValidationError{}} = Jido.agent_ref(instance, 123)
    assert {:error, %ValidationError{}} = Jido.agent_ref(instance, "agent-1", extra: true)
  end

  test "compatibility lookup, list, count, and stop report malformed options", %{jido: jido} do
    assert nil == Jido.whereis_agent(jido, "missing")
    assert {:error, :not_found} = Jido.stop_agent(jido, "missing")

    for opts <- [[1], [{:partition, nil}, 1], [{:partition, nil} | :invalid]] do
      assert {:error, %ValidationError{}} = Jido.whereis_agent(jido, "missing", opts)
      assert {:error, %ValidationError{}} = Jido.list_agents(jido, opts)
      assert {:error, %ValidationError{}} = Jido.agent_count(jido, opts)
      assert {:error, %ValidationError{}} = Jido.stop_agent(jido, "missing", opts)
    end

    assert {:error, %ValidationError{}} = Jido.whereis_agent(jido, 123)
    assert {:error, %ValidationError{}} = Jido.stop_agent(jido, 123)
  end
end
