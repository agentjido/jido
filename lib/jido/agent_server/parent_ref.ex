defmodule Jido.AgentServer.ParentRef do
  @moduledoc """
  Reference to a logical parent agent in Jido hierarchy tracking.

  `ParentRef` models Jido's logical parent-child relationship, which is layered
  on top of OTP supervision. Parent and child agents are still OTP peers under
  a supervisor; the parent relationship is represented explicitly with this
  struct, child-start signals, and process monitors.

  While a child is attached, the runtime injects this value into
  `agent.state.__parent__` so child actions can use `Directive.emit_to_parent/3`.
  If the child becomes orphaned, the current parent ref is cleared and the former
  parent is moved to `agent.state.__orphaned_from__`.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              pid: Zoi.any(description: "Parent process PID"),
              id: Zoi.string(description: "Parent instance ID"),
              tag: Zoi.any(description: "Tag assigned by parent when spawning this child"),
              meta: Zoi.map(description: "Arbitrary metadata from parent") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Creates a new ParentRef from a map of attributes.

  Returns `{:ok, parent_ref}` or `{:error, reason}`.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    Zoi.parse(@schema, attrs)
  end

  def new(_), do: {:error, Jido.Error.validation_error("ParentRef requires a map")}

  @doc """
  Creates a new ParentRef from a map, raising on error.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, parent_ref} -> parent_ref
      {:error, reason} -> raise Jido.Error.validation_error("Invalid ParentRef", details: reason)
    end
  end

  @doc """
  Validates that a value is a valid ParentRef.
  """
  @spec validate(term()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = parent_ref), do: {:ok, parent_ref}
  def validate(attrs) when is_map(attrs), do: new(attrs)
  def validate(_), do: {:error, Jido.Error.validation_error("Expected a ParentRef struct or map")}
end
