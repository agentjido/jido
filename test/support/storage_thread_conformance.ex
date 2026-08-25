defmodule JidoTest.StorageThreadConformance do
  @moduledoc """
  Reusable ExUnit cases for the thread-journal half of `Jido.Storage`.

  The caller supplies an adapter module and an option expression. The
  expression is evaluated for every generated test, allowing adapters to
  inject isolated tables, directories, or backend connections.

  ## Example

      use JidoTest.StorageThreadConformance,
        adapter: Jido.Storage.ETS,
        setup: quote do: [table: unique_table(:thread_conformance)]

  The helper covers the shared journal contract. Adapter-specific lifecycle,
  corruption, and backend failure tests belong in the adapter's own suite.
  """

  defmacro __using__(options) do
    adapter = Keyword.fetch!(options, :adapter)

    setup =
      case Keyword.get(options, :setup, quote(do: [])) do
        {:quote, _, [[do: expression]]} -> expression
        expression -> expression
      end

    quote do
      alias unquote(adapter), as: ThreadStorageAdapter

      describe "thread journal storage conformance" do
        test "returns :not_found when loading a missing thread" do
          opts = unquote(setup)
          thread_id = "missing_#{System.unique_integer([:positive])}"

          assert :not_found = ThreadStorageAdapter.load_thread(thread_id, opts),
                 "thread contract: missing load must return :not_found"
        end

        test "returns :not_found after an empty append" do
          opts = unquote(setup)
          thread_id = "empty_#{System.unique_integer([:positive])}"

          assert {:ok, thread} = ThreadStorageAdapter.append_thread(thread_id, [], opts)
          assert thread.entries == []
          assert :not_found = ThreadStorageAdapter.load_thread(thread_id, opts)
        end

        test "creates a thread by appending entries" do
          opts = unquote(setup)
          thread_id = "create_#{System.unique_integer([:positive])}"
          entries = [%{kind: :message, payload: %{content: "hello"}}]

          assert {:ok, thread} = ThreadStorageAdapter.append_thread(thread_id, entries, opts),
                 "thread contract: append must return the created thread"

          assert thread.id == thread_id
          assert thread.rev == 1
          assert [%Jido.Thread.Entry{kind: :message}] = thread.entries
        end

        test "preserves append ordering and assigns contiguous sequences" do
          opts = unquote(setup)
          thread_id = "ordering_#{System.unique_integer([:positive])}"

          first = [%{kind: :note, payload: %{n: 1}}, %{kind: :note, payload: %{n: 2}}]
          second = [%{kind: :note, payload: %{n: 3}}]

          assert {:ok, initial} = ThreadStorageAdapter.append_thread(thread_id, first, opts)
          assert {:ok, _} = ThreadStorageAdapter.append_thread(thread_id, second, opts)
          assert {:ok, thread} = ThreadStorageAdapter.load_thread(thread_id, opts)

          assert Enum.map(thread.entries, & &1.payload.n) == [1, 2, 3]
          assert Enum.map(thread.entries, & &1.seq) == [0, 1, 2]
          assert Enum.take(thread.entries, 2) == initial.entries
        end

        test "preserves metadata from creation through later appends and load" do
          opts = unquote(setup)
          thread_id = "metadata_#{System.unique_integer([:positive])}"
          metadata = %{account_id: "acct-1", source: :test}

          assert {:ok, created} =
                   ThreadStorageAdapter.append_thread(
                     thread_id,
                     [%{kind: :note}],
                     Keyword.put(opts, :metadata, metadata)
                   )

          assert created.metadata == metadata

          assert {:ok, appended} =
                   ThreadStorageAdapter.append_thread(thread_id, [%{kind: :note}], opts)

          assert appended.metadata == metadata
          assert {:ok, loaded} = ThreadStorageAdapter.load_thread(thread_id, opts)
          assert loaded.metadata == metadata
        end

        test "increments revision by the number of appended entries" do
          opts = unquote(setup)
          thread_id = "revision_#{System.unique_integer([:positive])}"

          assert {:ok, first} =
                   ThreadStorageAdapter.append_thread(
                     thread_id,
                     [%{kind: :note}, %{kind: :note}],
                     opts
                   )

          assert first.rev == 2

          assert {:ok, second} =
                   ThreadStorageAdapter.append_thread(
                     thread_id,
                     [%{kind: :note}, %{kind: :note}, %{kind: :note}],
                     opts
                   )

          assert second.rev == 5
          assert {:ok, loaded} = ThreadStorageAdapter.load_thread(thread_id, opts)
          assert loaded.rev == 5
        end

        test "normalizes maps and preserves Entry structs" do
          opts = unquote(setup)
          thread_id = "normalization_#{System.unique_integer([:positive])}"
          entry = Jido.Thread.Entry.new(kind: :tool_result, payload: %{ok: true})

          assert {:ok, thread} =
                   ThreadStorageAdapter.append_thread(
                     thread_id,
                     [%{kind: :message, payload: %{content: "map"}}, entry],
                     opts
                   )

          assert Enum.all?(thread.entries, &match?(%Jido.Thread.Entry{}, &1))
          assert Enum.map(thread.entries, & &1.seq) == [0, 1]
          assert Enum.map(thread.entries, & &1.id) |> Enum.all?(&is_binary/1)
        end

        test "assigns entry and thread timestamps" do
          opts = unquote(setup)
          thread_id = "timestamps_#{System.unique_integer([:positive])}"
          before = System.system_time(:millisecond)

          assert {:ok, created} =
                   ThreadStorageAdapter.append_thread(thread_id, [%{kind: :note}], opts)

          after_create = System.system_time(:millisecond)
          entry = hd(created.entries)

          assert is_integer(entry.at) and entry.at in before..after_create
          assert is_integer(created.created_at) and created.created_at in before..after_create
          assert is_integer(created.updated_at) and created.updated_at >= created.created_at

          assert {:ok, updated} =
                   ThreadStorageAdapter.append_thread(thread_id, [%{kind: :note}], opts)

          assert updated.created_at == created.created_at
          assert updated.updated_at >= created.updated_at
        end

        test "reports entry count in stats" do
          opts = unquote(setup)
          thread_id = "stats_#{System.unique_integer([:positive])}"

          assert {:ok, thread} =
                   ThreadStorageAdapter.append_thread(
                     thread_id,
                     [%{kind: :note}, %{kind: :note}, %{kind: :note}],
                     opts
                   )

          assert thread.stats.entry_count == 3
          assert {:ok, loaded} = ThreadStorageAdapter.load_thread(thread_id, opts)
          assert loaded.stats.entry_count == 3
        end

        test "accepts a matching expected revision" do
          opts = unquote(setup)
          thread_id = "expected_match_#{System.unique_integer([:positive])}"

          assert {:ok, first} =
                   ThreadStorageAdapter.append_thread(thread_id, [%{kind: :note}], opts)

          assert {:ok, second} =
                   ThreadStorageAdapter.append_thread(
                     thread_id,
                     [%{kind: :note}],
                     Keyword.put(opts, :expected_rev, first.rev)
                   )

          assert second.rev == 2
        end

        test "accepts expected revision zero when creating a thread" do
          opts = unquote(setup)
          thread_id = "expected_create_#{System.unique_integer([:positive])}"

          assert {:ok, thread} =
                   ThreadStorageAdapter.append_thread(
                     thread_id,
                     [%{kind: :note}],
                     Keyword.put(opts, :expected_rev, 0)
                   )

          assert thread.rev == 1
        end

        test "rejects a stale expected revision without changing the journal" do
          opts = unquote(setup)
          thread_id = "expected_stale_#{System.unique_integer([:positive])}"

          assert {:ok, before} =
                   ThreadStorageAdapter.append_thread(thread_id, [%{kind: :note}], opts)

          assert {:error, :conflict} =
                   ThreadStorageAdapter.append_thread(
                     thread_id,
                     [%{kind: :note, payload: %{must_not: :persist}}],
                     Keyword.put(opts, :expected_rev, 0)
                   )

          assert {:ok, after_conflict} = ThreadStorageAdapter.load_thread(thread_id, opts)
          assert after_conflict.rev == before.rev
          assert after_conflict.entries == before.entries
        end

        test "deleting a thread is idempotent" do
          opts = unquote(setup)
          thread_id = "delete_#{System.unique_integer([:positive])}"

          assert {:ok, _} = ThreadStorageAdapter.append_thread(thread_id, [%{kind: :note}], opts)
          assert :ok = ThreadStorageAdapter.delete_thread(thread_id, opts)
          assert :not_found = ThreadStorageAdapter.load_thread(thread_id, opts)
          assert :ok = ThreadStorageAdapter.delete_thread(thread_id, opts)

          assert {:ok, recreated} =
                   ThreadStorageAdapter.append_thread(thread_id, [%{kind: :note}], opts)

          assert recreated.metadata == %{}
        end
      end
    end
  end
end
