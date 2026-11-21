defmodule Jido.Exec.BoundaryRulesTest do
  use ExUnit.Case, async: true

  alias Jido.Exec.{Runtime, ValueResolver}
  alias Jido.Flow.Ref

  describe "durable values" do
    test "reject process-local terms at their exact path" do
      for {value, type, path} <- [
            {%{socket: hd(Port.list())}, :port, [:value, :socket]},
            {[make_ref()], :reference, [:value, 0]},
            {{:ok, fn -> :ok end}, :function, [:value, 1]},
            {%{self() => :key}, :pid, [:value, :key]},
            {[1 | self()], :pid, [:value, :tail]}
          ] do
        assert {:error, %{details: %{type: ^type, path: ^path}}} =
                 Runtime.validate_local(value, :value)
      end

      assert :ok =
               Runtime.validate_local(
                 %{list: [1 | 2], bits: <<5::size(3)>>, nested: {:ok, [%{a: 1}]}},
                 :value
               )
    end
  end

  describe "reference resolution" do
    test "reports missing sources and untraversable values" do
      state = %{input: %{items: [:a, :b], pair: {1, 2}, output: Jido.Action.Output.raw(1)}}

      assert {:ok, :b} = ValueResolver.resolve(Ref.input([:items, 1]), state)

      for {path, reason, type} <- [
            {[:pair, :x], :not_traversable, :tuple},
            {[:output, :x], :missing_key, :action_output}
          ] do
        assert {:error, %{details: %{reason: ^reason, value_type: ^type}}} =
                 ValueResolver.resolve(Ref.input(path), state)
      end

      assert {:error, %{details: %{reason: :source_not_available, ref_type: :item}}} =
               ValueResolver.resolve(Ref.item(), state)
    end
  end

  describe "canonical Flow validation" do
    test "rejects malformed canonical component data" do
      {:ok, flow} =
        Jido.Flow.new(%{
          name: "canonical",
          components: [
            %{kind: :step, name: "a", action: Jido.Test.Action.Fixtures.Actions.Add},
            %{
              kind: :choice,
              name: "c",
              options: [
                %{name: "o", condition: true, action: Jido.Test.Action.Fixtures.Actions.Add}
              ],
              fallback: %{action: Jido.Test.Action.Fixtures.Actions.Add}
            }
          ],
          output: %{}
        })

      a = flow.components["a"]
      c = flow.components["c"]

      for components <- [
            %{1 => a},
            %{"a" => Map.delete(a, :kind)},
            %{"a" => %{a | kind: :unknown}},
            %{"a" => %{a | needs: [:not_a_name | :tail]}},
            %{"a" => %{a | needs: :bad}},
            %{"c" => %{c | options: :bad}},
            %{"c" => %{c | options: [:bad]}},
            :not_a_map
          ] do
        assert {:error, %Jido.Error.ValidationError{}} =
                 Jido.Flow.validate(%{flow | components: components})
      end
    end
  end

  describe "data definitions" do
    test "default nil needs and meta and reject malformed choice parts" do
      step = %{kind: :step, name: "a", action: Jido.Test.Action.Fixtures.Actions.Add}

      assert {:ok, flow} =
               Jido.Flow.new(%{
                 name: "defaults",
                 components: [Map.merge(step, %{needs: nil, meta: nil})],
                 output: %{}
               })

      assert %{needs: [], meta: %{}} = flow.components["a"]

      for choice <- [
            %{kind: :choice, name: "c", options: [:bad], fallback: %{action: step.action}},
            %{kind: :choice, name: "c", options: [], fallback: :bad}
          ] do
        assert {:error, %Jido.Error.ValidationError{}} =
                 Jido.Flow.new(%{name: "bad_choice", components: [choice], output: %{}})
      end
    end
  end

  describe "Instruction targets" do
    test "reject unknown modules and non-template bindings" do
      assert {:error, %Jido.Error.ValidationError{details: %{reason: :nofile}}} =
               Jido.Instruction.resolve(Jido.NoSuchActionModule)

      assert {:error, %Jido.Error.ValidationError{details: %{reason: :invalid_template}}} =
               Jido.Instruction.bind(:not_a_template, %{}, %{})
    end
  end

  describe "expression trees" do
    test "parse map, list, and struct data with exact errors" do
      # A parse result must be an operation; data appears as its operands.
      assert {:ok, %Jido.Expr.Operation{operands: [%{a: 1, b: [1, 2]}, %{a: 1}]}} =
               Jido.Expr.parse(quote(do: %{a: 1, b: [1, 2]} == %{a: 1}))

      assert {:ok, %Jido.Expr.Operation{operands: [%{1 => 2}, 1]}} =
               Jido.Expr.parse({:==, [], [%{1 => 2}, 1]})

      assert {:error, %Jido.Expr.Error{reason: :expected_expression}} =
               Jido.Expr.parse(quote(do: %{a: 1}))

      for {ast, reason} <- [
            {quote(do: %{a: 1, a: 2} == 1), :duplicate_key},
            {quote(do: %{{:tuple} => 1} == 1), :invalid_map_key},
            {{:==, [], [[1 | 2], 1]}, :improper_list}
          ] do
        assert {:error, %Jido.Expr.Error{reason: ^reason}} = Jido.Expr.parse(ast)
      end

      leaf_error = %Jido.Expr.Error{reason: :unsupported_syntax}

      assert {:error, %Jido.Expr.Error{path: [:operands, 0]}} =
               Jido.Expr.parse(quote(do: unknown_call() + 1),
                 leaf_parser: fn _ast -> {:error, leaf_error} end
               )

      assert {:error, %Jido.Expr.Error{reason: :invalid_callback_return}} =
               Jido.Expr.parse(quote(do: unknown_call()), leaf_parser: fn _ast -> :bad end)
    end

    test "normalize and evaluate reject unsupported data" do
      assert {:error, %Jido.Expr.Error{reason: :unsupported_value}} =
               Jido.Expr.normalize(%{pair: {1, 2}})

      assert {:error, %Jido.Expr.Error{reason: :unsupported_value}} =
               Jido.Expr.evaluate(Jido.Expr.new!(:+, [~D[2026-01-01], 1]))

      assert {:error, %Jido.Expr.Error{reason: :expected_expression}} = Jido.Expr.validate(1)

      assert {:error, %Jido.Expr.Error{reason: :invalid_callback_return}} =
               Jido.Expr.evaluate(Jido.Expr.new!(:+, [Ref.input(:x), 1]),
                 resolve: fn _ -> :bad end
               )

      assert {:error, %Jido.Expr.Error{reason: :reducer_failure}} =
               Jido.Expr.reduce(%{a: 1}, :acc, fn _value, _acc -> raise "reducer" end)
    end
  end
end
