# Run the notebook examples against Jido's Action and Signal dependencies.
filename = Path.expand("../../../guides/typed-signals.livemd", __DIR__)

ExUnit.CaptureLog.capture_log(fn ->
  ~r/```elixir\n(.*?)\n```/s
  |> Regex.scan(File.read!(filename), capture: :all_but_first)
  |> Enum.map(&hd/1)
  |> Enum.reject(&String.contains?(&1, "Mix.install("))
  |> Enum.reduce({[], Code.env_for_eval(file: filename)}, fn code, {bindings, env} ->
    ast = Code.string_to_quoted!(code, file: filename)
    {_result, bindings, env} = Code.eval_quoted_with_env(ast, bindings, env)
    {bindings, env}
  end)
end)

defmodule Jido.Examples.TypedSignalsTest do
  use ExUnit.Case, async: false
  @moduletag :example
  @moduletag capture_log: true

  defp request do
    SignalExamples.AreaRequested.new!(%{"width" => 3, "height" => 4},
      id: "boundary-request",
      source: "/examples/tests",
      subject: "rectangle-test",
      time: "2026-01-01T00:00:00Z",
      extensions: %{"causationid" => "original-cause"}
    )
  end

  test "input validation preserves the supplied native Signal" do
    signal = request()

    assert {:ok, %{signal: ^signal}} =
             SignalExamples.CalculateArea.validate_params(%{signal: signal})
  end

  test "wrong envelope, type, dataschema, and data fail before the callback" do
    signal = request()

    for invalid <- [
          %{signal | source: ""},
          %{signal | type: "example.wrong"},
          %{signal | dataschema: "urn:example:area:requested:2"},
          %{signal | data: %{"width" => "3", "height" => 4}},
          Jido.Signal.to_map(signal)
        ] do
      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Jido.Exec.run(SignalExamples.CalculateArea, %{signal: invalid})
    end
  end

  test "output validation rejects the wrong completion definition or data" do
    {:ok, %{signal: completion}} =
      Jido.Exec.run(SignalExamples.CalculateArea, %{signal: request()})

    for invalid <- [
          %{completion | type: "example.wrong"},
          %{completion | dataschema: "urn:example:area:completed:2"},
          %{completion | data: %{"area" => "12"}}
        ] do
      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               SignalExamples.CalculateArea.validate_output(%{signal: invalid})
    end
  end

  test "the two-step Flow constructs its label request from the area result" do
    assert {:ok, %{signal: label}} =
             Jido.Exec.run(SignalExamples.AreaLabelFlow, %{signal: request()})

    assert label.type == SignalExamples.LabelRequested.type()
    assert label.data == %{"text" => "Area: 12"}
    refute label.id == request().id
  end

  test "new Signals retain trace context and name their immediate cause" do
    {:ok, signal} =
      Jido.Signal.put_context(
        request(),
        "traceparent",
        "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
      )

    assert {:ok, %{signal: completion}} =
             Jido.Exec.run(SignalExamples.CalculateArea, %{signal: signal})

    assert {:ok, %{signal: label}} =
             Jido.Exec.run(SignalExamples.PrepareLabel, %{signal: completion})

    assert Jido.Signal.get_context(completion, "causationid") == signal.id
    assert Jido.Signal.get_context(label, "causationid") == completion.id

    assert Jido.Signal.get_context(label, "traceparent") ==
             Jido.Signal.get_context(signal, "traceparent")

    assert completion.id != signal.id
    assert label.id != completion.id
  end

  test "a domain failure returns an error and the consumer constructs its Signal" do
    signal = %{request() | data: %{"width" => 101, "height" => 100}}

    assert {:error, %Jido.Action.Error.ExecutionFailureError{details: %{code: :area_limit}}} =
             Jido.Exec.run(SignalExamples.AreaLabelFlow, %{signal: signal})

    failure =
      SignalExamples.AreaFailed.new!(
        %{"code" => "area_limit"},
        SignalExamples.Boundary.child_options(signal)
      )

    assert Jido.Signal.get_context(failure, "causationid") == signal.id
    assert failure.data == %{"code" => "area_limit"}
  end

  test "schema export exposes the current limit" do
    exported = SignalExamples.CalculateArea.to_json()
    assert exported["input_schema"]["properties"]["signal"] == %{}
    assert exported["output_schema"]["properties"]["signal"] == %{}
  end
end
