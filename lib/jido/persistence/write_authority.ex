defmodule Jido.Persistence.WriteAuthority do
  @moduledoc """
  A migration gate that routes compatible and Ref persistence calls to one key.

  Create this value with `Jido.Persistence.establish_write_authority/4` after
  old writers stop. Pass the same value as `:write_authority` to every writer
  during the identity migration.
  """

  @enforce_keys [
    :instance,
    :agent_module,
    :agent_id,
    :partition,
    :namespace,
    :mode,
    :key,
    :other_key
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          instance: atom() | nil,
          agent_module: module(),
          agent_id: String.t(),
          partition: term(),
          namespace: String.t(),
          mode: :legacy | :ref,
          key: binary(),
          other_key: binary()
        }
end
