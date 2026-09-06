defmodule JidoTest.Telemetry.FormatterTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.Telemetry.Formatter

  test "duration units and millisecond precision follow native time" do
    native = &System.convert_time_unit(&1, :microsecond, :native)

    assert Formatter.format_duration(native.(342)) == "342μs"
    assert Formatter.format_duration(native.(1_500)) == "1.5ms"
    assert Formatter.format_duration(native.(2_500_000)) == "2.5s"
    assert Formatter.to_ms(native.(5_000)) == 5
    assert Formatter.to_ms(native.(1_234)) == 1.234
    assert Formatter.format_duration(nil) == "0μs"
    assert Formatter.to_ms(nil) == 0
    assert apply(Formatter, :format_duration, [:invalid]) == "??"
    assert apply(Formatter, :to_ms, [:invalid]) == 0
  end

  test "metadata is sorted, omits nil, and bounds long values" do
    assert Formatter.format_metadata(%{z: nil, b: false, a: 12, c: [1, 2]}) ==
             "a=12 b=false c=[1, 2]"

    assert Formatter.format_metadata(%{id: "abcdefghijkl"}, max_value_length: 8) ==
             "id=abcde..."

    assert Formatter.format_metadata(%{record: %{status: :ok}}) ==
             "record=%{status: :ok}"

    assert Formatter.format_metadata(nil) == ""
    assert apply(Formatter, :format_metadata, [[], []]) == ""
  end

  test "directive summaries combine structs and portable descriptions" do
    directives = [
      %Directive.Stop{},
      %{type: :emit},
      {:emit, %{id: "one"}},
      :await,
      %{unrelated: true},
      42
    ]

    assert Formatter.summarize_directives(directives) == %{"Stop" => 1, emit: 2, await: 1}

    assert Formatter.format_directive_types(%{"Stop" => 1, emit: 2, await: 1}) ==
             "Stop=1 Await=1 Emit=2"

    for value <- [nil, :invalid] do
      assert apply(Formatter, :summarize_directives, [value]) == %{}
      assert apply(Formatter, :format_directive_types, [value]) == ""
    end

    assert Formatter.summarize_directives([]) == %{}
    assert Formatter.format_directive_types(%{}) == ""
  end

  test "Action summaries expose parameter keys and arity without values" do
    assert Formatter.format_action({:run, %{password: "secret", name: "hidden"}}) ==
             "{:run, keys: [:name, :password]}"

    assert Formatter.format_action({:run, ["secret", "hidden"]}) == "{:run, arity: 2}"

    assert Formatter.format_action(%{action: :run, params: %{password: "secret"}}) ==
             "{:run, keys: [:password]}"

    assert Formatter.format_action(%{action: :run}) == ":run"
    assert Formatter.format_action(__MODULE__) == "JidoTest.Telemetry.FormatterTest"
    assert Formatter.format_action(:run) == "run"
    assert Formatter.format_action(nil) == "nil"
    assert Formatter.format_action(42) == "42"
  end

  test "inspection and key extraction keep output bounded" do
    assert Formatter.safe_inspect(%{a: 1}) == "%{a: 1}"
    text = Formatter.safe_inspect(String.duplicate("x", 200), 20)
    assert String.length(text) <= 20
    assert String.ends_with?(text, "...")
    assert Formatter.safe_inspect(String.duplicate("x", 200), 2) == "<inspect_error>"

    assert Formatter.extract_keys(%{secret: "hidden", agent_id: "one"}) == [:agent_id, :secret]
    assert Formatter.extract_keys(nil) == []
    assert apply(Formatter, :extract_keys, [:invalid]) == []
  end

  test "log lines normalize Signal names and duration before sorting" do
    duration = System.convert_time_unit(1_500, :microsecond, :native)

    assert Formatter.format_log_line(%{signal_type: :request, duration: duration, agent_id: "a"}) ==
             "agent_id=a duration=1.5ms signal_type=request"

    assert Formatter.format_signal_type("request") == "request"
    assert Formatter.format_signal_type(nil) == "unknown"
    assert apply(Formatter, :format_signal_type, [42]) == "unknown"
    assert apply(Formatter, :format_log_line, [nil]) == ""
  end
end
