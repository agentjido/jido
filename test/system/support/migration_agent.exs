defmodule JidoTest.System.MigrationAgent.State do
  @moduledoc false
  use Jido.Agent.Plugin
  def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(0)}
end

defmodule JidoTest.System.MigrationAgent.Persistence do
  @moduledoc false
  use Jido.Persistence.Plugin
  def dump(value, _context, _opts), do: {:ok, %{format: 1, value: value}}
  def load(%{format: 1, value: value}, _context, _opts), do: {:ok, value}
  def load(_value, _context, _opts), do: {:error, :unsupported_plugin_format}
end

defmodule JidoTest.System.MigrationAgent.Plugin do
  @moduledoc false
  use Jido.Plugin,
    agent: JidoTest.System.MigrationAgent.State,
    persistence: JidoTest.System.MigrationAgent.Persistence
end

defmodule JidoTest.System.MigrationAgent do
  @moduledoc false
  use Jido.Agent,
    name: "system_migration_agent",
    schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)}),
    plugins: [JidoTest.System.MigrationAgent.Plugin],
    routes: [{"system.work", JidoTest.System.ControlledWork}]
end
