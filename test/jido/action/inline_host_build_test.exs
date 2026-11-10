defmodule Jido.Action.InlineHostBuildTest do
  use ExUnit.Case, async: false

  alias Jido.Test.Action.InlineBuild, as: Build

  @moduletag :tmp_dir
  @moduletag timeout: 180_000

  setup context do
    fixture = Build.setup(context)
    on_exit(fn -> File.rm_rf!(context.tmp_dir) end)
    {:ok, fixture: fixture}
  end

  test "a clean release loads inline Actions and Flows with source removed", %{
    fixture: fixture
  } do
    {output, status} = Build.mix(fixture, ["release"])
    assert status == 0, "inline release exited with status #{status}:\n#{output}"
    beams = Build.beams(fixture)
    assert length(beams) == 10
    assert Enum.count(beams, &String.starts_with?(&1, "Elixir.Jido.Flow.Generated.Inline.")) == 1

    # The package remains in the isolated build directory. Remove the full
    # consumer project, including its source variants and Mix file.
    File.rm_rf!(fixture.app)
    File.mkdir!(fixture.app)
    result = Build.release_probe(fixture)
    assert_probe(result, beams)
    assert Map.keys(result["roles"]["targets"]) == ["finish", "step"]
    assert Map.keys(result["steps"]["targets"]) == ["first", "second"]
  end

  test "ordinary compilation rejects an Action without run/2", %{fixture: fixture} do
    Build.replace(fixture, "missing_action.ex", "missing_action.ex")
    {output, status} = Build.mix(fixture, ["compile"])
    assert status != 0
    assert output =~ "run/2"
    assert output =~ "implementation not provided"
  end

  test "body macro edits rebuild unchanged owners and recover after failed compilation", %{
    fixture: fixture
  } do
    Build.compile!(fixture)
    refute Build.compile!(fixture) =~ "Compiling"
    initial = Build.probe(fixture)
    beams = Build.beams(fixture)
    assert_probe(initial, beams)

    owners =
      for name <- ["roles", "steps"], into: %{} do
        path = Path.join([fixture.app, "lib", name <> ".ex"])
        {path, {File.read!(path), File.stat!(path, time: :posix).mtime}}
      end

    owner_beam = Path.join(Build.ebin(fixture), "Elixir.InlineConsumer.Roles.beam")
    initial_beam = File.read!(owner_beam)

    Build.replace(fixture, "body_macro_changed.ex", "body_macro.ex")
    assert Build.compile!(fixture) =~ "Compiling"

    for {path, {source, mtime}} <- owners do
      assert File.read!(path) == source
      assert File.stat!(path, time: :posix).mtime == mtime
    end

    refute File.read!(owner_beam) == initial_beam
    changed = Build.probe(fixture)
    assert_probe(changed, beams, :changed_macro)
    assert Map.drop(changed, ["results"]) == Map.drop(initial, ["results"])
    assert Build.beams(fixture) == beams

    Build.replace(fixture, "body_macro_invalid.ex", "body_macro.ex")
    {output, status} = Build.mix(fixture, ["compile", "--warnings-as-errors"])
    assert status != 0
    assert output =~ "missing_inline_body_function"

    Build.replace(fixture, "body_macro_changed.ex", "body_macro.ex")
    Build.compile!(fixture)
    assert Build.probe(fixture) == changed
    assert Build.beams(fixture) == beams
  end

  test "Step syntax changes preserve identity and renamed Steps remove stale artifacts", %{
    fixture: fixture
  } do
    Build.compile!(fixture)
    initial = Build.probe(fixture)
    beams = Build.beams(fixture)
    assert_probe(initial, beams)

    Build.replace(fixture, "steps_nested.ex", "steps.ex")
    Build.compile!(fixture)
    assert Build.probe(fixture) == initial
    assert Build.beams(fixture) == beams

    Build.replace(fixture, "steps_reduced.ex", "steps.ex")
    Build.compile!(fixture)
    changed = Build.probe(fixture)
    assert changed["roles"] == initial["roles"]
    assert Map.keys(changed["steps"]["targets"]) == ["renamed"]
    assert changed["results"] == put_in(initial["results"], ["steps", "value"], 3)
    assert changed["missing_steps"] == %{"first" => true, "second" => true}
    assert_probe_artifacts(changed, Build.beams(fixture))

    assert beams -- Build.beams(fixture) ==
             target_beams(initial["steps"]["targets"], ["first", "second"])

    assert Build.beams(fixture) -- beams == target_beams(changed["steps"]["targets"], ["renamed"])
  end

  defp assert_probe(result, beams, version \\ :original) do
    assert_probe_artifacts(result, beams)
    assert result["missing_steps"] == %{"renamed" => true}

    {direct, role, roles, steps} =
      case version do
        :original -> {3, 7, 8, 6}
        :changed_macro -> {102, 106, 206, 204}
      end

    assert result["results"] == %{
             "direct" => %{"action" => %{"value" => direct}, "flow" => %{"value" => 12}},
             "host" => %{
               "bound" => %{"message" => "bound:[7]"},
               "callback" => %{"message" => "default:[4]"},
               "late_first" => %{"message" => "late:[6]"},
               "late_second" => %{"message" => "late:[7]"}
             },
             "validation" => true,
             "roles" => %{"value" => roles},
             "role_actions" => %{"step" => %{"value" => role}, "finish" => %{"value" => role}},
             "steps" => %{"value" => steps},
             "embedded" => %{"value" => 12}
           }
  end

  defp assert_probe_artifacts(result, beams) do
    assert result["artifacts"] == Enum.map(beams, &%{"file" => &1, "local" => true})
    assert result["owners_unloaded"] == [true, true, true]
    assert result["catalog"] == [true, true]
    assert result["lookups"] == List.duplicate(true, length(beams))
  end

  defp target_beams(targets, names),
    do: names |> Enum.map(&(targets[&1] <> ".beam")) |> Enum.sort()
end
