# Discover Actions

`Jido.Discovery` gives you a read-only catalog of available Action modules.
Jido builds this catalog in a temporary Task during startup. Startup does not
wait for the scan. Use `Jido.Discovery.ready?/0` when your code must know if the
first scan is complete.

By default, Discovery scans the module lists of all loaded applications. You
can use an application allowlist and you can add explicit modules:

```elixir
config :jido, Jido.Discovery,
  applications: [:my_app, :jido_connect_github],
  modules: [MyApp.SpecialAction]
```

Use the catalog through its public API:

```elixir
Jido.Discovery.list_actions(name: "email")
Jido.Discovery.get_action(MyApp.SendEmail)
Jido.Discovery.get_action_by_slug("Ykp9FX0tyhYB_4Oa")
Jido.Discovery.last_updated()
```

Call `Jido.Discovery.refresh/1` after code loading changes. A successful refresh
replaces the complete catalog. Readers continue to use the old catalog until
the new scan is complete.

Discovery finds inventory. It does not give authority. An application must
keep its own allowlist and assignment data. Do not store catalog slugs as
product identifiers. A slug changes when the module name changes.

Discovery does not scan Agent definitions or Topology definitions. Keep those
module lists explicit. Runtime `Jido.list_agents/0` lists live registered
Agents. It does not list Agent modules.

Use a trusted Codec Registry for module references in stored authoring data.
Decoding strings must not create arbitrary atoms or load arbitrary modules.
