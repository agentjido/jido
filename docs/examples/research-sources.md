> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Research source inventory

Access date for all web sources: **2026-09-03**.

The local competitor set comes from the `jido_run` research archive at
`docs/archive/2026-08-30-batch-03/specs/competitors/README.md`. The archive
snapshot is dated 2026-02-20. It lists 11 frameworks. This catalog includes all
11 and adds Akka because it is an important agent-runtime reference.

Only official documentation, official repositories, and current HexDocs pages
support framework claims. Some old URLs now redirect to a new official docs
location. The profile keeps the stable official URL that was checked.

| Framework | Official sources used |
| --- | --- |
| Akka | [Agents](https://doc.akka.io/libraries/akka-core/current/typed/agents.html), [interaction patterns and timers](https://doc.akka.io/libraries/akka-core/current/typed/interaction-patterns.html), [event sourcing](https://doc.akka.io/libraries/akka-core/current/typed/persistence.html), [cluster](https://doc.akka.io/libraries/akka-core/current/typed/cluster.html), [cluster sharding](https://doc.akka.io/libraries/akka-core/current/typed/cluster-sharding.html) |
| AutoGen | [AgentChat tutorial](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/index.html), [examples](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/examples/index.html) |
| LlamaIndex | [agents](https://developers.llamaindex.ai/python/framework/module_guides/deploying/agents/), [ReAct workflow](https://developers.llamaindex.ai/python/examples/workflow/react_agent/) |
| CrewAI | [documentation](https://docs.crewai.com/), [first Flow](https://docs.crewai.com/en/guides/flows/first-flow), [official examples repository](https://github.com/crewAIInc/crewAI-examples) |
| Semantic Kernel | [agent architecture](https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/agent-architecture), [agent orchestration](https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/agent-orchestration/) |
| LangGraph | [workflows and agents](https://docs.langchain.com/oss/python/langgraph/workflows-agents), [Graph API](https://docs.langchain.com/oss/python/langgraph/use-graph-api), [agentic RAG](https://docs.langchain.com/oss/python/langgraph/agentic-rag), [support email agent](https://docs.langchain.com/oss/python/langgraph/thinking-in-langgraph) |
| Haystack | [Agent](https://docs.haystack.deepset.ai/docs/agent), [pipelines](https://docs.haystack.deepset.ai/docs/pipelines), [tutorials](https://haystack.deepset.ai/tutorials) |
| Mastra | [documentation and templates](https://mastra.ai/docs), [multi-agent workflow](https://mastra.ai/en/examples/agents/multi-agent-workflow) |
| Google ADK | [workflow agents](https://adk.dev/agents/workflow-agents/), [multi-agent systems](https://google.github.io/adk-docs/agents/multi-agents/), [streaming](https://google.github.io/adk-docs/get-started/streaming/), [Restate integration](https://google.github.io/adk-docs/integrations/restate/) |
| PydanticAI | [examples index](https://pydantic.dev/docs/ai/examples/setup/), [weather agent](https://pydantic.dev/docs/ai/examples/getting-started/weather-agent/), [durable execution](https://ai.pydantic.dev/durable_execution/), [testing](https://ai.pydantic.dev/testing/) |
| Pi / Pi Agent | [official repository](https://github.com/earendil-works/pi), [agent core](https://github.com/earendil-works/pi/tree/main/packages/agent), [coding agent](https://github.com/earendil-works/pi/tree/main/packages/coding-agent), [extension documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md), [package documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md), [extension examples](https://github.com/earendil-works/pi/tree/main/packages/coding-agent/examples/extensions), [package catalog](https://pi.dev/packages) |
| Sagents | [current package docs](https://sagents.hexdocs.pm/), [human in the loop](https://sagents.hexdocs.pm/Sagents.Middleware.HumanInTheLoop.html), [SubAgent](https://sagents.hexdocs.pm/Sagents.Middleware.SubAgent.html), [official repository](https://github.com/sagents-ai/sagents) |

## Additional architecture sources

| Source | Use |
| --- | --- |
| [A Tree You Can Prove, a Graph You Can Think In](https://volodymyrpavlyshyn.substack.com/p/a-tree-you-can-prove-a-graph-you) | Secondary article that motivates separate proof, analysis, containment, and semantic-memory views. |
| [Causal-Temporal Event Graphs: A Formal Model for Recursive Agent Execution Traces](https://arxiv.org/abs/2604.17557) | Primary paper by Simon Foldvik. It defines single-parent causal trees, recursive trace composition, valid partial traces after failure, and compatibility with Merkle commitments. |

The [Pi package ecosystem review](pi-package-ecosystem.md) records the sampled
packages and the Jido pressure tests that come from them.

## Local sources

The status review also used these repository sources:

The current checkout contains the implementation and test paths for `counter`,
`react_agent`, and `scheduled_counter`. Their profiles link to these local
files.

- [`examples/08_applications/README.md`](../../examples/08_applications/README.md) for current
  implemented examples and their open work.
- [`Jido.Agent.Directive`](../../lib/jido/agent/directive.ex) for built-in
  runtime commands.
- [`Jido.Plugin.Scheduler`](../../lib/jido/plugin/scheduler.ex) for delayed and
  recurring Signals.

## Citation method

Each profile links to the source example or the closest official source. When
several frameworks show the same use case, the catalog has one normalized
profile and cites all sources. The catalog does not copy framework code or
framework-specific names into the proposed Jido API.
