Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Durability.DirectFlowTest do
  use Jido.Test.Case, async: false
  @moduletag :example

  alias Jido.Durable
  alias Jido.Durable.Status
  alias Jido.Examples.Durability.DirectFlow

  setup_all do
    Jido.Test.Examples.Loader.require_source!("05_flow_durability/05_09_direct_flow/direct_flow.ex")
    :ok
  end

  test "runs a durable Flow without an Agent", c do
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, Store)}

    {:ok, request} =
      Jido.Signal.new("examples.durable.order", %{subtotal: 10}, source: "/examples/durable")

    assert {:ok, %Status{state: :completed, ref: ref}} =
             Durable.start(c.jido, DirectFlow, request, persistence: persistence)

    assert {:ok, %{total: 12}} = Durable.result(c.jido, ref, persistence: persistence)
  end
end
