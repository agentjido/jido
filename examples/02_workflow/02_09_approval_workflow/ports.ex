defmodule Jido.Examples.ApprovalWorkflow.Search do
  @moduledoc "The flight search contract."

  @callback search(client :: term(), constraints :: map()) ::
              {:ok, [map()]} | {:error, term()}
end

defmodule Jido.Examples.ApprovalWorkflow.BookingAPI do
  @moduledoc "The idempotent booking submission contract."

  @callback book(client :: term(), request :: map(), idempotency_key :: String.t()) ::
              {:ok, String.t()} | {:error, term()}
end
