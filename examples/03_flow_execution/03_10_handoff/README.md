# Handoff

Handoff selects a successor Instruction and stops the current Flow. Exec
compiles it to one terminal `Jido.Exec.Node.Handoff`. The caller decides when
and where to run the successor.

See [the ExUnit proof](handoff_test.exs).
