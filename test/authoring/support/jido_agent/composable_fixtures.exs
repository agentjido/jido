defmodule Jido.Test.Agent.Authoring.Action do
  use Jido.Action,
    name: "agent_authoring_action",
    schema: Jido.Joi.object(%{value: Jido.Joi.string()})

  def run(_, _), do: raise("authoring must not run Actions")
end

defmodule Jido.Test.Agent.Authoring.Flow do
  use Jido.Flow,
    name: "agent_authoring_flow",
    schema: Jido.Joi.object(%{value: Jido.Joi.string()})

  flow do
    step "work", action: Jido.Test.Agent.Authoring.Action, params: %{value: input(:value)}
    output result("work")
  end
end

defmodule Jido.Test.Agent.Authoring.Worker do
  use Jido.Agent, name: "worker"

  state do
    schema Jido.Joi.object(%{value: Jido.Joi.string() |> Jido.Joi.default("")})
  end

  routes do
    route "work.request", Jido.Test.Agent.Authoring.Action
  end
end

defmodule Jido.Test.Agent.Authoring.Audit do
  alias Jido.Agent.Schema
  alias Spark.Dsl.Extension, as: SparkExtension

  @section %Spark.Dsl.Section{name: :audit, schema: [label: [type: :string, required: true]]}
  use Jido.Plugin, id: "test.audit", sections: [@section]

  def lower(dsl, config) do
    label = SparkExtension.get_opt(dsl, [:audit], :label)
    if label, do: {:ok, Map.put(config, :label, label)}, else: {:ok, config}
  end

  def normalize(data) do
    with {:ok, data} <- Schema.fields(data, [:label, :enabled], %{enabled: true}),
         :ok <- Schema.nonempty(data[:label]),
         do: {:ok, data}
  end
end

defmodule Jido.Test.Agent.Authoring.Minimal do
  use Jido.Agent, name: "minimal"
end
