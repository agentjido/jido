defmodule Jido.Pod.Directive.ApplyMutation do
  @moduledoc false

  alias Jido.Pod.Mutation

  @schema Zoi.struct(
            __MODULE__,
            %{
              plan: Zoi.any(description: "Pod mutation plan."),
              opts: Zoi.map(description: "Runtime mutation options.") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new!(Mutation.Plan.t(), keyword()) :: t()
  def new!(plan, opts \\ []) do
    %__MODULE__{plan: plan, opts: Map.new(opts)}
  end
end
