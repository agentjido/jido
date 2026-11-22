defmodule Jido.Examples.Plugins.StateMiddleware.Note do
  @moduledoc "A validated fact that the state middleware records."

  alias Jido.Joi

  use Jido.Agent.Directive

  @schema Joi.struct(__MODULE__, %{label: Joi.string() |> Joi.min(1)}, coerce: true)
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  def schema, do: @schema
end

defmodule Jido.Examples.Plugins.StateMiddleware.Plugin do
  @moduledoc "Observes each successful candidate and reduces one owned audit field."

  alias Jido.Joi

  use Jido.Plugin

  alias Jido.Agent.Plugin.{Preparation, Reduction}
  alias Jido.Examples.Plugins.StateMiddleware.Note

  @impl true
  def state_spec(_opts) do
    {:audit,
     Joi.object(%{
       count_after: Joi.integer(),
       count_before: Joi.integer(),
       label: Joi.string(),
       turns: Joi.integer() |> Joi.min(0)
     })
     |> Joi.default(%{count_after: 0, count_before: 0, label: "", turns: 0})}
  end

  @impl true
  def directives(_opts), do: [Note]

  @impl true
  def prepare(%Preparation{agent_state: state}, _opts),
    do: {:ok, %{count_before: state.count}}

  @impl true
  def reduce(%Reduction{} = reduction, _opts) do
    label =
      Enum.find_value(reduction.directives, "", fn
        %Note{label: label} -> label
        _directive -> nil
      end)

    {:ok,
     %{
       count_after: reduction.candidate_state.count,
       count_before: reduction.prepared_input.count_before,
       label: label,
       turns: reduction.plugin_state.turns + 1
     }}
  end
end

defmodule Jido.Examples.Plugins.StateMiddleware.Agent do
  @moduledoc "Changes domain state while a Plugin reduces its separate owned field."

  alias Jido.Joi

  use Jido.Agent,
    name: "plugin_state_middleware_agent",
    plugins: [Jido.Examples.Plugins.StateMiddleware.Plugin]

  state do
    schema Joi.object(%{count: Joi.integer() |> Joi.default(0)})
  end

  routes do
    signal_source "/examples/plugins/state_middleware"

    route "examples.plugins.state_middleware.add" do
      action %{amount: amount, label: label},
        schema: Joi.object(%{amount: Joi.integer(), label: Joi.string() |> Joi.min(1)}),
        context: context do
        next_state = %{context.agent_state | count: context.agent_state.count + amount}
        note = %Jido.Examples.Plugins.StateMiddleware.Note{label: label}
        {:ok, next_state, [note]}
      end
    end
  end
end
