defmodule Jido.Examples.DefinitionChanges do
  @moduledoc "Builds one trusted complete document for an explicit AgentServer upgrade."

  alias Jido.Catalog

  defmodule IncrementV1 do
    @moduledoc false
    use Jido.Action, name: "runtime_definition_increment_v1"

    @impl true
    def run(_input, context), do: {:ok, %{count: context.agent_state.count + 1}}
  end

  defmodule IncrementV2 do
    @moduledoc false
    use Jido.Action, name: "runtime_definition_increment_v2"

    @impl true
    def run(_input, context), do: {:ok, %{total: context.agent_state.total + 1}}
  end

  defmodule Migrate do
    @moduledoc false
    use Jido.Action,
      name: "runtime_definition_migrate",
      schema: Jido.Joi.object(%{state: Jido.Joi.map()})

    @impl true
    def run(%{state: %{count: count}}, _context), do: {:ok, %{total: count + 10}}
  end

  defmodule V1 do
    @moduledoc "The active version before the upgrade."
    use Jido.Agent, name: "runtime_definition_v1", vsn: 1

    state do
      schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
    end

    routes do
      route "examples.runtime.definition.increment", IncrementV1
    end
  end

  defmodule V2 do
    @moduledoc "The complete replacement definition."
    use Jido.Agent, name: "runtime_definition_v2", vsn: 2

    state do
      schema Jido.Joi.object(%{total: Jido.Joi.integer()})
    end

    routes do
      route "examples.runtime.definition.increment", IncrementV2
    end
  end

  @doc "Returns the trusted Catalog and complete V2 Codec document."
  def upgrade_input do
    definition = V2.definition()

    catalog =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"agents/runtime-definition-v2", 1} => V2,
        {"schemas/runtime-definition-v2", 1} => definition.schema,
        {"actions/runtime-definition-increment-v2", 1} => IncrementV2
      })

    {:ok, document} =
      Jido.Codec.encode(definition, catalog: catalog, codec: Jido.Agent.Codec)

    {document, catalog}
  end

  @doc "Builds the command used before and after the upgrade."
  def increment_signal do
    Jido.Signal.new!("examples.runtime.definition.increment", %{}, source: "/examples")
  end
end
