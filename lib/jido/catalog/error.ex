defmodule Jido.Catalog.Error do
  @moduledoc "An invalid Catalog reference or registration."

  use Splode.Error,
    class: :invalid,
    fields: [message: "Invalid Catalog operation", details: %{}]

  @type t :: %__MODULE__{message: String.t(), details: map()}
end
