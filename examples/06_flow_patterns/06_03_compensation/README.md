# Compensation

An explicit business rejection routes through one idempotent release Action.
The managed example stops after reservation and resumes without reserving
twice. Automatic compensation after an execution failure remains undefined.

See [the ExUnit proof](compensation_test.exs).
