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
  - `agent_id` - Elixir.Agent ID
  - `parent_thread_id` / `child_thread_id` - Thread relationships
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Unique entry identifier") |> Zoi.min(1),
              seq: Zoi.integer(description: "Monotonic sequence within thread") |> Zoi.min(0),
              at: Zoi.integer(description: "Timestamp (ms)"),
              kind: Zoi.atom(description: "Entry type - open, any atom accepted"),
              payload: Zoi.map(description: "Kind-specific data") |> Zoi.default(%{}),
              refs:
                Zoi.map(description: "Cross-references to other primitives") |> Zoi.default(%{})
            },
            coerce: true
          )
          |> Zoi.refine({__MODULE__, :validate_input_type, []})

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the data schema for a Thread Entry."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc false
  def validate_input_type(%__MODULE__{}, opts) do
    case get_in(opts, [:ctx, Access.key(:input)]) do
      %__MODULE__{} -> :ok
      input when is_struct(input) -> {:error, "Entry schema does not accept unrelated structs"}
      _input -> :ok
    end
  end

  @doc "Create a new entry from attributes"
  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    now = System.system_time(:millisecond)

    %__MODULE__{
      id: entry_id(attrs),
      seq: fetch_attr(attrs, :seq, 0),
      at: fetch_attr(attrs, :at, now),
      kind: fetch_attr(attrs, :kind, :note),
      payload: fetch_attr(attrs, :payload, %{}),
      refs: fetch_attr(attrs, :refs, %{})
    }
  end

  defp fetch_attr(attrs, key, default \\ nil) do
    value =
      case Map.fetch(attrs, key) do
        {:ok, value} -> value
        :error -> Map.get(attrs, Atom.to_string(key))
      end

    case value do
      nil -> default
      value -> value
    end
  end

  defp entry_id(attrs) do
    case fetch_attr(attrs, :id) do
      nil -> generate_id()
      id -> id
    end
  end

  defp generate_id, do: "entry_" <> Jido.Util.generate_id()
end
