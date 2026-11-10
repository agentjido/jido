# Controlled Execution

Immediate execution and direct Runic stepwise execution return the same
two-branch output. The paired test compiles the Flow with `Jido.Exec.compile/2`
and uses `Runic.Runner` for the low-level execution controls.
