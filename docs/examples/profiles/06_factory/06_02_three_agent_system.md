# Three-Agent System

Feature ID: `06_02_three_agent_system`. Status: implemented within the tested scope.

A System Agent owns a conversation Agent and a factory manager. The manager
checks a FIFO queue each second and starts one temporary worker Agent per item,
with at most one worker active. Workers perform three timed demonstration steps.
ReqLLM tools send commands and read queue, worker, job, scheduler, and event data.
The factory sends result Signals through
the owner to the conversation. Model work runs in an owned task after commit,
so events can arrive while the model is busy. IEx prints answers and events.
Tests cover queue order, capacity, control, stale progress, worker failure,
completion, and shutdown. The live OpenAI workshop probe passed.
Chat sessions stream text while factory events remain available. Tool arguments
are complete before execution. The final answer is not printed a second time.
Requests such as `add 3 jobs to the factory` use a batch tool with numbered demo
goals and distinct IDs. Zoi validates inputs before a command reaches the factory.
Batch retries return the same IDs. Invalid goals or insufficient space reject
the whole batch.

[Source](../../../../lib/examples/06_factory/06_02_three_agent_system/system.ex) ·
[Tests](../../../../test/examples/06_factory/06_02_three_agent_system/system_test.exs) ·
[Worker tests](../../../../test/examples/06_factory/06_02_three_agent_system/workshop_test.exs) ·
[Batch tests](../../../../test/examples/06_factory/06_02_three_agent_system/batch_test.exs) ·
[Live probe](../../../../lib/examples/06_factory/workshop_probe.exs) ·
[Run guide](../../../../lib/examples/06_factory/README.md)
