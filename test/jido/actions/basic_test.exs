defmodule JidoTest.Actions.BasicActionsTest do
  use ExUnit.Case, async: true
  alias Jido.Actions.Basic

  @moduletag :capture_log

  setup do
    # Forcibly set the log level to :debug to ensure all log messages are captured
    Logger.configure(level: :debug)
    :ok
  end

  describe "Sleep" do
    test "sleeps for the specified duration" do
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, %{duration_ms: 100}} = Basic.Sleep.run(%{duration_ms: 100}, %{})
      end_time = System.monotonic_time(:millisecond)
      assert end_time - start_time >= 100
    end

    test "uses default duration when not specified" do
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, %{duration_ms: 1000}} = Basic.Sleep.run(%{duration_ms: 1000}, %{})
      end_time = System.monotonic_time(:millisecond)
      assert end_time - start_time >= 1000
    end
  end

  describe "Log" do
    import ExUnit.CaptureLog

    test "logs message with specified level" do
      levels = [:debug, :info, :warning, :error]

      for level <- levels do
        log =
          capture_log(fn ->
            # Ensure all log levels are captured
            Logger.configure(level: :debug)

            assert {:ok, %{level: ^level, message: "Test message"}} =
                     Basic.Log.run(%{level: level, message: "Test message"}, %{})
          end)

        assert log =~ "Test message"
        assert log =~ "[#{level}]"
      end
    end

    test "uses default level when not specified" do
      log =
        capture_log(fn ->
          # Ensure info level is captured
          Logger.configure(level: :debug)

          assert {:ok, %{level: :info, message: "Test message"}} =
                   Basic.Log.run(%{level: :info, message: "Test message"}, %{})
        end)

      assert log =~ "[info]"
      assert log =~ "Test message"
    end
  end

  describe "Todo" do
    import ExUnit.CaptureLog

    test "logs todo message" do
      log =
        capture_log(fn ->
          # Ensure info level is captured
          Logger.configure(level: :info)

          assert {:ok, %{todo: "Implement feature"}} =
                   Basic.Todo.run(%{todo: "Implement feature"}, %{})
        end)

      assert log =~ "[info]"
      assert log =~ "TODO Action: Implement feature"
    end
  end

  describe "Delay" do
    test "introduces random delay within specified range" do
      start_time = System.monotonic_time(:millisecond)

      assert {:ok, %{min_ms: 100, max_ms: 200, actual_delay: delay}} =
               Basic.RandomSleep.run(%{min_ms: 100, max_ms: 200}, %{})

      end_time = System.monotonic_time(:millisecond)

      assert delay >= 100 and delay <= 200
      assert end_time - start_time >= delay
    end
  end

  describe "Increment" do
    test "increments the value by 1" do
      assert {:ok, %{value: 6}} = Basic.Increment.run(%{value: 5}, %{})
    end
  end

  describe "Decrement" do
    test "decrements the value by 1" do
      assert {:ok, %{value: 4}} = Basic.Decrement.run(%{value: 5}, %{})
    end
  end

  describe "Noop" do
    test "returns input params unchanged" do
      params = %{test: "value", other: 123}
      assert {:ok, ^params} = Basic.Noop.run(params, %{})
    end

    test "works with empty params" do
      assert {:ok, %{}} = Basic.Noop.run(%{}, %{})
    end
  end

  describe "Inspect" do
    import ExUnit.CaptureIO

    test "inspects simple values" do
      output =
        capture_io(fn ->
          assert {:ok, %{value: 123}} = Basic.Inspect.run(%{value: 123}, %{})
        end)

      assert output =~ "123"
    end

    test "inspects complex data structures" do
      complex_value = %{a: [1, 2, 3], b: %{c: "test"}}
      expected_output = inspect(complex_value)

      output =
        capture_io(fn ->
          assert {:ok, %{value: ^complex_value}} = Basic.Inspect.run(%{value: complex_value}, %{})
        end)

      assert String.trim(output) == expected_output
    end
  end
end
