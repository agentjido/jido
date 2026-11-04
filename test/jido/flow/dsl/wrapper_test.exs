defmodule Jido.Flow.DSL.WrapperTest do
  use ExUnit.Case, async: false

  test "Map and State forms keep evaluation, aliases, and expression scopes" do
    flows =
      for form <- [:keyword, :block] do
        name = ~s|(send(self(), :map_name); "mapped")|
        schema = "(send(self(), :state_schema); Jido.Joi.map())"

        {map, state} =
          case form do
            :keyword ->
              {"map #{name}, collection: input(:items), action: Echo, params: %{value: item() + 1}",
               "state #{schema}, initial: %{value: input(:start) + 1}"}

            :block ->
              {"map #{name} do\n collection input(:items)\n action Echo\n params %{value: item() + 1}\nend",
               "state #{schema} do\n initial %{value: input(:start) + 1}\nend"}
          end

        owner =
          compile("""
          #{map}
          iterate "loop" do
            #{state}
            action Echo
            params %{value: state(:value) + 1}
            repeat 1
          end
          output %{mapped: result("mapped"), loop: result("loop")}
          """)

        assert_received :map_name
        refute_received :map_name
        assert_received :state_schema
        refute_received :state_schema

        assert {:ok, %{mapped: [%{value: 3}], loop: %{state: %{value: 4}}}} =
                 Jido.Exec.run(owner, %{items: [2], start: 2})

        owner.flow()
      end

    assert [flow, flow] = flows
  end

  test "Map and State keep their distinct option errors and declaration lines" do
    for {declaration, message, line} <- [
          {~s|map "bad", [:invalid]|, "Flow declaration options must be a keyword list", 5},
          {~s|map "bad", params: %{}, params: %{}|, "duplicate Flow declaration field: :params", 5},
          {~s|map("bad", params: %{}, do: (params %{}))|, "do not mix keyword and block fields in one declaration", 5},
          {"iterate \"loop\" do\n state Jido.Joi.map(), [:invalid]\nend",
           "Iterate state options must be a keyword list", 6},
          {"iterate \"loop\" do\n state Jido.Joi.map(), initial: %{}, initial: %{}\nend",
           "duplicate Iterate state field: :initial", 6},
          {"iterate \"loop\" do\n state(Jido.Joi.map(), initial: %{}, do: (initial %{}))\nend",
           "do not mix keyword and block fields in Iterate state", 6}
        ] do
      error = assert_raise CompileError, fn -> compile(declaration) end
      assert error.description == message
      assert error.file == "wrapper_probe.ex"
      assert error.line == line
    end
  end

  test "Choice option and fallback forms preserve names, aliases, and expressions" do
    flows =
      for option_form <- [:keyword, :block], fallback_form <- [:keyword, :block] do
        name = ~s|(send(self(), :option_name); "yes")|

        option =
          case option_form do
            :keyword ->
              "option #{name}, condition: input(:chosen), action: Echo, params: %{value: input(:value) + 1}"

            :block ->
              "option #{name} do\n condition input(:chosen)\n action Echo\n params %{value: input(:value) + 1}\nend"
          end

        fallback =
          case fallback_form do
            :keyword -> "otherwise action: Echo, params: %{value: input(:value) - 1}"
            :block -> "otherwise do\n action Echo\n params %{value: input(:value) - 1}\nend"
          end

        owner =
          compile("""
          choice "route" do
            #{option}
            #{fallback}
          end
          output result("route")
          """)

        assert_received :option_name
        refute_received :option_name
        assert Jido.Exec.run(owner, %{chosen: true, value: 2}) == {:ok, %{value: 3}}
        assert Jido.Exec.run(owner, %{chosen: false, value: 2}) == {:ok, %{value: 1}}
        owner.flow()
      end

    assert [flow, flow, flow, flow] = flows
  end

  test "Choice targets keep exact option errors and source locations" do
    for target <- [~s|option("yes", |, "otherwise("],
        {options, message} <- [
          {"[:invalid])", "Choice declaration options must be a keyword list"},
          {"params: %{}, params: %{})", "duplicate Choice declaration field: :params"},
          {"params: %{}, do: (params %{}))", "do not mix keyword and block fields in one Choice target"}
        ] do
      error =
        assert_raise CompileError, fn ->
          compile("choice \"route\" do\n#{target}#{options}\nend")
        end

      assert error.description == message
      assert error.file == "wrapper_probe.ex"
      assert error.line == 6
    end
  end

  defp compile(declarations) do
    owner = Module.concat(__MODULE__, "Owner#{System.unique_integer([:positive])}")

    on_exit(fn ->
      :code.purge(owner)
      :code.delete(owner)
    end)

    Code.compile_string(
      """
      defmodule #{inspect(owner)} do
        use Jido.Flow, name: "wrapper_probe"
        alias Jido.Test.Action.Fixtures.Actions.EchoParamsAction, as: Echo
        flow do
          #{declarations}
        end
      end
      """,
      "wrapper_probe.ex"
    )

    owner
  end
end
