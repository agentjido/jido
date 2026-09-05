# Flow Factory

Feature ID: `06_04_flow_factory`.

A Mission Agent owns nine department Agents. A Plugin runs a Jido Flow after
commit. The Flow joins parallel research and design, maps work to API, UI, and
Test workers, integrates their artifacts, and joins Quality and optional Security
reviews. Iterate allows two repairs. Handoff receives the accepted revision.

The local mode needs no key. Live mode uses ReqLLM and Dotenvy. Both modes
produce proposal artifacts. The example includes inspection, cancellation,
worker cleanup, attempt identity, and a complete execution deadline. It does
not modify repositories or persist an active Flow execution.

[Guide and source](../../../../lib/examples/06_factory/06_04_flow_factory/README.md)
· [Tests](../../../../test/examples/06_factory/06_04_flow_factory/flow_factory_test.exs)
· [Results](../../flow-factory-results.md)
