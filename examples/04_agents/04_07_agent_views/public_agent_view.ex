defmodule Jido.Examples.PublicAgentView.UpdateTitle do
  @moduledoc "A named operation that can appear in a public Agent view."

  use Jido.Action,
    id: "examples/agent-view/update-title",
    name: "agent_view_update_title",
    schema: Jido.Joi.object(%{title: Jido.Joi.string()})

  @impl true
  def run(%{title: title}, %{agent_state: state}), do: {:ok, %{state | title: title}}
end

defmodule Jido.Examples.PublicAgentView.Agent do
  @moduledoc "An Agent with private state, metadata, and route defaults."

  use Jido.Agent,
    id: "examples/agent-view/agent",
    name: "public_agent_view",
    description: "Updates one public title",
    metadata: %{internal_owner: "operations"}

  state do
    schema Jido.Joi.object(%{title: Jido.Joi.string() |> Jido.Joi.default("private")})
  end

  routes do
    route "examples.agent_view.update",
          Jido.Examples.PublicAgentView.UpdateTitle,
          as: :update_title,
          defaults: %{title: "private-default"}
  end
end

defmodule Jido.Examples.PublicAgentView do
  @moduledoc "Builds a JSON-safe framework-neutral Agent description."

  alias Jido.Catalog
  alias Jido.Examples.PublicAgentView.{Agent, UpdateTitle}

  def catalog do
    Catalog.from_targets!(__MODULE__, :jido, %{
      {"examples/agent-view/agent", 1} => Agent,
      {"examples/agent-view/schema", 1} => Agent.definition().schema,
      {"examples/agent-view/update-title", 1} => UpdateTitle,
      {"examples/agent-view/atoms/update-title", 1} => :update_title
    })
  end

  def project(source, opts \\ []), do: Jido.Agent.View.project(source, catalog(), opts)
end
