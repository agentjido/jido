# Reduce

Reduce updates one accumulator in collection order. Exec compiles the complete
Reduce to one `Jido.Exec.Node.Reduce`, and the node runs its Action serially.

See [the ExUnit proof](reduce_test.exs).
