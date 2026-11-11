Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Durability.StartAndResultTest do
  use Jido.Test.Case, async: false
  @moduletag :example

  alias Jido.Durable
  alias Jido.Durable.Status
  alias Jido.Examples.Durability.StartAndResult

  setup_all do
    Jido.Test.Examples.Loader.require_source!("05_flow_durability/05_01_start_and_result/start_and_result.ex")

    :ok
  end

  test "starts from a Signal and reads the normal Exec result" do
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, Store)}
    jido = start_durable_jido(persistence)

    {:ok, request} =
      Jido.Signal.new("examples.durable.order", %{subtotal: 10}, source: "/examples/durable")

    assert {:ok, %Status{state: :completed, ref: ref}} =
             Durable.start(jido, StartAndResult, request)

    assert {:ok, %{total: 12}} = Durable.result(jido, ref)
  end

  defp start_durable_jido(persistence) do
    suffix = System.unique_integer([:positive])
    jido = :"start_and_result_#{suffix}"

    start_supervised!(
      {Jido, name: jido, namespace: "examples/start-and-result/#{suffix}", persistence: persistence},
      id: jido
    )

    jido
  end
end
