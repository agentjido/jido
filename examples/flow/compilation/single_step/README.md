# Single Step

`Jido.Flow.new!/1` converts one data-authored Step to one canonical component.
The expected dependency data is `%{"echo" => %{needs: [], references: [], effective: []}}`.
Validation rejects the same definition without an explicit output.

Read [`single_step.ex`](single_step.ex) and run its paired offline test.
