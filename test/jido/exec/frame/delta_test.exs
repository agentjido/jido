defmodule JidoActionTest.Exec.Frame.DeltaTest do
  use ExUnit.Case, async: true

  alias Jido.Exec.Frame
  alias Jido.Exec.Frame.Delta

  describe "encode/2 and decode/2" do
    test "stores a cumulative Flow frame as references plus its new result" do
      session = large_session()
      parent = Frame.new(%{session: session, request_id: "request-1"})

      child =
        Frame.put_result(parent, "model", %{turn: %{session: session}, output: "42"}, [])

      assert {:delta, encoded} = Delta.encode(parent, child)
      assert {:ok, ^child} = Delta.decode(parent, encoded)

      assert encoded_bytes(encoded) < div(encoded_bytes(child), 10)
    end

    test "references the shared parent and branch outputs after a parallel join" do
      session = large_session()
      root = Frame.new(%{session: session})
      nested = Frame.nest(root, %{turn: %{session: session}})

      left =
        {:jido_parallel_action, 0, "left", nested, {:ok, %{tool_call_id: "left", content: large_content("left")}, []}}

      right =
        {:jido_parallel_action, 1, "right", nested,
         {:ok, %{tool_call_id: "right", content: large_content("right")}, []}}

      {:ok, merged} = Frame.merge([elem(left, 3), elem(right, 3)])

      child =
        Frame.put_result(
          merged,
          "tools",
          [
            %{name: "left", value: elem(elem(left, 4), 1)},
            %{name: "right", value: elem(elem(right, 4), 1)}
          ],
          []
        )

      parent = [left, right]

      assert {:delta, encoded} = Delta.encode(parent, child)
      assert {:ok, ^child} = Delta.decode(parent, encoded)

      assert encoded_bytes(encoded) < div(encoded_bytes(child), 5)
    end

    test "references values that move between invoke control wrappers" do
      session = large_session()
      frame = Frame.new(%{session: session})
      turn = %{session: session, model_outcome: %{kind: :tool_calls}}

      parent =
        {:jido_invoke_decision, frame, "next", %{kind: :tools, input: %{turn: turn}}, []}

      child =
        {:jido_invoke_continue, frame, "next", %{turn: turn}, :dynamic_tool_flow, []}

      assert {:delta, encoded} = Delta.encode(parent, child)
      assert {:ok, ^child} = Delta.decode(parent, encoded)

      assert encoded_bytes(encoded) < div(encoded_bytes(child), 10)
    end

    test "keeps an eight-step durable frame journal below one tenth of full snapshots" do
      session = large_session()
      initial = Frame.new(%{session: session})

      {_last, full_bytes, delta_bytes} =
        Enum.reduce(1..8, {initial, 0, 0}, fn step, {parent, full_total, delta_total} ->
          attempts =
            Enum.map(1..step, fn attempt ->
              %{
                attempt: attempt,
                before: String.duplicate("before #{attempt} ", 300),
                after: String.duplicate("after #{attempt} ", 300)
              }
            end)

          child =
            Frame.put_result(
              parent,
              "step_#{step}",
              %{turn: %{session: session, attempts: attempts}, output: step},
              []
            )

          assert {:delta, encoded} = Delta.encode(parent, child)
          assert {:ok, ^child} = Delta.decode(parent, encoded)

          {child, full_total + encoded_bytes(child), delta_total + encoded_bytes(encoded)}
        end)

      assert delta_bytes < div(full_bytes, 10)
    end

    test "produces deterministic delta bytes for maps with different insertion order" do
      parent = Frame.new(Map.new([{:session, large_session()}, {:request_id, "request-1"}]))

      left =
        Frame.put_result(
          parent,
          "model",
          Map.new([{:output, "42"}, {:session, large_session()}]),
          []
        )

      right =
        Frame.put_result(
          parent,
          "model",
          Map.new([{:session, large_session()}, {:output, "42"}]),
          []
        )

      assert {:delta, left_encoded} = Delta.encode(parent, left)
      assert {:delta, right_encoded} = Delta.encode(parent, right)

      assert :erlang.term_to_binary(left_encoded, [:deterministic]) ==
               :erlang.term_to_binary(right_encoded, [:deterministic])
    end

    test "uses a parent reference for an unchanged propagated value" do
      value = [Frame.nest(Frame.new(large_session()), %{value: 1})]

      assert {:delta, encoded} = Delta.encode(value, value)
      assert {:ok, ^value} = Delta.decode(value, encoded)
      assert encoded_bytes(encoded) < 256
    end

    test "preserves local value structs around frame values" do
      parent_frame = Frame.new(%{session: large_session()})
      child_frame = Frame.put_result(parent_frame, "model", %{output: "42"}, [])
      parent = Jido.Exec.Fact.local_value(parent_frame)
      child = Jido.Exec.Fact.local_value(child_frame)

      assert {:delta, encoded} = Delta.encode(parent, child)
      assert {:ok, ^child} = Delta.decode(parent, encoded)
    end

    test "does not treat a user value shaped like an internal reference as a delta" do
      reference = %Jido.Exec.Frame.Delta.Reference{path: [{:map, :missing}]}
      shared = large_content("shared")
      parent = %{shared: shared}
      child = %{shared: shared, value: reference}

      assert {:delta, encoded} = Delta.encode(parent, child)
      assert {:ok, ^child} = Delta.decode(parent, encoded)
    end

    test "keeps a full value when references do not reduce its encoded size" do
      assert :full = Delta.encode(%{left: 1}, %{right: 2})
    end

    test "rejects a reference path that the parent does not contain" do
      encoded = delta_reference([{:map, :missing}])

      assert {:error, {:invalid_parent_reference, [{:map, :missing}]}} =
               Delta.decode(%{}, encoded)
    end

    test "rejects a malformed reference path" do
      assert {:error, {:invalid_parent_reference, :invalid}} =
               Delta.decode(%{}, delta_reference(:invalid))
    end

    test "rejects a reference into an improper parent list" do
      assert {:error, {:invalid_parent_reference, [{:list, 0}]}} =
               Delta.decode([:head | :tail], delta_reference([{:list, 0}]))
    end
  end

  defp large_session do
    %{
      id: "session-1",
      thread: %{
        entries: [
          %{role: :user, content: String.duplicate("request ", 4_000)},
          %{role: :assistant, content: String.duplicate("response ", 4_000)}
        ]
      }
    }
  end

  defp large_content(label), do: String.duplicate(label <> " result ", 2_000)

  defp delta_reference(path) do
    {:jido_frame_delta, 1, %Jido.Exec.Frame.Delta.Reference{path: path}}
  end

  defp encoded_bytes(term), do: term |> :erlang.term_to_binary([:deterministic]) |> byte_size()
end
