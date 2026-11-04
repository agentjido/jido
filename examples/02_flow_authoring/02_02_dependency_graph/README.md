# Dependency Graph

Result references create data dependencies. `needs` creates a control
dependency. The expected graph has independent `load` and `audit` roots,
`charge` after `load`, and `save` after both `charge` and `audit`.

Read [`dependency_graph.ex`](dependency_graph.ex) and run its paired offline
test.
