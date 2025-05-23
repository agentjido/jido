#
# Type Provider from Commanded: https://github.com/commanded/commanded/blob/master/lib/commanded/event_store/type_provider.ex
# License: MIT
#
defmodule Jido.Signal.Serialization.TypeProvider do
  @moduledoc """
  Specification to convert between an Elixir struct and a corresponding string type.
  """

  @type t :: module
  @type type :: String.t()

  @doc """
  Type of the given Elixir struct as a string
  """
  @callback to_string(struct) :: type

  @doc """
  Convert the given type string to an Elixir struct
  """
  @callback to_struct(type) :: struct

  @doc false
  @spec to_string(struct) :: type
  def to_string(struct), do: type_provider().to_string(struct)

  @doc false
  @spec to_struct(type) :: struct
  def to_struct(type), do: type_provider().to_struct(type)

  @doc """
  Get the configured type provider
  """
  @spec type_provider() :: module()
  def type_provider do
    Jido.Signal.Serialization.Config.default_type_provider()
  end
end
