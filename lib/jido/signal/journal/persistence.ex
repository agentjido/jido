defmodule Jido.Signal.Journal.Persistence do
  @moduledoc """
  Defines the behavior for Journal persistence adapters.
  """
  alias Jido.Signal

  @type signal_id :: String.t()
  @type conversation_id :: String.t()
  @type error :: {:error, term()}

  @callback init() :: :ok | {:ok, pid()} | error()

  @callback put_signal(Signal.t(), pid() | nil) :: :ok | error()

  @callback get_signal(signal_id(), pid() | nil) ::
              {:ok, Signal.t()} | {:error, :not_found} | error()

  @callback put_cause(signal_id(), signal_id(), pid() | nil) :: :ok | error()

  @callback get_effects(signal_id(), pid() | nil) :: {:ok, MapSet.t()} | error()

  @callback get_cause(signal_id(), pid() | nil) ::
              {:ok, signal_id()} | {:error, :not_found} | error()

  @callback put_conversation(conversation_id(), signal_id(), pid() | nil) :: :ok | error()

  @callback get_conversation(conversation_id(), pid() | nil) :: {:ok, MapSet.t()} | error()
end
