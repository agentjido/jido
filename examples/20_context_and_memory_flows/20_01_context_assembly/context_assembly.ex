defmodule Jido.Examples.ContextMemory.ContextAssembly.Project do
  use Jido.Action, name: "example_context_assembly_project"

  @impl true
  def run(params, _context) do
    messages = [
      message(:system, params.instructions, :static_instructions),
      message(:system, params.tenant.policy, :tenant_policy),
      message(:system, "Agent #{params.agent.name} plan: #{params.agent.plan}", :agent_state),
      message(:system, "Session summary: #{params.session.summary}", :session),
      message(:system, "Resource #{params.resource.title}: #{params.resource.excerpt}", :resource),
      message(:user, params.request, :request)
    ]

    digest =
      messages
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    {:ok,
     %{
       stage: :prepared,
       messages: messages,
       message_count: length(messages),
       byte_count: Enum.sum(Enum.map(messages, &byte_size(&1.content))),
       digest: digest,
       cache_observation: params.cache_observation,
       provenance: Enum.map(messages, &Map.take(&1, [:source, :owner]))
     }}
  end

  defp message(role, content, source) do
    %{role: role, content: content, source: source, owner: owner(source)}
  end

  defp owner(:static_instructions), do: :application
  defp owner(:tenant_policy), do: :tenant
  defp owner(:agent_state), do: :agent
  defp owner(:session), do: :session
  defp owner(:resource), do: :resource
  defp owner(:request), do: :caller
end

defmodule Jido.Examples.ContextMemory.ContextAssembly do
  alias Jido.Joi

  use Jido.Flow,
    name: "example_context_assembly",
    schema:
      Joi.object(%{
        instructions: Joi.string() |> Joi.min(1),
        request: Joi.string() |> Joi.min(1),
        agent:
          Joi.object(%{
            name: Joi.string() |> Joi.min(1),
            plan: Joi.string() |> Joi.min(1)
          }),
        session: Joi.object(%{summary: Joi.string()}),
        resource:
          Joi.object(%{
            title: Joi.string() |> Joi.min(1),
            excerpt: Joi.string()
          }),
        tenant: Joi.object(%{policy: Joi.string()}),
        cache_observation: Joi.map()
      })

  flow do
    step "project",
      action: Jido.Examples.ContextMemory.ContextAssembly.Project,
      params: %{
        instructions: input(:instructions),
        request: input(:request),
        agent: input(:agent),
        session: input(:session),
        resource: input(:resource),
        tenant: input(:tenant),
        cache_observation: input(:cache_observation)
      }

    output result("project")
  end
end
