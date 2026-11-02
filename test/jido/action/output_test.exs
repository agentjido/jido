defmodule JidoActionTest.Action.OutputTest do
  use Covenant.Case, component: "jido_action.output", async: true

  alias Jido.Action.Output

  @tag obligation: "jido_action.output.I1"
  test "stream construction and validation do not consume the enumerable" do
    owner = self()
    token = make_ref()

    stream =
      Stream.map([1, 2], fn value ->
        send(owner, {token, :consumed, value})
        value
      end)

    output = Output.stream(stream, meta: %{source: :test})
    assert output.value === stream
    assert {:ok, ^output} = Output.validate(output)
    refute_received {^token, :consumed, _}
    assert Enum.to_list(output.value) == [1, 2]
    assert_received {^token, :consumed, 1}
    assert_received {^token, :consumed, 2}
  end

  describe "constructors" do
    @tag obligation: "jido_action.output.I1"
    test "build explicit abnormal output envelopes" do
      assert %Output{kind: :raw, value: {:ok, 1}, meta: %{source: :test}} =
               Output.raw({:ok, 1}, meta: %{source: :test})

      stream = Stream.map(1..3, &(&1 * 2))

      assert %Output{kind: :stream, value: ^stream, meta: %{}} =
               Output.stream(stream)

      assert %Output{kind: :batch, value: [%{id: 1}], meta: %{page: 1}} =
               Output.batch([%{id: 1}], meta: %{page: 1})

      assert %Output{kind: :opaque, value: {:external, :resource}, meta: %{}} =
               Output.opaque({:external, :resource})

      assert %Output{kind: :preserve, value: %{value: 1}, meta: %{source: :test}} =
               Output.preserve(%{value: 1}, meta: %{source: :test})
    end

    @tag obligation: "jido_action.output.I1"
    test "reject invalid constructor inputs" do
      assert_raise ArgumentError, ~r/invalid action output envelope/, fn ->
        Output.raw(:value, meta: [])
      end

      assert_raise ArgumentError, ~r/invalid action output envelope/, fn ->
        Output.raw(:value, [:not_keyword])
      end

      assert_raise ArgumentError, ~r/invalid action output envelope/, fn ->
        Output.raw(:value, meta: %{}, unexpected: true)
      end

      assert_raise ArgumentError, ~r/invalid action output envelope/, fn ->
        Output.raw(:value, :not_opts)
      end

      assert_raise ArgumentError, ~r/invalid action output envelope/, fn ->
        Output.stream(:not_enumerable)
      end

      assert_raise ArgumentError, ~r/invalid action output envelope/, fn ->
        Output.stream([1 | 2])
      end

      assert_raise ArgumentError, ~r/invalid action output envelope/, fn ->
        Output.batch(:not_a_list)
      end

      assert_raise ArgumentError, ~r/invalid action output envelope/, fn ->
        Output.batch([1 | 2])
      end
    end
  end

  describe "validation" do
    @tag obligation: "jido_action.output.I2"
    test "validates existing output envelopes" do
      assert {:ok, %Output{kind: :raw, value: "payload", meta: %{}}} =
               Output.validate(%Output{kind: :raw, value: "payload", meta: %{}})
    end

    @tag obligation: "jido_action.output.I2"
    test "reports malformed output envelopes" do
      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
               Output.validate(:not_an_output)

      assert Exception.message(error) == "invalid action output envelope"
      assert error.details.value == :not_an_output

      assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
               Output.validate(%Output{kind: :batch, value: :not_a_list, meta: %{}})

      assert Exception.message(error) == "invalid action output envelope"
      assert error.details.value == %Output{kind: :batch, value: :not_a_list, meta: %{}}

      for output <- [
            %Output{kind: :unknown, value: :value, meta: %{}},
            %Output{kind: :raw, value: :value, meta: []},
            %Output{kind: :batch, value: [1 | 2], meta: %{}},
            %Output{kind: :stream, value: :not_enumerable, meta: %{}}
          ] do
        assert {:error, %Jido.Action.Error.InvalidInputError{} = error} = Output.validate(output)
        assert error.message == "invalid action output envelope"
        assert error.details == %{value: output}
      end
    end
  end
end
