defmodule Jido.Signal.Bus.TypeSelectionTest do
  use JidoSignalTest.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Bus

  test "default observation selection uses the type path and ignores other Signal fields" do
    events = [
      Signal.new!("sensor.reading", nil, source: "/first"),
      Signal.new!("sensor.reading", false,
        source: "/second",
        subject: "sensor-2",
        time: "2026-10-12T12:00:00Z",
        datacontenttype: "application/json",
        dataschema: "https://example.com/sensor/v1",
        extensions: %{"region" => "west"}
      ),
      Signal.new!("sensor.reading", %{"status" => "critical"},
        source: "/third",
        subject: "sensor-3",
        time: "2026-10-12T13:00:00Z",
        extensions: %{"region" => "east"}
      )
    ]

    unrelated = %{List.last(events) | type: "inventory.updated"}

    for path <- ["sensor.reading", "sensor.*", "sensor.**", "**.reading"] do
      bus = start_supervised!({Bus, name: unique_name("type_selection")})
      assert {:ok, _} = Bus.subscribe(bus, path)
      assert {:ok, records} = Bus.publish(bus, events ++ [unrelated])
      assert Enum.map(records, & &1.signal) == events ++ [unrelated]

      for expected <- events do
        assert_received {:signal, received}
        assert received == expected
      end

      refute_received {:signal, _}
    end
  end
end
