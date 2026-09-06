defmodule JidoTest.MigrationFormatterTest do
  use JidoTest.Case, async: false

  test "records ordered test results and appends one JSON record per suite" do
    previous = System.get_env("JIDO_MIGRATION_RESULTS")
    path = Path.join(System.tmp_dir!(), unique_id("migration-results"))
    System.put_env("JIDO_MIGRATION_RESULTS", path)

    on_exit(fn ->
      if previous,
        do: System.put_env("JIDO_MIGRATION_RESULTS", previous),
        else: System.delete_env("JIDO_MIGRATION_RESULTS")

      File.rm(path)
    end)

    formatter =
      start_supervised!(%{
        id: :formatter,
        start: {GenServer, :start_link, [JidoTest.MigrationFormatter, []]}
      })

    GenServer.cast(formatter, {:suite_started, %{}})

    for {name, state} <- [
          {:"test passes", nil},
          {:"test fails", {:failed, [:assertion]}},
          {:"test skipped", {:skipped, "known gap"}}
        ] do
      test = %ExUnit.Test{
        name: name,
        module: __MODULE__,
        state: state,
        time: 15,
        tags: %{file: __ENV__.file, line: 1}
      }

      GenServer.cast(formatter, {:test_finished, test})
    end

    GenServer.cast(formatter, {:suite_finished, %{run: 45}})
    assert :sys.get_state(formatter) == []
    record = path |> File.read!() |> Jason.decode!()
    assert Enum.map(record["tests"], & &1["status"]) == ["passed", "failed", "skipped"]

    assert Enum.map(record["tests"], & &1["name"]) == [
             "test passes",
             "test fails",
             "test skipped"
           ]

    assert Enum.at(record["tests"], 1)["failure"] =~ "assertion"
    assert hd(record["tests"])["failure"] == nil
    assert record["times"] == %{"run" => 45}

    GenServer.cast(formatter, {:suite_finished, %{run: 0}})
    assert :sys.get_state(formatter) == []
    assert length(String.split(File.read!(path), "\n", trim: true)) == 2
    System.delete_env("JIDO_MIGRATION_RESULTS")
    GenServer.cast(formatter, {:suite_finished, %{run: 0}})
    assert :sys.get_state(formatter) == []
    assert length(String.split(File.read!(path), "\n", trim: true)) == 2
  end
end
