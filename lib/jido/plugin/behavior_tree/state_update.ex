defmodule Jido.Plugin.BehaviorTree.StateUpdate do
  @moduledoc false

  use Jido.Agent.Directive

  alias Jido.BehaviorTree.{Blackboard, Tree}
  alias Jido.{Codec, Error, Joi}

  @state_schema Joi.object(
                  %{
                    tree: Joi.struct(Tree),
                    blackboard: Joi.struct(Blackboard),
                    status: Joi.enum([:idle, :running, :success, :failure]),
                    tick_count: Joi.integer() |> Joi.min(0)
                  },
                  unrecognized_keys: :error
                )

  @enforce_keys [:state]
  defstruct [:state]

  def state_schema, do: @state_schema

  @impl true
  def validate(%__MODULE__{state: state} = update) do
    with :ok <- portable(state),
         {:ok, state} <- Jido.Agent.Directive.parse(@state_schema, state) do
      {:ok, %{update | state: state}}
    end
  end

  defp portable(state) do
    with {:error, path} <- Codec.Term.validate(state, :behavior_tree) do
      Error.validation_result(:nonportable_behavior_tree, path, "Behavior Tree state must be portable")
    end
  end
end
