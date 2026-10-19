# 09_10 Plugins add Agent DSL structure

A Plugin can add a domain language to an Agent. This lesson adds named count
thresholds. The same Plugin validates the declaration and owns the reached
threshold state.

## What you will learn

- Add a Spark section and a named entity through `use Jido.Plugin`.
- Use `extensions: [Thresholds]` to import the `thresholds` section into an Agent.
- Lower DSL syntax to one portable, versioned contribution in `Agent.extensions`.
- Apply the same normalization and route checks to DSL, Map, and JSON input.
- Reduce only the Plugin-owned field after an Action returns a complete candidate.

## Read the code

Start with [the Agent](plugin_dsl.ex). Its declarations are the main extension
point:

```elixir
thresholds do
  on "examples.plugins.dsl.add"
  threshold :first, at: 1
  threshold :third, at: 3
end
```

Read [the Plugin and entity](thresholds.ex) next. The Spark section defines the
syntax. `lower/2` converts it to `%{on: type, thresholds: entries}`.
`normalize/1` checks positive bounds and unique names. `verify/2` checks the
route. `state_spec/1` and `reduce/2` add the behavior. One Plugin supplies all
of these parts; no Agent compiler change is required.

The Agent's `registry/0` gives installed code and known atoms stable names for
JSON. The [tests](../../../test/examples/09_plugins/09_10_plugin_dsl/plugin_dsl_test.exs)
show the DSL data, direct and live commands, Map validation, and JSON import.

## Run it

```sh
mix test test/examples/09_plugins/09_10_plugin_dsl --include example --seed 0
```

Expected result: adding three reaches `:first` and `:third` once. Direct and
live commands agree. Imported JSON starts the same Plugin. Invalid bounds,
missing routes, and untrusted references fail before execution.

## Important behavior

Custom syntax is an authoring interface. Stored documents contain validated
data and trusted references. They do not contain source code. Plugin callbacks
receive the same data as keyword options after import. An Agent must import
the provider to use its syntax, but Map and JSON authors supply the contribution
directly. A provider can add syntax without runtime callbacks; this Plugin also
adds state behavior.

## Limits

This Plugin expects domain state to have an integer `count`. Thresholds record
whether a value was reached; decreasing the count does not remove that record.
The example has no external effects. JSON requires the Plugin, Agent, schema,
and generated Action code to be installed. It cannot install code or define
new atoms.

## Files

- [Agent and trusted Registry](plugin_dsl.ex)
- [Plugin, section, and entity](thresholds.ex)
- [Tests](../../../test/examples/09_plugins/09_10_plugin_dsl/plugin_dsl_test.exs)

Previous: [State Middleware](../09_06_state_middleware/README.md) |
Next: [Composition](../09_05_composition/README.md)
