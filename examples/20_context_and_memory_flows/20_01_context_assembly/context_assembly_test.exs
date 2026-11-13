Code.require_file("context_assembly.ex", __DIR__)

defmodule Jido.Examples.ContextMemory.ContextAssemblyTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.ContextMemory.ContextAssembly

  @input %{
    instructions: "Answer with a source.",
    request: "How long do we retain reports?",
    agent: %{name: "policy-agent", plan: "Use the current policy resource."},
    session: %{summary: "The user asks about report retention."},
    resource: %{title: "Retention policy", excerpt: "Reports are retained for 30 days."},
    tenant: %{policy: "Do not expose another tenant's data."},
    cache_observation: %{provider: "offline", hit: false}
  }

  test "projects six owned layers in a stable order" do
    assert {:ok, result} = Jido.Exec.run(ContextAssembly, @input)

    assert result.stage == :prepared
    assert result.message_count == 6

    assert Enum.map(result.messages, & &1.source) == [
             :static_instructions,
             :tenant_policy,
             :agent_state,
             :session,
             :resource,
             :request
           ]

    assert List.last(result.messages).role == :user
    assert result.cache_observation == %{provider: "offline", hit: false}
  end

  test "the projection is idempotent for the same recorded layers" do
    assert {:ok, first} = Jido.Exec.run(ContextAssembly, @input)
    assert {:ok, second} = Jido.Exec.run(ContextAssembly, @input)
    assert first == second
  end
end
