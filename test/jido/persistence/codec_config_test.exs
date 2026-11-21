defmodule Jido.Persistence.CodecConfigTest do
  use ExUnit.Case, async: true

  alias Jido.Persistence
  alias Jido.Persistence.{Codec, Config, ETS, File, Inspector, NamespaceManifest, Store}
  alias Jido.Test.AgentServer.Fixtures.CounterAgent

  setup do
    table = :"codec_config_#{System.unique_integer([:positive])}"
    %{store: {ETS, table: table}}
  end

  test "Store declarations use Term and JSON is opt-in", %{store: store} do
    assert {:ok, %Config{store: ^store, codec: Codec.Term}} = Config.open(store)

    assert {:ok, %Config{store: ^store, codec: Codec.JSON}} =
             Config.open(store: store, codec: Codec.JSON)

    assert {:error, {:duplicate_persistence_profile_options, [:codec]}} =
             Config.open(store: store, codec: Codec.Term, codec: Codec.JSON)

    assert {:error, {:unknown_persistence_profile_options, [:unknown]}} =
             Config.open(store: store, unknown: true)
  end

  test "JSON round-trips supported Elixir values and rejects release-local values" do
    value = %{
      atom: :ok,
      binary: <<0, 255>>,
      list: [1, true, nil],
      module: CounterAgent,
      tuple: {:ok, 2},
      struct: URI.parse("https://jido.run/path")
    }

    assert {:ok, bytes} = Codec.JSON.encode(value)
    assert {:ok, ^value} = Codec.JSON.decode(bytes, [])
    assert {:error, {:unsupported_persistence_value, :pid}} = Codec.JSON.encode(self())

    unknown = "persistence_unknown_atom_#{System.unique_integer([:positive])}"

    encoded =
      JSON.encode!(%{
        "codec" => "jido.json",
        "codec_version" => 1,
        "value" => %{"$jido" => "atom", "name" => unknown}
      })

    assert {:error, {:unknown_persistence_atom, ^unknown}} = Codec.JSON.decode(encoded, [])
  end

  test "Agent records use the selected JSON codec", %{store: store} do
    profile = [store: store, codec: Codec.JSON]
    agent = CounterAgent.instantiate!(id: "json-agent")

    assert :ok = Persistence.save_agent(profile, agent, namespace: "json-profile")
    assert {:ok, ^agent} = Persistence.load_agent(profile, CounterAgent, agent.id, namespace: "json-profile")

    address = Jido.Agent.Address.new!(namespace: "json-profile", id: agent.id)
    assert {:ok, raw, _condition} = Store.read(store, Persistence.agent_key(address))
    assert {:ok, %{"codec" => "jido.json", "codec_version" => 1}} = JSON.decode(raw)
  end

  test "namespace manifest pins codec and formats", %{store: store} do
    {:ok, term} = Config.open(store)
    {:ok, json} = Config.open(store: store, codec: Codec.JSON)

    assert :ok = NamespaceManifest.open(term, "manifest")
    assert :ok = NamespaceManifest.open(term, "manifest")

    assert {:ok,
            %{
              codec: %{id: "jido.term", version: 1},
              records: %{agent: 3, execution: 3, wake: 3},
              wake: %{bucket_ms: 60_000, shards: 64}
            }} = NamespaceManifest.read(term, "manifest")

    assert {:error, {:persistence_namespace_mismatch, _expected, _actual}} =
             NamespaceManifest.open(json, "manifest")
  end

  test "inspection redacts state and export emits paged JSONL", %{store: store} do
    {:ok, config} = Config.open(store)
    agent = CounterAgent.instantiate!(id: "inspected-agent", state: %{count: 7})
    address = Jido.Agent.Address.new!(namespace: "inspection", id: agent.id)
    key = Persistence.agent_key(address)
    assert :ok = Persistence.save_agent(config, agent, namespace: address.namespace)

    assert {:ok, redacted} = Inspector.read(config, key)
    assert redacted.checkpoint.agent.state == "[REDACTED]"

    assert {:ok, full} = Inspector.read(config, key, full: true)
    assert full.checkpoint.agent.state.count == 7

    {:ok, io} = StringIO.open("")
    assert {:ok, 1} = Inspector.export_jsonl(config, "jido:agent:v3:", io, limit: 1)
    {_input, output} = StringIO.contents(io)
    assert {:ok, %{"key" => ^key, "record" => record}} = JSON.decode(output)
    assert record["entries"] != nil
  end

  test "inspection projects execution values unless full output is explicit", %{store: store} do
    {:ok, config} = Config.open(store)
    key = "jido:execution:v3:test:batches:1"
    events = [%{event: "started", init_value: %{secret: "VISIBLE"}}]
    {:ok, bytes} = Config.encode(config, events)
    assert :ok = Store.compare_and_swap(store, key, :not_found, bytes)

    assert {:ok,
            %{
              kind: "execution_batch",
              event_count: 1,
              events: [%{kind: "map", fields: ["event", "init_value"]}]
            }} = Inspector.read(config, key)

    refute inspect(elem(Inspector.read(config, key), 1)) =~ "VISIBLE"
    assert {:ok, ^events} = Inspector.read(config, key, full: true)
  end

  test "inspection rejects invalid and old record formats", %{store: store} do
    {:ok, config} = Config.open(store)
    invalid_key = "jido:agent:v3:invalid"
    {:ok, invalid_bytes} = Config.encode(config, %{format: 3})
    assert :ok = Store.compare_and_swap(store, invalid_key, :not_found, invalid_bytes)
    assert {:error, :invalid_persistence_record} = Inspector.read(config, invalid_key)

    old_key = "jido:agent:v2:old"
    {:ok, old_bytes} = Config.encode(config, %{format: 2})
    assert :ok = Store.compare_and_swap(store, old_key, :not_found, old_bytes)
    assert {:error, :unsupported_persistence_record} = Inspector.read(config, old_key)
  end

  test "File with JSON stores parseable documents and supports JSONL export" do
    path = Path.join(System.tmp_dir!(), "jido-json-file-#{System.unique_integer([:positive])}")
    on_exit(fn -> Elixir.File.rm_rf!(path) end)

    {:ok, config} = Config.open(store: {File, path: path}, codec: Codec.JSON)
    assert :ok = NamespaceManifest.open(config, "json-file")

    agent = CounterAgent.instantiate!(id: "json-file-agent", state: %{count: 4})
    assert :ok = Persistence.save_agent(config, agent, namespace: "json-file")

    for record_file <- Path.wildcard(Path.join(path, "records/*.bin")) do
      assert {:ok, %{"codec" => "jido.json"}} = record_file |> Elixir.File.read!() |> JSON.decode()
    end

    {:ok, io} = StringIO.open("")
    assert {:ok, 2} = Inspector.export_jsonl(config, "jido:", io, limit: 1)
    {_input, output} = StringIO.contents(io)

    assert output
           |> String.split("\n", trim: true)
           |> Enum.all?(fn line -> match?({:ok, %{"key" => _, "record" => _}}, JSON.decode(line)) end)
  end

  test "JSON rejects a struct with missing fields" do
    {:ok, encoded} = Codec.JSON.encode(URI.parse("https://jido.run/path"))
    {:ok, envelope} = JSON.decode(encoded)
    fields = get_in(envelope, ["value", "fields"])
    truncated = put_in(envelope, ["value", "fields"], tl(fields))

    assert {:error, {:invalid_persistence_struct_fields, "Elixir.URI"}} =
             truncated |> JSON.encode!() |> Codec.JSON.decode([])
  end
end
