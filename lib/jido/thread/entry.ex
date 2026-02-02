defmodule Jido.Thread.Entry do
  @moduledoc """
  A single entry in a Thread. Typed by `kind` with kind-specific payload.

  Entries are immutable once appended. The `refs` map provides cross-links
  to other Jido primitives (signals, instructions, actions).

  ## Entry Kinds

  Kinds are open - any atom is accepted. Recommended kinds include:
  - `:message` - User/assistant/system message
  - `:tool_call` - Tool execution request
  - `:tool_result` - Tool execution result
  - `:signal_in` / `:signal_out` - Signal events
  - `:instruction_start` / `:instruction_end` - Instruction execution
  - `:note` - Human annotation
  - `:error` - Error occurred
  - `:checkpoint` - State snapshot marker

  ## Refs Conventions

  Common ref keys (not enforced):
  - `signal_id` - Associated signal ID
  - `instruction_id` - Associated instruction ID
  - `action` - Action module name
  - `agent_id` - Agent ID
  - `parent_thread_id` / `child_thread_id` - Thread relationships
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Unique entry identifier"),
              seq: Zoi.integer(description: "Monotonic sequence within thread"),
              at: Zoi.integer(description: "Timestamp (ms)"),
              kind: Zoi.atom(description: "Entry type - open, any atom accepted"),
              payload: Zoi.map(description: "Kind-specific data") |> Zoi.default(%{}),
              refs:
                Zoi.map(description: "Cross-references to other primitives") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Create a new entry from attributes"
  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: attrs[:id] || Map.get(attrs, "id"),
      seq: attrs[:seq] || Map.get(attrs, "seq") || 0,
      at: attrs[:at] || Map.get(attrs, "at") || System.system_time(:millisecond),
      kind: attrs[:kind] || Map.get(attrs, "kind") || :note,
      payload: attrs[:payload] || Map.get(attrs, "payload") || %{},
      refs: attrs[:refs] || Map.get(attrs, "refs") || %{}
    }
  end
end
