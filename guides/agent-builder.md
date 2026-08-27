# Agent Builder

Use `Jido.Agent.Builder` when Agent author data arrives in steps or from runtime
configuration. The result is the same inert `%Jido.Agent{}` definition that
`Jido.Agent.new!/1` and the module DSL make.

```elixir
definition =
  Jido.Agent.Builder.new("report_agent")
  |> Jido.Agent.Builder.description("Builds reports")
  |> Jido.Agent.Builder.state_schema(MyApp.AgentSchemas.report_state())
  |> Jido.Agent.Builder.plugin_defaults(:none)
  |> Jido.Agent.Builder.plugin(MyApp.ReportPlugin,
    as: :primary,
    config: %{format: "pdf"}
  )
  |> Jido.Agent.Builder.route("report.requested", MyApp.BuildReport,
    params: %{source: "builder"},
    priority: 10
  )
  |> Jido.Agent.Builder.schedule(
    "daily_report",
    "0 9 * * *",
    "report.requested",
    data: %{period: "daily"},
    timezone: "Etc/UTC"
  )
  |> Jido.Agent.Builder.metadata(%{owner: "analytics"})
  |> Jido.Agent.Builder.build!()
```

Use `build/1` when the input can be invalid:

```elixir
case Jido.Agent.Builder.build(builder) do
  {:ok, definition} -> use_definition(definition)
  {:error, error} -> report_error(error)
end
```

The Builder accepts definition fields only. It rejects `id`, `state`,
`agent_module`, and strategy data. Build the definition first. Then make an
instance at the explicit runtime boundary:

```elixir
{:ok, instance} =
  Jido.Agent.instantiate(definition,
    id: "report-1",
    state: %{last_report: nil}
  )
```

The Builder does not read host configuration, mount a plugin, run Agent work,
or start a process.

For schema refinements and transforms, use static named MFA callbacks. Do not
use anonymous functions or closures.
