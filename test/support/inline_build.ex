defmodule JidoActionTest.InlineBuild do
  @moduledoc false

  import ExUnit.Assertions

  @fixture Path.expand("../fixtures/inline_consumer", __DIR__)

  def setup(%{tmp_dir: directory}) do
    app = Path.join(directory, "consumer")
    File.cp_r!(@fixture, app)

    # Keep the probe outside the consumer so release tests can delete all source.
    scripts = Path.join(directory, "scripts")
    File.rename!(Path.join(app, "scripts"), scripts)
    for path <- Path.wildcard(Path.join(app, "lib/*.ex")), do: File.touch!(path, 946_684_800)

    paths =
      :code.get_path()
      |> Enum.map(&(&1 |> to_string() |> Path.expand()))
      |> Enum.filter(&(Path.basename(&1) == "ebin" and File.dir?(&1)))

    %{app: app, scripts: scripts, paths: paths, build: Path.join(directory, "build")}
  end

  def replace(fixture, variant, source) do
    destination = Path.join([fixture.app, "lib", source])

    mtime =
      if File.exists?(destination),
        do: File.stat!(destination, time: :posix).mtime + 1,
        else: 946_684_800

    File.cp!(Path.join([fixture.app, "variants", variant]), destination)
    # Advance only the changed source. Same-second edits must trigger Mix.
    File.touch!(destination, mtime)
  end

  def mix(fixture, args) do
    elixir(fixture, ["-e", "Mix.CLI.main(System.argv())", "--" | args])
  end

  def compile!(fixture) do
    {output, status} = mix(fixture, ["compile", "--warnings-as-errors"])
    assert status == 0, "inline compile exited with status #{status}:\n#{output}"
    output
  end

  def probe(fixture, offset \\ 1) do
    fixture
    |> elixir([Path.join(fixture.scripts, "probe.exs")], offset)
    |> result!()
  end

  def release_probe(fixture) do
    release = Path.join(fixture.build, "rel/inline_consumer")

    script =
      "Code.require_file(System.fetch_env!(\"INLINE_GUARD\")); Code.require_file(System.fetch_env!(\"INLINE_PROBE\"))"

    run(
      fixture,
      Path.join(release, "bin/inline_consumer"),
      ["eval", script],
      env(fixture, 1, release)
    )
    |> result!()
  end

  def beams(fixture) do
    fixture
    |> ebin()
    |> Path.join("Elixir.Jido.Action.Generated.Inline.*.beam")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  def ebin(fixture), do: Path.join(fixture.build, "lib/inline_consumer/ebin")

  defp elixir(fixture, args, offset \\ 1) do
    paths = Enum.flat_map([ebin(fixture) | fixture.paths], &["-pa", &1])
    args = paths ++ ["-r", Path.join(fixture.scripts, "guard.exs")] ++ args
    run(fixture, System.find_executable("elixir"), args, env(fixture, offset, ebin(fixture)))
  end

  defp env(fixture, offset, artifacts) do
    [
      {"MIX_ENV", "test"},
      {"MIX_BUILD_PATH", fixture.build},
      {"MIX_DEPS_PATH", nil},
      {"MIX_TARGET", "host"},
      {"ERL_FLAGS", "+S 2:2 +SDcpu 1 +SDio 1"},
      {"ELIXIR_ERL_OPTIONS", nil},
      {"RELEASE_DISTRIBUTION", "none"},
      {"INLINE_OFFSET", Integer.to_string(offset)},
      {"INLINE_ARTIFACT_ROOT", artifacts},
      {"INLINE_GUARD", Path.join(fixture.scripts, "guard.exs")},
      {"INLINE_PROBE", Path.join(fixture.scripts, "probe.exs")}
    ]
    |> Enum.map(fn {key, value} ->
      {String.to_charlist(key), if(value, do: String.to_charlist(value), else: false)}
    end)
  end

  defp run(fixture, executable, args, env) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args,
        cd: fixture.app,
        env: env
      ])

    try do
      collect(port, [], System.monotonic_time(:millisecond) + 40_000)
    after
      if Port.info(port), do: Port.close(port)
    end
  end

  defp collect(port, output, deadline) do
    receive do
      {^port, {:data, data}} ->
        collect(port, [data | output], deadline)

      {^port, {:exit_status, status}} ->
        {output |> Enum.reverse() |> IO.iodata_to_binary(), status}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        # Kill only this still-open port's OS process. The stdin guard also
        # stops the VM if ExUnit terminates the port owner before this deadline.
        {:os_pid, pid} = Port.info(port, :os_pid)
        System.cmd(System.find_executable("kill"), ["-KILL", Integer.to_string(pid)])

        receive do
          {^port, {:exit_status, _status}} -> :ok
        after
          5_000 -> flunk("inline build child did not report exit after SIGKILL")
        end

        flunk("inline build child timed out:\n" <> IO.iodata_to_binary(Enum.reverse(output)))
    end
  end

  defp result!({output, status}) do
    assert status == 0, "inline probe exited with status #{status}:\n#{output}"
    [_, result] = Regex.run(~r/^INLINE_RESULT=(.*)$/m, output)
    JSON.decode!(result)
  end
end
