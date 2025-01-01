defmodule JidoTest.SignalTest do
  use ExUnit.Case, async: true
  alias Jido.Signal

  describe "from_map/1" do
    test "creates a valid Signal struct with required fields" do
      map = %{
        "specversion" => "1.0.2",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123"
      }

      assert {:ok, signal} = Signal.from_map(map)
      assert %Signal{} = signal
      assert signal.specversion == "1.0.2"
      assert signal.type == "example.event"
      assert signal.source == "/example"
      assert signal.id == "123"
    end

    test "creates a valid Signal struct with all fields" do
      map = %{
        "specversion" => "1.0.2",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123",
        "subject" => "test_subject",
        "time" => "2023-05-20T12:00:00Z",
        "datacontenttype" => "application/json",
        "dataschema" => "https://example.com/schema",
        "data" => %{"key" => "value"},
        "jidoinstructions" => [{:action1, %{param1: "value1"}}],
        "jidoopts" => %{"opt1" => "value1"}
      }

      assert {:ok, signal} = Signal.from_map(map)
      assert %Signal{} = signal
      assert signal.subject == "test_subject"
      assert signal.time == "2023-05-20T12:00:00Z"
      assert signal.datacontenttype == "application/json"
      assert signal.dataschema == "https://example.com/schema"
      assert signal.data == %{"key" => "value"}
      assert signal.jidoinstructions == [{:action1, %{param1: "value1"}}]
      assert signal.jidoopts == %{"opt1" => "value1"}
    end

    test "returns error for invalid specversion" do
      map = %{
        "specversion" => "1.0",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123"
      }

      assert {:error, "parse error: unexpected specversion 1.0"} = Signal.from_map(map)
    end

    test "returns error for missing required fields" do
      map = %{"specversion" => "1.0.2"}
      assert {:error, "parse error: missing type"} = Signal.from_map(map)
    end

    test "handles empty optional fields" do
      map = %{
        "specversion" => "1.0.2",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123",
        "subject" => "",
        "time" => "",
        "datacontenttype" => "",
        "dataschema" => ""
      }

      assert {:error, _} = Signal.from_map(map)
    end

    test "sets default datacontenttype for non-nil data" do
      map = %{
        "specversion" => "1.0.2",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123",
        "data" => %{"key" => "value"}
      }

      assert {:ok, signal} = Signal.from_map(map)
      assert signal.datacontenttype == "application/json"
    end

    test "handles jidoinstructions and jidoopts fields" do
      map = %{
        "specversion" => "1.0.2",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123",
        "jidoinstructions" => [{:action1, %{param1: "value1"}}],
        "jidoopts" => %{"opt1" => "value1"}
      }

      assert {:ok, signal} = Signal.from_map(map)
      assert signal.jidoinstructions == [{:action1, %{param1: "value1"}}]
      assert signal.jidoopts == %{"opt1" => "value1"}
    end

    test "returns error for invalid jidoinstructions format" do
      map = %{
        "specversion" => "1.0.2",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123",
        "jidoinstructions" => "invalid_format"
      }

      assert {:error, "parse error: jidoinstructions must be a list of instructions"} =
               Signal.from_map(map)
    end

    test "returns error for invalid jidoopts format" do
      map = %{
        "specversion" => "1.0.2",
        "type" => "example.event",
        "source" => "/example",
        "id" => "123",
        "jidoopts" => "invalid_format"
      }

      assert {:error, "parse error: jidoopts must be a map"} = Signal.from_map(map)
    end
  end
end
