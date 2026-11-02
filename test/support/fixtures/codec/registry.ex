defmodule JidoActionTest.Fixtures.CodecRegistry do
  @moduledoc false

  alias Jido.Authoring.Registry
  alias JidoActionTest.Fixtures.NestedFlow
  alias JidoActionTest.Fixtures.Actions.{Add, Multiply}

  def mixed do
    Registry.new!(%{
      {"actions/add", 1} => {:action, Add},
      {"actions/multiply", 1} => {:action, Multiply},
      {"flows/nested", 1} => {:flow, NestedFlow},
      {"schemas/map", 1} => {:schema, Zoi.map()},
      {"schemas/object", 1} => {:schema, Zoi.object(%{})},
      {"atoms/add", 1} => {:atom, :add},
      {"atoms/amount", 1} => {:atom, :amount},
      {"atoms/count", 1} => {:atom, :count},
      {"atoms/debug", 1} => {:atom, :debug},
      {"atoms/go", 1} => {:atom, :go},
      {"atoms/items", 1} => {:atom, :items},
      {"atoms/kind", 1} => {:atom, :kind},
      {"atoms/owner", 1} => {:atom, :owner},
      {"atoms/value", 1} => {:atom, :value}
    })
  end

  def storage do
    Registry.new!(%{
      {"action/add/v1", 1} => {:action, Add},
      {"action/multiply/v1", 1} => {:action, Multiply},
      {"schema/map/v1", 1} => {:schema, Zoi.map()},
      {"atom/amount/v1", 1} => {:atom, :amount},
      {"atom/atom-key/v1", 1} => {:atom, :atom_key},
      {"atom/bad/v1", 1} => {:atom, :bad},
      {"atom/blocked/v1", 1} => {:atom, :blocked},
      {"atom/disabled/v1", 1} => {:atom, :disabled},
      {"atom/host/v1", 1} => {:atom, :host},
      {"atom/id/v1", 1} => {:atom, :id},
      {"atom/items/v1", 1} => {:atom, :items},
      {"atom/key/v1", 1} => {:atom, :key},
      {"atom/kind/v1", 1} => {:atom, :kind},
      {"atom/line/v1", 1} => {:atom, :line},
      {"atom/payload/v1", 1} => {:atom, :payload},
      {"atom/ready/v1", 1} => {:atom, :ready},
      {"atom/request/v1", 1} => {:atom, :request},
      {"atom/result/v1", 1} => {:atom, :result},
      {"atom/selected/v1", 1} => {:atom, :selected},
      {"atom/source/v1", 1} => {:atom, :source},
      {"atom/state/v1", 1} => {:atom, :state},
      {"atom/status/v1", 1} => {:atom, :status},
      {"atom/test/v1", 1} => {:atom, :test},
      {"atom/value/v1", 1} => {:atom, :value}
    })
  end
end
