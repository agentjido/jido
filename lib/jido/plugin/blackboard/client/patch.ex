defmodule Jido.Plugin.Blackboard.Client.Patch do
  @moduledoc """
  Requests a conditional board patch after the owning Agent commits.

  Set `:revision` to the token from the snapshot used for the decision.
  Set `:request_id` to a caller-chosen identifier for the result Signal.
  """

  use Jido.Agent.Directive

  alias Jido.{Blackboard, Error, Joi}

  @schema Joi.struct(
            __MODULE__,
            %{
              request_id: Joi.string() |> Joi.min(1),
              revision: Joi.string() |> Joi.min(1),
              put: Joi.map() |> Joi.default(%{}),
              delete: Joi.list(Joi.string()) |> Joi.default([])
            },
            coerce: true
          )

  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc "Returns the Directive schema."
  @spec schema() :: Joi.schema()
  def schema, do: @schema

  @impl true
  def validate(%__MODULE__{} = patch) do
    with {:ok, patch} <- super(patch),
         :ok <- Blackboard.validate_changes(patch.put, patch.delete) do
      {:ok, patch}
    else
      {:error, :invalid_request} ->
        Error.validation_result(:invalid_directive, [], "Blackboard patch contains invalid changes", %{})

      {:error, _reason} = error ->
        error
    end
  end

  def validate(other), do: super(other)
end
