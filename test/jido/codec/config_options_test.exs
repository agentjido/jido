defmodule Jido.Instruction.ConfigOptionsTest do
  use Covenant.Case, component: "jido_action.inline", async: true

  alias Jido.Action.Inline
  alias Jido.Action.Inline.Parser
  alias Jido.Instruction.Config
  alias Jido.Flow.DSL.InlineStep

  @tag obligation: ["jido_action.inline.I1", "jido_action.inline.I2"]
  test "each caller keeps its error label and source location" do
    for {validate, label, message, allowed} <- callers() do
      for invalid <- [:invalid, [:invalid], [{allowed, :ok} | :tail]] do
        error = assert_raise CompileError, fn -> validate.(invalid) end
        assert error.description == message
        assert_source(error)
      end

      error = assert_raise CompileError, fn -> validate.([{allowed, 1}, {allowed, 2}]) end
      assert error.description == "duplicate #{label}: #{inspect(allowed)}"
      assert_source(error)
    end
  end

  @tag obligation: ["jido_action.inline.I1", "jido_action.inline.I2"]
  test "inline Action and Step checks keep their distinct diagnostic order" do
    error =
      assert_raise CompileError, fn ->
        Parser.options!([unknown: 1, do: 1, do: 2], [:do], caller())
      end

    assert error.description == "unsupported inline Action option: :unknown"
    assert_source(error)

    error =
      assert_raise CompileError, fn ->
        InlineStep.parse!([], [unknown: 1, do: 1, do: 2], caller())
      end

    assert error.description == "duplicate inline Step field: :do"
    assert_source(error)

    error =
      assert_raise CompileError, fn ->
        InlineStep.parse!([], [do: :ok, inline: [unknown: 1]], caller())
      end

    assert error.description == "unsupported inline Step setting: :unknown"
    assert_source(error)
  end

  @tag obligation: "jido_action.inline.I1"
  test "Action invalid option expressions retain their expression line" do
    error =
      assert_raise CompileError, fn ->
        Parser.options!({:options, [line: 29], nil}, [:do], caller())
      end

    assert error.file == "authoring_options.ex"
    assert error.line == 29
  end

  @tag obligation: ["jido_action.inline.I1", "jido_action.inline.I2"]
  test "valid options still produce inline Action and Step declarations" do
    assert %Inline{} = Inline.parse_callback!({:params, [], nil}, [do: :ok], caller())

    assert %{action: %Inline{}, component_options: [needs: []]} =
             InlineStep.parse!([], [needs: [], inline: [name: "valid"], do: :ok], caller())

    assert :ok = Config.validate_options!([action: String], caller(), "invalid", "Flow field")
  end

  defp callers do
    [
      {&Parser.options!(&1, [:do], caller()), "inline Action option", "inline Action options must be a keyword list",
       :do},
      {&Config.validate_options!(
         &1,
         caller(),
         "Flow declaration fields must be a keyword list",
         "Flow declaration field"
       ), "Flow declaration field", "Flow declaration fields must be a keyword list", :action},
      {&InlineStep.parse!([], &1, caller()), "inline Step field", "inline Step options must be a keyword list", :do},
      {&InlineStep.parse!([], [do: :ok, inline: &1], caller()), "inline Step setting",
       "inline Step settings must be a keyword list", :name}
    ]
  end

  defp caller, do: %{__ENV__ | file: "authoring_options.ex", line: 17}

  defp assert_source(error) do
    assert error.file == "authoring_options.ex"
    assert error.line == 17
  end
end
