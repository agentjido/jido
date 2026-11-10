defmodule Jido.Test.Codec.Fixtures.CodecRegistry do
  @moduledoc false

  alias Jido.Catalog
  alias Jido.Test.Flow.Fixtures.NestedFlow
  alias Jido.Test.Action.Fixtures.Actions.{Add, Multiply}

  def mixed do
    Catalog.from_targets!(__MODULE__, :jido, %{
      {"actions/add", 1} => Add,
      {"actions/multiply", 1} => Multiply,
      {"flows/nested", 1} => NestedFlow,
      {"schemas/map", 1} => Jido.Joi.map(),
      {"schemas/object", 1} => Jido.Joi.object(%{}),
      {"atoms/add", 1} => :add,
      {"atoms/amount", 1} => :amount,
      {"atoms/count", 1} => :count,
      {"atoms/debug", 1} => :debug,
      {"atoms/go", 1} => :go,
      {"atoms/items", 1} => :items,
      {"atoms/kind", 1} => :kind,
      {"atoms/owner", 1} => :owner,
      {"atoms/value", 1} => :value
    })
  end

  def storage do
    Catalog.from_targets!(__MODULE__, :jido, %{
      {"action/add/v1", 1} => Add,
      {"action/multiply/v1", 1} => Multiply,
      {"schema/map/v1", 1} => Jido.Joi.map(),
      {"atom/amount/v1", 1} => :amount,
      {"atom/atom-key/v1", 1} => :atom_key,
      {"atom/bad/v1", 1} => :bad,
      {"atom/blocked/v1", 1} => :blocked,
      {"atom/disabled/v1", 1} => :disabled,
      {"atom/host/v1", 1} => :host,
      {"atom/id/v1", 1} => :id,
      {"atom/items/v1", 1} => :items,
      {"atom/key/v1", 1} => :key,
      {"atom/kind/v1", 1} => :kind,
      {"atom/line/v1", 1} => :line,
      {"atom/payload/v1", 1} => :payload,
      {"atom/ready/v1", 1} => :ready,
      {"atom/request/v1", 1} => :request,
      {"atom/result/v1", 1} => :result,
      {"atom/selected/v1", 1} => :selected,
      {"atom/source/v1", 1} => :source,
      {"atom/state/v1", 1} => :state,
      {"atom/status/v1", 1} => :status,
      {"atom/test/v1", 1} => :test,
      {"atom/value/v1", 1} => :value
    })
  end
end
