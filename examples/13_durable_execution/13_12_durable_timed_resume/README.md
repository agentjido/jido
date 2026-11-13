# 13_12 Timed Resume

`Jido.Durable.Status.next_wake_at` is a UTC Unix time in milliseconds. A host
schedules a callback for that time and calls `Jido.Durable.resume/3`.

The durable layer saves the timer state. It does not own a timer process.

See [the ExUnit proof](timed_resume_test.exs).
