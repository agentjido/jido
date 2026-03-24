defmodule Jido.Agent.StateOp do
  @moduledoc """
  State operations that strategies handle to update agent state.

  These are **not** directives - they never leave the strategy layer.
  They are separated from directives to maintain a clean boundary:

  - **State operations** → modify agent state within the strategy
  - **Directives** → external effects for the runtime to execute

  ## Available State Operations

  - `SetState` - Deep merge attributes into state
  - `ReplaceState` - Replace state wholesale (no merge)
  - `DeleteKeys` - Remove top-level keys from state
  - `SetPath` - Set value at a nested path
  - `DeletePath` - Delete value at a nested path
  - `AppendThread` - Append one or more entries to the default thread journal

  ## Usage

  Actions can return state operations alongside directives:

      alias Jido.Agent.{Directive, StateOp}

      {:ok, result, [
        %StateOp.SetState{attrs: %{status: :processing}},
        %Directive.Emit{signal: my_signal}
      ]}

  The strategy applies state operations to the agent and passes through
  directives to the runtime.
  """

  alias __MODULE__.{SetState, ReplaceState, DeleteKeys, SetPath, DeletePath, AppendThread}

  @typedoc "Any state operation struct."
  @type t ::
          SetState.t()
          | ReplaceState.t()
          | DeleteKeys.t()
          | SetPath.t()
          | DeletePath.t()
          | AppendThread.t()

  # ============================================================================
  # SetState - Merge attributes into agent state
  # ============================================================================

  defmodule SetState do
    @moduledoc """
    Deep merge attributes into the agent's state.

    Uses `DeepMerge.deep_merge/2` semantics - nested maps are merged recursively.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                attrs: Zoi.map(description: "Attributes to merge into agent state")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for SetState."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # ReplaceState - Replace state wholesale
  # ============================================================================

  defmodule ReplaceState do
    @moduledoc """
    Replace the agent's state wholesale (no merge).

    Use cases:
    - Reset strategy state completely
    - Replace large blob structures
    - Ensure no stale keys remain from previous state
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                state: Zoi.map(description: "Complete new state to replace existing")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for ReplaceState."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # DeleteKeys - Remove top-level keys from state
  # ============================================================================

  defmodule DeleteKeys do
    @moduledoc """
    Delete top-level keys from the agent's state.

    Use cases:
    - Clear ephemeral/transient keys
    - Remove strategy-only keys after completion
    - Clean up temporary data without full state replacement
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                keys: Zoi.list(Zoi.atom(), description: "Top-level keys to delete")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for DeleteKeys."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # SetPath - Set value at nested path
  # ============================================================================

  defmodule SetPath do
    @moduledoc """
    Set a value at a nested path in the agent's state.

    Uses `put_in/3` semantics. Path must be a list of atoms.

    ## Example

        %SetPath{path: [:config, :timeout], value: 5000}
        # Sets agent.state.config.timeout = 5000
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                path: Zoi.list(Zoi.atom(), description: "Path to the key (list of atoms)"),
                value: Zoi.any(description: "Value to set at path")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for SetPath."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # DeletePath - Delete value at nested path
  # ============================================================================

  defmodule DeletePath do
    @moduledoc """
    Delete a value at a nested path in the agent's state.

    Uses `pop_in/2` semantics. Path must be a list of atoms.

    ## Example

        %DeletePath{path: [:temp, :cache]}
        # Removes agent.state.temp.cache
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                path: Zoi.list(Zoi.atom(), description: "Path to delete (list of atoms)")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for DeletePath."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # AppendThread - Append entries to the default thread journal
  # ============================================================================

  defmodule AppendThread do
    @moduledoc """
    Append one or more entries to the default thread journal stored at
    `agent.state[:__thread__]`.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                entries: Zoi.list(Zoi.any(), description: "Entries to append to the thread")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for AppendThread."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # Helper Constructors
  # ============================================================================

  @doc "Creates a SetState state operation."
  @spec set_state(map()) :: SetState.t()
  def set_state(attrs) when is_map(attrs), do: %SetState{attrs: attrs}

  @doc "Creates a ReplaceState state operation."
  @spec replace_state(map()) :: ReplaceState.t()
  def replace_state(state) when is_map(state), do: %ReplaceState{state: state}

  @doc "Creates a DeleteKeys state operation."
  @spec delete_keys([atom()]) :: DeleteKeys.t()
  def delete_keys(keys) when is_list(keys), do: %DeleteKeys{keys: keys}

  @doc "Creates a SetPath state operation."
  @spec set_path([atom()], term()) :: SetPath.t()
  def set_path(path, value) when is_list(path), do: %SetPath{path: path, value: value}

  @doc "Creates a DeletePath state operation."
  @spec delete_path([atom()]) :: DeletePath.t()
  def delete_path(path) when is_list(path), do: %DeletePath{path: path}

  @doc "Creates an AppendThread state operation."
  @spec append_thread(map() | struct() | [map() | struct()]) :: AppendThread.t()
  def append_thread(entry_or_entries)
      when is_map(entry_or_entries) or is_struct(entry_or_entries),
      do: %AppendThread{entries: [entry_or_entries]}

  def append_thread(entry_or_entries) when is_list(entry_or_entries),
    do: %AppendThread{entries: entry_or_entries}
end
