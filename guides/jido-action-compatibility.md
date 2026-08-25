# `jido_action` Version Compatibility

Jido 2.x uses `jido_action` 2.x by default. An application can explicitly use
`jido_action` 3.x. This choice is opt-in because version 3 changes public Action,
Instruction, and execution APIs.

## Support Policy

| Jido version | Default `jido_action` version | Support state |
| --- | --- | --- |
| Jido 2.x | `~> 2.3` | Stable default |
| Jido 2.x | `~> 3.0.0-beta.1` | Explicit application override |
| Planned Jido 3.x | 3.x | Version 2 support will be removed |

Jido 2.x does not use an open dependency range that selects either major
version. Thus, an existing application does not get version 3 after a normal
dependency update.

## Opt In To Version 3

Version 3 requires Elixir 1.20 or later. Add a direct dependency with
`override: true` in the application that uses Jido:

```elixir
defp deps do
  [
    {:jido, "~> 2.3"},
    {:jido_action, "~> 3.0.0-beta.1", override: true}
  ]
end
```

Update the lock file and force Jido to compile against the selected version:

```bash
mix deps.unlock jido_action
mix deps.get
mix deps.clean jido --build
mix compile
```

Commit the lock file. Test this dependency choice in CI. Do not use the version
3 override until all application-owned Actions compile with version 3.

To return to version 2, remove the direct `jido_action` dependency. Then run the
same commands.

## Conditional Compilation

Jido detects the installed `jido_action` API when Jido compiles. It compiles
one internal adapter for that version. The adapter covers these Jido paths:

- Action discovery;
- Agent instruction construction and normalization;
- Action execution in built-in strategies; and
- supported execution options and instance routing.

This is a compile-time choice. It is not an application setting and it cannot
change while the node runs. If the lock file changes between major versions,
compile Jido again.

You can check the compiled version:

```elixir
Jido.Agent.Instruction.jido_action_version()
# => 2 or 3
```

## Stable Jido Agent Inputs

Use the Jido Agent command forms when possible. They work with both versions:

```elixir
MyAgent.cmd(agent, MyAction)
MyAgent.cmd(agent, {MyAction, %{value: 42}})
MyAgent.cmd(agent, {MyAction, %{value: 42}, %{tenant_id: "acme"}})
```

If you need an Instruction value, use the Jido compatibility constructor:

```elixir
{:ok, instruction} =
  Jido.Agent.Instruction.new(
    MyAction,
    %{value: 42},
    %{tenant_id: "acme"},
    timeout: 5_000
  )
```

Do not construct `%Jido.Instruction{}` directly in code that must support both
versions. Its fields are different in each major version.

Custom Agent strategies must also use `Jido.Agent.Instruction` to read and run
instructions:

```elixir
alias Jido.Agent.Instruction, as: AgentInstruction
alias Jido.Observe.Config, as: ObserveConfig

# Inside a strategy cmd/3 callback, ctx is the strategy context.
action = AgentInstruction.action(instruction)

opts =
  ObserveConfig.action_exec_opts(
    ctx[:jido_instance],
    AgentInstruction.exec_opts(instruction)
  )

case AgentInstruction.run(instruction, opts) do
  {:ok, result} -> {:ok, action, result}
  {:error, reason} -> {:error, action, reason}
end
```

## Critical Version 3 Changes

The Jido adapter does not restore features that `jido_action` 3.x removed. An
application that selects version 3 must make these changes in its own code:

| Area | Version 2 | Version 3 |
| --- | --- | --- |
| Elixir | Jido 2.x supports Elixir 1.18 and later | Elixir 1.20 or later |
| Action schema | NimbleOptions or Zoi | Map-shaped Zoi schema, or `[]` |
| Action options | Metadata and compensation options are available | Only `name`, `description`, `schema`, and `output_schema` |
| Action hooks | Validation, result, and error hooks are available | These hooks are removed |
| Instruction | `action`, `id`, and `opts` fields | `target` and `metadata`; pass options to `Jido.Exec.run/4` |
| Timeout | 30-second default | `:infinity` default |
| Retry policy | Automatic retry and backoff | The caller owns retry and backoff |
| Compensation | Action compensation is available | The caller owns rollback policy |
| Async execution | `run_async/4`, `await/2`, and `cancel/1` | These functions are removed |
| Per-call logs and telemetry | `log_level` and `telemetry` options | These options are removed |
| Action metadata and tools | Generated metadata and tool functions | These functions are removed |

Set an explicit `timeout` when version 3 must have a deadline. Remove unsupported
execution options such as `max_retries`, `backoff`, `log_level`, and
`telemetry` from direct `Jido.Exec` calls.

Jido-owned Actions use Zoi schemas that work with both supported versions.
Application-owned Actions are outside the adapter. Migrate those Actions before
you enable the override.

For the full Action and Flow migration, see the
[`jido_action` v3 migration guide](https://jido-action.hexdocs.pm/3.0.0-beta.1/v3-migration.html).
