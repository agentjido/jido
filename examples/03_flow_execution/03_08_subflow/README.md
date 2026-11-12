# Subflow

A Step can call another Flow. Exec compiles the parent Step to one
`Jido.Exec.Node.Subflow`. The child Runic workflow stays inside that node.

See [the ExUnit proof](subflow_test.exs).
