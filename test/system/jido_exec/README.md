# Action and Flow system verification

Run `mix test.system test/system/jido_exec` from the package root. The suite validates one two-Action Flow
and runs the same input through its compiled Flow value, Flow module, and Instruction forms. Each form must return the
same result and release its temporary supervised execution task.

External services, distributed storage, and multiple BEAM nodes are outside this suite.
