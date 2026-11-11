# Wait and Signal

A Selection compiles to one `Jido.Exec.Node.Wait`. Immediate `Jido.Exec.run/4`
rejects a Flow that can wait. A host starts the compiled workflow, stores its
state, and uses an addressed Signal or a timer to resume it.
