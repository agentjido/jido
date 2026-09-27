defmodule JidoTest.System.MigrationAgent.State do
  @moduledoc false
  @behaviour Jido.Plugin
  def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(0)}
end

defmodule JidoTest.System.MigrationAgent.Persistence do
  @moduledoc false
  @behaviour Jido.Plugin
  def dump(value, _context, _opts), do: {:ok, %{format: 1, value: value}}
  def load(%{format: 1, value: value}, _context, _opts), do: {:ok, value}
  def load(_value, _context, _opts), do: {:error, :unsupported_plugin_format}
end

defmodule JidoTest.System.MigrationAgent.Plugin do
  @moduledoc false
  use Jido.Plugin

  @impl true
  defdelegate state_spec(opts), to: JidoTest.System.MigrationAgent.State

  @impl true
  defdelegate dump(value, context, opts), to: JidoTest.System.MigrationAgent.Persistence

  @impl true
  defdelegate load(value, context, opts), to: JidoTest.System.MigrationAgent.Persistence
end

defmodule JidoTest.System.MigrationAgent do
  @moduledoc false
  use Jido.Agent, name: "system_migration_agent"

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
    plugin JidoTest.System.MigrationAgent.Plugin
  end

  routes do
    route "system.work", JidoTest.System.ControlledWork
  end
end
