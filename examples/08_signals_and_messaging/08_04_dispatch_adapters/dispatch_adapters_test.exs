Code.require_file("dispatch_adapters.ex", __DIR__)

defmodule Jido.Examples.Signals.DispatchAdaptersTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Signals.DispatchAdapters
  alias Jido.Signal.Dispatch

  test "delivers to local adapters in order" do
    signal = Jido.Signal.new!("examples.dispatch.created", %{}, source: "/dispatch")

    assert :ok = Dispatch.dispatch(signal, DispatchAdapters.local_targets(self()))
    assert_receive {:signal, ^signal}
    assert_receive {:captured_signal, ^signal}
  end

  test "validates an HTTP target without contacting it" do
    assert {:ok, {:http, options}} = DispatchAdapters.validate_http_target()
    assert options[:url] == "https://example.test/events"
  end
end
