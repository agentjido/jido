# Invoke

Invoke uses a decision Action and an expander Action to select an Action or
Flow at run time. Exec compiles this boundary to one `Jido.Exec.Node.Invoke`.
The dynamic target does not change the parent Runic graph.

See [the ExUnit proof](invoke_test.exs).
