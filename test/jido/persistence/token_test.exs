defmodule JidoTest.Persistence.TokenTest do
  use ExUnit.Case, async: true

  alias Jido.Persistence
  alias Jido.Persistence.Record
  alias JidoTest.AgentFixtures.CounterAgent

  defmodule TokenAdapter do
    @behaviour Jido.Persistence.Adapter

    @impl true
    def get(key, opts) do
      case Keyword.get(opts, :read_override) do
        nil ->
          Elixir.Agent.get(Keyword.fetch!(opts, :store), fn values ->
            case Map.get(values, key) do
              nil -> {:error, :not_found}
              {bytes, token} -> {:ok, bytes, token}
            end
          end)

        reply ->
          reply
      end
    end

    @impl true
    def compare_and_swap(key, expected, bytes, opts) do
      if observer = Keyword.get(opts, :observer), do: send(observer, {:cas, key, expected})
      if hook = Keyword.get(opts, :before_cas), do: hook.(key)

      Elixir.Agent.get_and_update(Keyword.fetch!(opts, :store), fn values ->
        current = Map.get(values, key)

        matched? =
          case {expected, current} do
            {:not_found, nil} -> true
            {{:token, wanted}, {_bytes, wanted}} -> true
            _ -> false
          end

        if matched? do
          {:ok, Map.put(values, key, {bytes, new_token()})}
        else
          {{:error, :conflict}, values}
        end
      end)
    end

    @impl true
    def put(key, bytes, opts) do
      Elixir.Agent.update(Keyword.fetch!(opts, :store), fn values ->
        Map.put(values, key, {bytes, new_token()})
      end)
    end

    defp new_token, do: "opaque-#{System.unique_integer([:positive])}"
  end

  setup do
    {:ok, store} = Elixir.Agent.start_link(fn -> %{} end)
    on_exit(fn -> if Process.alive?(store), do: Elixir.Agent.stop(store) end)

    agent = CounterAgent.new!(id: "token-#{System.unique_integer([:positive])}")
    %{agent: agent, store: {TokenAdapter, store: store, observer: self()}}
  end

  test "validated token reads drive save, replacement, and tombstone writes", c do
    namespace = "token-test"
    opts = [namespace: namespace]
    agent = c.agent
    assert :ok = Persistence.save_agent(c.store, c.agent, opts)
    assert_receive {:cas, key, :not_found}

    assert {:ok, bytes, first_token} = get(c.store, key)
    assert {:ok, ^agent} = Persistence.load_agent(c.store, CounterAgent, c.agent.id, opts)

    assert :ok = Persistence.save_agent(c.store, c.agent, opts ++ [revision: 1])
    assert_receive {:cas, ^key, {:token, ^first_token}}

    assert {:ok, _bytes, second_token} = get(c.store, key)
    assert :ok = Persistence.replace_agent(c.store, c.agent, c.agent, opts ++ [revision: 2])
    assert_receive {:cas, ^key, {:token, ^second_token}}

    assert {:ok, _bytes, third_token} = get(c.store, key)
    assert :ok = Persistence.delete_agent(c.store, CounterAgent, c.agent.id, opts)
    assert_receive {:cas, ^key, {:token, ^third_token}}
    assert {:error, :deleted} = Persistence.load_agent(c.store, CounterAgent, c.agent.id, opts)
    assert :ok = Persistence.delete_agent(c.store, CounterAgent, c.agent.id, opts)
    refute_received {:cas, ^key, _condition}

    assert {:ok, tombstone_bytes, _token} = get(c.store, key)
    assert {:ok, tombstone} = Record.decode(tombstone_bytes)
    assert Record.kind(tombstone) == :tombstone
    assert :binary.match(bytes, first_token) == :nomatch
    assert :binary.match(tombstone_bytes, first_token) == :nomatch
  end

  test "a changed token rejects the old candidate even when bytes match", c do
    assert :ok = Persistence.save_agent(c.store, c.agent)
    assert_receive {:cas, key, :not_found}
    assert {:ok, bytes, first_token} = get(c.store, key)

    {adapter, options} = c.store
    hook = fn ^key -> adapter.put(key, bytes, options) end
    racing = {adapter, Keyword.put(options, :before_cas, hook)}

    assert {:error, :conflict} = Persistence.save_agent(racing, c.agent, revision: 1)
    assert_receive {:cas, ^key, {:token, ^first_token}}
    assert {:ok, ^bytes, new_token} = get(c.store, key)
    assert new_token != first_token
    refute_received {:cas, ^key, {:token, ^new_token}}
  end

  test "malformed token reads and read failures do not write", c do
    {adapter, options} = c.store

    for reply <- [
          {:ok, "bytes", nil},
          {:ok, "bytes", ""},
          {:ok, "bytes", {:secret, "raw-token"}},
          {:ok, "bytes", "raw-token", :extra},
          {:ok, :not_binary, "token"}
        ] do
      source = {adapter, Keyword.put(options, :read_override, reply)}

      assert {:error, %Jido.Error.ExecutionError{details: details}} =
               Persistence.save_agent(source, c.agent)

      assert details.code == :persistence_invalid_callback_result
      assert details.result == :invalid_token_read
      refute_received {:cas, _key, _condition}
    end

    source = {adapter, Keyword.put(options, :read_override, {:error, :offline})}
    assert {:error, :offline} = Persistence.save_agent(source, c.agent)
    refute_received {:cas, _key, _condition}
  end

  test "a token stays out of restore output and semantic telemetry", c do
    assert :ok = Persistence.save_agent(c.store, c.agent)
    assert_receive {:cas, key, :not_found}
    assert {:ok, _bytes, token} = get(c.store, key)

    handler = {:token_telemetry, make_ref()}
    owner = self()

    :ok =
      :telemetry.attach_many(
        handler,
        [
          [:jido, :persistence, :operation, :start],
          [:jido, :persistence, :operation, :stop]
        ],
        fn _event, measurements, metadata, _config ->
          send(owner, {:telemetry, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, restored, 0} =
             Persistence.load_agent_with_revision(c.store, CounterAgent, c.agent.id)

    assert restored == c.agent
    assert_receive {:telemetry, measurements, metadata}
    refute inspect(measurements) =~ token
    refute inspect(metadata) =~ token
    assert_receive {:telemetry, measurements, metadata}
    refute inspect(measurements) =~ token
    refute inspect(metadata) =~ token
  end

  defp get({adapter, opts}, key), do: adapter.get(key, opts)
end
