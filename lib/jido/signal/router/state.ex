defmodule Jido.Signal.Router.State do
  @moduledoc false

  @empty_wildcard_index %{
    id: 0,
    exact: %{},
    single: nil,
    multi: nil,
    terminals: [],
    globstar?: false
  }

  @type t :: %__MODULE__{
          entries: [map()],
          exact_index: %{optional(String.t()) => [map()]},
          wildcard_index: map(),
          next_order: non_neg_integer(),
          next_node_id: pos_integer()
        }

  defstruct entries: [],
            exact_index: %{},
            wildcard_index: @empty_wildcard_index,
            next_order: 0,
            next_node_id: 1
end
