defmodule Jido.Agent.StateSource do
  @moduledoc false

  alias Jido.Joi

  def ecto_schema(%{plugins: plugins}) do
    Enum.find_value(plugins, fn
      %{provider: Jido.Plugin.EctoState, data: %{schema: schema}} -> schema
      _ -> nil
    end)
  end

  # Snapshot reads can include SQL fields. Only Jido-owned fields can enter
  # the runtime or a Jido checkpoint.
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
