defmodule JidoTest.Thread.Actions.RecordTest do
  use ExUnit.Case, async: true

  alias Jido.Thread
  alias Jido.Thread.Actions.Record

  describe "run/2" do
    test "initializes a thread when missing" do
      params = %{
        entries: [
          %{kind: :message, payload: %{role: "user", content: "hello"}}
        ]
      }

      assert {:ok, %{__thread__: thread}} = Record.run(params, %{state: %{}})
      assert %Thread{} = thread
      assert Thread.entry_count(thread) == 1
      assert Thread.last(thread).payload == %{role: "user", content: "hello"}
    end

    test "appends to an existing thread" do
      existing =
        Thread.new()
        |> Thread.append(%{kind: :note, payload: %{text: "first"}})

      params = %{
        entries: [
          %{kind: :message, payload: %{role: "assistant", content: "second"}}
        ]
      }

      assert {:ok, %{__thread__: thread}} = Record.run(params, %{state: %{__thread__: existing}})
      assert Thread.entry_count(thread) == 2

      [first, second] = Thread.to_list(thread)
      assert first.payload == %{text: "first"}
      assert second.payload == %{role: "assistant", content: "second"}
    end

    test "rejects empty entry batches" do
      assert {:error, %Jido.Error.ValidationError{}} =
               Record.run(%{entries: []}, %{state: %{}})
    end
  end
end
