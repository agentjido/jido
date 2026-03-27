defmodule Jido.AgentServer.ChildInfo do
  @moduledoc """
  Information about a child agent in the logical hierarchy.

  > #### Internal Module {: .warning}
  > This module is internal to the AgentServer implementation. Its API may
  > change without notice.

  Used for parent agents to track spawned children.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              pid: Zoi.any(description: "Child process PID"),
              ref: Zoi.any(description: "Monitor reference for the child process"),
              module: Zoi.atom(description: "Child agent module"),
              id: Zoi.string(description: "Child instance ID"),
              partition:
                Zoi.any(description: "Logical partition of the child agent")
                |> Zoi.optional(),
              tag: Zoi.any(description: "Tag used when spawning") |> Zoi.optional(),
              meta: Zoi.map(description: "Metadata passed during spawn") |> Zoi.default(%{})
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
  Creates a new ChildInfo from a map of attributes.

  Returns `{:ok, child_info}` or `{:error, reason}`.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    Zoi.parse(@schema, attrs)
  end

  def new(_), do: {:error, Jido.Error.validation_error("ChildInfo requires a map")}

  @doc """
  Creates a new ChildInfo from a map, raising on error.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, child_info} -> child_info
      {:error, reason} -> raise Jido.Error.validation_error("Invalid ChildInfo", details: reason)
    end
  end
end
