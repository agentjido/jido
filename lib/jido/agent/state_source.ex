defmodule Jido.Agent.StateSource do
  @moduledoc false

  alias Jido.Joi

  def ecto_schema(%{plugins: plugins}) do
    Enum.find_value(plugins, fn
      %{provider: Jido.Plugin.EctoState, data: %{schema: schema}} -> schema
      _ -> nil
    end)
  end

  def observe(agent, %{__struct__: schema} = row) do
    row
    |> Map.take(schema.__schema__(:fields))
    |> Map.merge(agent.state)
  end

  def turn_state(agent, plugin_inputs) do
    case Map.get(plugin_inputs, Jido.Plugin.EctoState) do
      %{runtime: %{row: row}} -> observe(agent, row)
      _ -> agent.state
    end
  end

  # A handler can return the state it read. Remove unchanged SQL fields
  # before validating the candidate. A changed field must fail validation.
  def drop_copied_fields(candidate, stored, observed)
      when stored === observed or candidate === stored,
      do: candidate

  def drop_copied_fields(candidate, stored, observed) do
    copied =
      for {key, value} <- observed,
          not Map.has_key?(stored, key),
          Map.fetch(candidate, key) === {:ok, value},
          do: key

    Map.drop(candidate, copied)
  end

  # Snapshot reads can include SQL fields. Keep only Jido-owned fields when
  # using an observed Agent as input or writing a Jido checkpoint.
  def stored_state(agent, schema) do
    with state when is_map(state) and not is_struct(state) <- agent.state,
         ecto when not is_nil(ecto) <- ecto_schema(agent),
         {:ok, fields} <- Joi.Schema.fields(schema) do
      owned_keys = Enum.map(fields, &elem(&1, 0))
      Map.drop(state, ecto.__schema__(:fields) -- owned_keys)
    else
      _ -> agent.state
    end
  end
end
