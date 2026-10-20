defmodule JidoTest.Persistence.StoreTest do
  use Covenant.Case, component: "jido.persistence", async: true

  alias Jido.Error.ExecutionError
  alias Jido.Persistence.Store

  defmodule MemoryAdapter do
    @behaviour Jido.Persistence.Adapter

    @impl true
    def get(key, opts) do
      Elixir.Agent.get(Keyword.fetch!(opts, :owner), fn values ->
        case Map.fetch(values, key) do
          :error ->
            {:error, :not_found}

          {:ok, {bytes, token}} ->
            if opts[:token_reads], do: {:ok, bytes, token}, else: {:ok, bytes}
        end
      end)
    end

    @impl true
    def compare_and_swap(key, expected, bytes, opts) do
      Elixir.Agent.get_and_update(Keyword.fetch!(opts, :owner), fn values ->
        current = Map.get(values, key)

        if match_condition?(current, expected) do
          token = "token-#{System.unique_integer([:positive])}"
          {:ok, Map.put(values, key, {bytes, token})}
        else
          {{:error, :conflict}, values}
        end
      end)
    end

    defp match_condition?(nil, :not_found), do: true
    defp match_condition?({bytes, _token}, bytes), do: true
    defp match_condition?({_bytes, token}, {:token, token}), do: true
    defp match_condition?(_current, _expected), do: false
  end

  defmodule ReplyAdapter do
    @behaviour Jido.Persistence.Adapter

    @impl true
    def get(key, opts), do: Keyword.fetch!(opts, :read).(key)

    @impl true
    def compare_and_swap(key, expected, bytes, opts),
      do: Keyword.fetch!(opts, :write).(key, expected, bytes)
  end

  setup do
    {:ok, owner} = Elixir.Agent.start_link(fn -> %{} end)
    on_exit(fn -> if Process.alive?(owner), do: Elixir.Agent.stop(owner) end)
    %{owner: owner}
  end

  @tag obligation: "jido.persistence.I1"
  test "opens only byte adapters with atomic compare-and-swap" do
    assert {:ok, {MemoryAdapter, []}} = Store.open(MemoryAdapter)
    assert {:error, {:invalid_persistence_adapter, String}} = Store.open(String)
    assert {:error, :persistence_not_configured} = Store.open(nil)
    assert {:error, {:invalid_persistence_config, _}} = Store.open({MemoryAdapter, [:bad]})
  end

  @tag obligation: ["jido.persistence.I3", "jido.persistence.I4"]
  test "byte reads keep exact-byte conditions and stale writes conflict", %{owner: owner} do
    {:ok, store} = Store.open({MemoryAdapter, owner: owner})

    assert {:error, :not_found} = Store.read(store, "record")
    assert :ok = Store.compare_and_swap(store, "record", :not_found, <<1, 2>>)
    assert {:ok, <<1, 2>>, <<1, 2>>} = Store.read(store, "record")
    assert {:error, :conflict} = Store.compare_and_swap(store, "record", :not_found, "bad")
    assert :ok = Store.compare_and_swap(store, "record", <<1, 2>>, "next")
    assert {:error, :conflict} = Store.compare_and_swap(store, "record", <<1, 2>>, "stale")
    assert {:ok, "next", "next"} = Store.read(store, "record")
  end

  @tag obligation: ["jido.persistence.I3", "jido.persistence.I14"]
  test "opaque tokens are not replaced with equal bytes", %{owner: owner} do
    {:ok, store} = Store.open({MemoryAdapter, owner: owner, token_reads: true})

    assert :ok = Store.compare_and_swap(store, "record", :not_found, "same")
    assert {:ok, "same", {:token, first}} = Store.read(store, "record")
    assert :ok = Store.compare_and_swap(store, "record", {:token, first}, "same")
    assert {:ok, "same", {:token, second}} = Store.read(store, "record")
    assert second != first
    assert {:error, :conflict} = Store.compare_and_swap(store, "record", {:token, first}, "stale")
    assert {:ok, "same", {:token, ^second}} = Store.read(store, "record")
  end

  @tag obligation: "jido.persistence.I3"
  test "invalid reads and callback faults return errors" do
    write = fn _key, _expected, _bytes -> flunk("unexpected write") end

    {:ok, store} =
      Store.open({ReplyAdapter, read: fn _key -> {:ok, "bytes", "x"} end, write: write})

    assert {:ok, "bytes", {:token, "x"}} = Store.read(store, "record")

    for {reply, result} <- [
          {{:ok, :not_bytes}, {:ok, :not_bytes}},
          {{:ok, "bytes", ""}, :invalid_token_read},
          {{:ok, "bytes", nil}, :invalid_token_read},
          {{:ok, "bytes", "token", :extra}, :invalid_token_read},
          {:invalid, :invalid}
        ] do
      {:ok, store} = Store.open({ReplyAdapter, read: fn _key -> reply end, write: write})

      assert {:error,
              %ExecutionError{
                details: %{code: :persistence_invalid_callback_result, result: ^result}
              }} =
               Store.read(store, "record")
    end

    for {read, kind, reason} <- [
          {fn _key -> raise "read failed" end, :error, %RuntimeError{message: "read failed"}},
          {fn _key -> throw(:read_failed) end, :throw, :read_failed},
          {fn _key -> exit(:read_failed) end, :exit, :read_failed}
        ] do
      {:ok, store} = Store.open({ReplyAdapter, read: read, write: write})

      assert {:error,
              %ExecutionError{
                details: %{
                  code: :persistence_callback_failed,
                  operation: :get,
                  kind: ^kind,
                  reason: ^reason
                }
              }} =
               Store.read(store, "record")
    end
  end

  @tag obligation: "jido.persistence.I4"
  test "write outcomes distinguish rejection, unknown commit, and callback faults", %{
    owner: owner
  } do
    parent = self()
    read = fn _key -> {:error, :not_found} end

    for {reply, expected} <- [
          {{:error, :conflict}, {:error, :conflict}},
          {{:error, {:rejected, :quota}}, {:error, {:rejected, :quota}}},
          {{:error, :indeterminate}, {:error, :indeterminate}},
          {{:error, {:indeterminate, :timeout}}, {:error, {:indeterminate, :timeout}}},
          {{:error, :offline}, {:error, {:indeterminate, :offline}}}
        ] do
      write = fn key, condition, bytes ->
        send(parent, {:write, key, condition, bytes})
        reply
      end

      {:ok, store} = Store.open({ReplyAdapter, read: read, write: write})
      assert Store.compare_and_swap(store, "record", :not_found, "bytes") == expected
      assert_received {:write, "record", :not_found, "bytes"}
      refute_received {:write, _, _, _}
    end

    committed_unknown = fn key, _condition, bytes ->
      send(parent, {:write, key})
      Elixir.Agent.update(owner, &Map.put(&1, key, {bytes, "committed"}))
      {:error, :indeterminate}
    end

    {:ok, store} = Store.open({ReplyAdapter, read: read, write: committed_unknown})
    assert {:error, :indeterminate} = Store.compare_and_swap(store, "record", :not_found, "new")
    assert_received {:write, "record"}
    refute_received {:write, "record"}
    assert Elixir.Agent.get(owner, &Map.fetch!(&1, "record")) == {"new", "committed"}

    for {write, expected} <- [
          {fn _, _, _ -> :invalid end,
           %{
             code: :persistence_invalid_callback_result,
             operation: :compare_and_swap,
             result: :invalid
           }},
          {fn _, _, _ -> raise "write failed" end,
           %{
             code: :persistence_callback_failed,
             operation: :compare_and_swap,
             kind: :error,
             reason: %RuntimeError{message: "write failed"}
           }},
          {fn _, _, _ -> throw(:write_failed) end,
           %{
             code: :persistence_callback_failed,
             operation: :compare_and_swap,
             kind: :throw,
             reason: :write_failed
           }},
          {fn _, _, _ -> exit(:write_failed) end,
           %{
             code: :persistence_callback_failed,
             operation: :compare_and_swap,
             kind: :exit,
             reason: :write_failed
           }}
        ] do
      {:ok, store} = Store.open({ReplyAdapter, read: read, write: write})

      assert {:error, {:indeterminate, %ExecutionError{details: details}}} =
               Store.compare_and_swap(store, "record", :not_found, "bytes")

      assert details == expected
    end
  end

  @tag obligation: "jido.persistence.I4"
  test "bad write conditions are rejected before an adapter call" do
    read = fn _key -> {:error, :not_found} end
    write = fn _, _, _ -> flunk("unexpected write") end
    {:ok, store} = Store.open({ReplyAdapter, read: read, write: write})

    assert {:error, {:rejected, {:invalid_store_input, :condition}}} =
             Store.compare_and_swap(store, "record", {:token, ""}, "bytes")

    assert {:error, {:rejected, {:invalid_store_input, :compare_and_swap}}} =
             Store.compare_and_swap(store, "record", :not_found, %{not: :bytes})
  end

  @tag obligation: ["jido.persistence.I1", "jido.persistence.I3", "jido.persistence.I4"]
  test "Store entry points reject malformed configurations, keys, options, and bytes" do
    assert {:error, {:invalid_store_input, :read}} = Store.read(:invalid, "record")
    assert {:error, {:invalid_store_input, :read}} = Store.read({MemoryAdapter, []}, :record)

    assert {:error, {:invalid_store_input, :read}} =
             Store.read({MemoryAdapter, :invalid}, "record")

    assert {:error, {:invalid_store_input, :read}} = Store.read({%{}, []}, "record")

    assert {:error, {:invalid_persistence_config, :options}} =
             Store.read({MemoryAdapter, [:not_keyword]}, "record")

    for {config, key, value} <- [
          {:invalid, "record", "bytes"},
          {{MemoryAdapter, :invalid}, "record", "bytes"},
          {{%{}, []}, "record", "bytes"},
          {{MemoryAdapter, []}, :record, "bytes"},
          {{MemoryAdapter, []}, "record", :bytes}
        ] do
      assert {:error, {:rejected, {:invalid_store_input, :compare_and_swap}}} =
               Store.compare_and_swap(config, key, :not_found, value)
    end

    assert {:error, {:rejected, {:invalid_store_input, :options}}} =
             Store.compare_and_swap(
               {MemoryAdapter, [:not_keyword]},
               "record",
               :not_found,
               "bytes"
             )

    assert_raise ArgumentError, ~r/keyword list/, fn ->
      Store.normalize_adapter({MemoryAdapter, [:not_keyword]})
    end

    assert_raise ArgumentError, ~r/invalid Jido persistence adapter/, fn ->
      Store.normalize_adapter(%{adapter: MemoryAdapter})
    end

    assert_raise ArgumentError, ~r/invalid Jido persistence adapter/, fn ->
      Store.normalize_adapter({MemoryAdapter, :not_a_list})
    end

    token_store =
      {ReplyAdapter,
       read: fn _key -> flunk("unexpected read") end,
       write: fn _key, _condition, _bytes -> :ok end}

    assert :ok = Store.compare_and_swap(token_store, "record", {:token, "x"}, "bytes")
  end

  @tag obligation: "jido.persistence.I14"
  test "store telemetry omits keys, bytes, tokens, and options", %{owner: owner} do
    handler = {__MODULE__, make_ref()}
    parent = self()

    :ok =
      :telemetry.attach_many(
        handler,
        [[:jido, :persistence, :store, :start], [:jido, :persistence, :store, :stop]],
        fn event, _measurements, metadata, _config ->
          if self() == parent, do: send(parent, {:store_event, event, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    {:ok, store} = Store.open({MemoryAdapter, owner: owner, token_reads: true})

    assert :ok = Store.compare_and_swap(store, "secret-key", :not_found, "secret-value")
    assert_received {:store_event, [:jido, :persistence, :store, :start], start_metadata}
    assert_received {:store_event, [:jido, :persistence, :store, :stop], stop_metadata}
    assert start_metadata.adapter_module == MemoryAdapter
    assert start_metadata.operation == :compare_and_swap
    assert stop_metadata.status == :ok
    refute inspect({start_metadata, stop_metadata}) =~ "secret-"

    assert {:ok, "secret-value", {:token, _token}} = Store.read(store, "secret-key")
    assert_received {:store_event, [:jido, :persistence, :store, :start], read_metadata}
    assert_received {:store_event, [:jido, :persistence, :store, :stop], read_stop_metadata}
    assert read_metadata.operation == :load
    assert read_stop_metadata.status == :ok
    refute inspect({read_metadata, read_stop_metadata}) =~ "secret-"
  end
end
