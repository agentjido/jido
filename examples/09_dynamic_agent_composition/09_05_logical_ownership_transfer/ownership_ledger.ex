defmodule Jido.Examples.OwnershipLedger do
  @moduledoc "Stores application-level logical ownership of independent Agents."

  use Jido.Agent, name: "dynamic_ownership_ledger"

  state do
    schema Jido.Joi.object(%{owners: Jido.Joi.map() |> Jido.Joi.default(%{})})
  end

  routes do
    signal_source "/examples/multi-agent/ownership"

    route "examples.multi_agent.ownership.adopt", as: :adopt do
      action %{agent_ref: agent_ref, owner: owner},
        schema:
          Jido.Joi.object(%{
            agent_ref: Jido.Joi.map(),
            owner: Jido.Joi.string() |> Jido.Joi.min(1)
          }),
        context: context do
        key = ownership_key(agent_ref)

        if Map.has_key?(context.agent_state.owners, key) do
          {:error, Jido.Error.validation_error("Agent already has a logical owner")}
        else
          {:ok, put_in(context.agent_state, [:owners, key], owner)}
        end
      end
    end

    route "examples.multi_agent.ownership.transfer", as: :transfer do
      action %{agent_ref: agent_ref, from: from, to: to},
        schema:
          Jido.Joi.object(%{
            agent_ref: Jido.Joi.map(),
            from: Jido.Joi.string() |> Jido.Joi.min(1),
            to: Jido.Joi.string() |> Jido.Joi.min(1)
          }),
        context: context do
        key = ownership_key(agent_ref)

        case Map.get(context.agent_state.owners, key) do
          ^from -> {:ok, put_in(context.agent_state, [:owners, key], to)}
          _other -> {:error, Jido.Error.validation_error("logical owner does not match")}
        end
      end
    end
  end

  def ownership_key(agent_ref),
    do: agent_ref |> Enum.sort() |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)
end
