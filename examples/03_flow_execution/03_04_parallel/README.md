# Parallel

Parallel Actions can run with bounded concurrency, but declaration order still
defines result order. Exec compiles the complete block to one
`Jido.Exec.Node.Parallel`.
