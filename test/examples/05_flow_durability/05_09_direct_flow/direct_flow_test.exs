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

  test "runs a durable Flow without an Agent" do
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, Store)}
    jido = start_durable_jido(persistence)

    {:ok, request} =
      Jido.Signal.new("examples.durable.order", %{subtotal: 10}, source: "/examples/durable")

    assert {:ok, %Status{state: :completed, ref: ref}} =
             Durable.start(jido, DirectFlow, request)

    assert {:ok, %{total: 12}} = Durable.result(jido, ref)
  end

  defp start_durable_jido(persistence) do
    suffix = System.unique_integer([:positive])
    jido = :"direct_flow_durable_#{suffix}"

    start_supervised!(
      {Jido, name: jido, namespace: "examples/direct-flow/#{suffix}", persistence: persistence},
      id: jido
    )

    jido
  end
end
