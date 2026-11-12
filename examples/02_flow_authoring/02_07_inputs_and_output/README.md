# Inputs and Output

Flow and Action schemas validate separate boundaries. Valid input
`%{left: 2, right: 3}` returns exactly `%{answer: 5}`. Invalid input fails
before Action work starts.

Read [`inputs_and_output.ex`](inputs_and_output.ex) and run its paired offline
test.

See [the ExUnit proof](inputs_and_output_test.exs).
