defmodule Jido.Examples.Collaboration.NestedOrganization.Worker do
  use Jido.Agent, name: "example_nested_organization_worker"

  state do
    schema Jido.Joi.object(%{completed: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/collaboration/nested-worker"

    route "examples.organization.work", as: :work do
      action input,
        schema: Jido.Joi.object(%{fail: Jido.Joi.boolean()}),
        context: context do
        if input.fail do
          {:error, Jido.Error.execution_error("injected worker failure")}
        else
          {:ok, %{completed: context.agent_state.completed + 1}}
        end
      end
    end
  end
end

defmodule Jido.Examples.Collaboration.NestedOrganization.Team do
  use Jido.Agent, name: "example_nested_organization_team"

  topology do
    agent :workers, Jido.Examples.Collaboration.NestedOrganization.Worker do
      count 2
    end
  end
end

defmodule Jido.Examples.Collaboration.NestedOrganization.Department do
  use Jido.Agent, name: "example_nested_organization_department"

  topology do
    agent :teams, Jido.Examples.Collaboration.NestedOrganization.Team do
      count 2
    end
  end
end

defmodule Jido.Examples.Collaboration.NestedOrganization.Company do
  use Jido.Agent, name: "example_nested_organization_company"

  topology do
    agent :departments, Jido.Examples.Collaboration.NestedOrganization.Department do
      count 2
    end
  end
end
