defmodule JidoTest.SignalTest do
  use JidoTest.Case, async: true
  alias Jido.Signal

  describe "new/1" do
    test "creates a signal with default id and source" do
      {:ok, signal} = Signal.new(%{type: "example.event"})

      assert is_binary(signal.id)
      # UUID length
      assert String.length(signal.id) == 36
      assert signal.source == "Elixir.JidoTest.SignalTest"
      assert signal.type == "example.event"
    end

    test "allows overriding default id and source" do
      {:ok, signal} =
        Signal.new(%{
          id: "custom-id",
          source: "custom-source",
          type: "example.event"
        })

      assert signal.id == "custom-id"
      assert signal.source == "custom-source"
    end

    test "sets specversion and time defaults" do
      {:ok, signal} = Signal.new(%{type: "example.event"})

      assert signal.specversion == "1.0.2"
      assert is_binary(signal.time)
      # ISO8601 format
      assert String.contains?(signal.time, "T")
    end
  end

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
        "data" => %{"key" => "value"}
      }

      assert {:ok, signal} = Signal.from_map(map)
      assert %Signal{} = signal
      assert signal.subject == "test_subject"
      assert signal.time == "2023-05-20T12:00:00Z"
      assert signal.datacontenttype == "application/json"
      assert signal.dataschema == "https://example.com/schema"
      assert signal.data == %{"key" => "value"}
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
  end
end
