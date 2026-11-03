defmodule Jido.Signal.ID do
  @moduledoc """
  Compatibility facade for the former Signal UUIDv7 API.

  Use `Jido.Id` for new code.
  """

  @type uuid7 :: Jido.Id.uuid7()
  @type timestamp :: Jido.Id.timestamp()
  @type comparison_result :: Jido.Id.comparison_result()

  @doc "Returns a new UUID7 and its embedded Unix millisecond timestamp."
  @spec generate() :: {uuid7(), timestamp()}
  def generate do
    uuid = Jido.Id.uuid7()
    {uuid, Jido.Id.uuid7_timestamp(uuid)}
  end

  @doc "Returns a new UUID7 string."
  @spec generate!() :: uuid7()
  def generate!, do: Jido.Id.uuid7()

  @doc "Returns the Unix millisecond timestamp embedded in a valid UUID7."
  @spec extract_timestamp(uuid7()) :: timestamp()
  def extract_timestamp(uuid), do: Jido.Id.uuid7_timestamp(uuid)

  @doc "Compares the complete binary values of two valid UUID7 strings."
  @spec compare(uuid7(), uuid7()) :: comparison_result()
  def compare(uuid1, uuid2), do: Jido.Id.compare_uuid7(uuid1, uuid2)

  @doc "Returns true when the value is a valid UUID7 string."
  @spec valid?(term()) :: boolean()
  def valid?(uuid), do: Jido.Id.uuid7?(uuid)
end
