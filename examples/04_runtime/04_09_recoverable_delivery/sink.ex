defmodule Jido.Examples.RecoverableDelivery.Sink do
  @moduledoc "The external delivery port used by the recoverable worker."

  alias Jido.Examples.RecoverableDelivery.Deliver

  @callback deliver(jido :: atom(), Deliver.t()) :: :ok | {:error, term()}
end
