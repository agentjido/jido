Code.require_file("tool_sources.ex", __DIR__)

defmodule Jido.Examples.AI.SkillsAndToolSourcesTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.AI.{Skill, ToolSource, Toolset}
  alias Jido.Examples.AI.SkillsAndToolSources.OfflineMCPSource

  test "trusted context combines a skill and an offline MCP-shaped source" do
    skill_root = Path.join([__DIR__, "fixtures", "skills"])

    context = %{
      jido_ai_tool_sources: [
        Skill.source([skill_root]),
        {OfflineMCPSource, %{server: "offline-docs"}}
      ]
    }

    assert {:ok, tools} = ToolSource.load(context)
    assert Toolset.names(tools) == ["load_skill", "remote_lookup"]

    load_skill = Enum.find(tools, &(&1.name == "load_skill"))

    assert {:ok, skill} =
             ToolSource.run(
               ToolSource.executor(load_skill),
               %{id: "skill-1", name: "load_skill", arguments: %{name: "focused-review"}},
               context
             )

    assert skill.name == "focused-review"
    assert skill.instructions =~ "Report concrete findings"

    lookup = Enum.find(tools, &(&1.name == "remote_lookup"))

    assert {:ok, %{query: "Agent identity", result: "offline result", server: "offline-docs"}} =
             ToolSource.run(
               ToolSource.executor(lookup),
               %{
                 id: "lookup-1",
                 name: "remote_lookup",
                 arguments: %{query: "Agent identity"}
               },
               context
             )

    assert {:ok, []} =
             ToolSource.load(%{
               request: %{jido_ai_tool_sources: [{OfflineMCPSource, %{server: "untrusted"}}]}
             })
  end
end
