defmodule Jido.AI.Contract.SkillTest do
  use Covenant.Case, component: "jido_ai.tools", async: true

  alias Jido.AI.{Skill, ToolSource}

  @moduletag obligation: ["jido_ai.tools.I2", "jido_ai.tools.I5", "jido_ai.tools.I6"]

  @tag :tmp_dir
  test "a trusted skill source publishes one lazy load tool", %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "skills")

    write_skill(
      root,
      "code-review",
      "Review code for bugs and missing tests.",
      "Report concrete findings first.\n",
      "license: Apache-2.0\nallowed-tools: shell\n"
    )

    write_skill(
      root,
      "api-design",
      "Design small and stable public APIs.",
      "Keep the public API small.\n"
    )

    File.mkdir_p!(Path.join([root, "code-review", "scripts"]))
    File.write!(Path.join([root, "code-review", "scripts", "check.sh"]), "exit 1\n")
    File.write!(Path.join(root, "README.md"), "not a skill")

    source = Skill.source([root])
    assert source == {Skill, %{roots: [Path.expand(root)]}}

    assert {:ok,
            [
              %{name: "api-design", description: "Design small and stable public APIs."},
              %{name: "code-review", description: "Review code for bugs and missing tests."}
            ]} = Skill.discover([root])

    context = %{jido_ai_tool_sources: [source]}
    assert {:ok, [tool]} = ToolSource.load(context)
    assert tool.name == "load_skill"
    assert tool.description =~ "- api-design: Design small and stable public APIs."
    assert tool.description =~ "- code-review: Review code for bugs and missing tests."
    refute tool.description =~ "check.sh"
    refute tool.description =~ "allowed-tools"

    assert {:ok,
            %{
              name: "code-review",
              description: "Review code for bugs and missing tests.",
              instructions: "Report concrete findings first.\n"
            }} =
             ToolSource.run(
               ToolSource.executor(tool),
               %{id: "skill-1", name: "load_skill", arguments: %{name: "code-review"}},
               context
             )
  end

  @tag :tmp_dir
  test "an empty root does not publish a load tool", %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "skills")
    File.mkdir_p!(root)

    assert {:ok, []} =
             ToolSource.load(%{jido_ai_tool_sources: [Skill.source([root])]})
  end

  @tag :tmp_dir
  test "skill loading resolves only exact discovered names", %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "skills")
    write_skill(root, "safe-skill", "Use trusted instructions.", "Stay within scope.\n")

    assert {:error, {:unknown_skill, "../safe-skill"}} =
             Skill.load([root], "../safe-skill")

    assert {:error, {:unknown_skill, "missing"}} = Skill.load([root], "missing")
  end

  @tag :tmp_dir
  test "discovery rejects invalid files and duplicate names", %{tmp_dir: tmp_dir} do
    invalid_root = Path.join(tmp_dir, "invalid")
    invalid_directory = Path.join(invalid_root, "directory-name")
    File.mkdir_p!(invalid_directory)

    File.write!(
      Path.join(invalid_directory, "SKILL.md"),
      """
      ---
      name: other-name
      description: This metadata has another name.
      ---
      Instructions.
      """
    )

    assert {:error, {:invalid_skill_file, _path, {:name_must_match_directory, "directory-name"}}} =
             Skill.discover([invalid_root])

    first_root = Path.join(tmp_dir, "first")
    second_root = Path.join(tmp_dir, "second")
    write_skill(first_root, "shared", "First copy.", "First.\n")
    write_skill(second_root, "shared", "Second copy.", "Second.\n")

    assert {:error, {:duplicate_skill, "shared"}} =
             Skill.discover([first_root, second_root])
  end

  defp write_skill(root, name, description, instructions, extra_frontmatter \\ "") do
    directory = Path.join(root, name)
    File.mkdir_p!(directory)

    File.write!(
      Path.join(directory, "SKILL.md"),
      "---\nname: #{name}\ndescription: #{description}\n#{extra_frontmatter}---\n#{instructions}"
    )
  end
end
