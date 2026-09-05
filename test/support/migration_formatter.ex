defmodule JidoTest.MigrationFormatter do
  @moduledoc false
  use GenServer

  def init(_opts), do: {:ok, []}

  def handle_cast({:test_finished, test}, tests) do
    status =
      case test.state do
        nil -> "passed"
        {kind, _detail} -> Atom.to_string(kind)
      end

    row = %{
      file: Path.relative_to_cwd(test.tags.file),
      module: inspect(test.module),
      name: Atom.to_string(test.name),
      line: test.tags.line,
      status: status,
      time_us: test.time,
      failure: if(status in ["failed", "invalid"], do: inspect(test.state, limit: :infinity))
    }

    {:noreply, [row | tests]}
  end

  def handle_cast({:suite_finished, times}, tests) do
    if path = System.get_env("JIDO_MIGRATION_RESULTS") do
      File.write!(path, Jason.encode!(%{tests: Enum.reverse(tests), times: times}) <> "\n", [
        :append
      ])
    end

    {:noreply, []}
  end

  def handle_cast(_event, tests), do: {:noreply, tests}
end
