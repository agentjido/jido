defmodule Jido.Test.CodecFixtures.Address do
  @moduledoc false

  alias Jido.Joi

  @schema Joi.struct(__MODULE__, %{
            street: Joi.string(),
            postal_code: Joi.string()
          })

  use Jido.Codec, schema: @schema
  codec(:postal_code, as: "postalCode")

  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  def schema, do: @schema
end

defmodule Jido.Test.CodecFixtures.Person do
  @moduledoc false

  alias Jido.Joi
  alias Jido.Test.CodecFixtures.Address

  @schema Joi.struct(__MODULE__, %{
            name: Joi.string(),
            address: Address.schema(),
            state: Joi.enum([:active, :disabled]),
            nickname: Joi.string() |> Joi.nullable() |> Joi.default(nil),
            tag: Joi.string()
          })

  use Jido.Codec, schema: @schema
  codec(:name, decode: :normalize_name, encode: :lower_name)
  codec(:nickname, omit: nil)

  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  def schema, do: @schema
  def normalize_name(value), do: String.trim(value)
  def lower_name(value), do: String.downcase(value)
end

defmodule Jido.Test.CodecFixtures.NamedMap do
  @moduledoc false

  alias Jido.Joi

  @schema Joi.map(
            %{
              state: Joi.enum([:ready, :stopped]),
              count: Joi.integer()
            },
            unrecognized_keys: :error
          )

  use Jido.Codec, schema: @schema
end
