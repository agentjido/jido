# Live Conversation

Feature ID: `06_01_live_conversation`. Status: implemented within the tested scope.

One Agent calls ReqLLM directly and stores text history across turns. Tests
exercise real provider request encoding and response decoding with local HTTP
responses. Duplicates start no model request; errors preserve committed history.
A live provider key is required for the interactive demo. The local Anthropic
key returned HTTP 401. The OpenAI key succeeded with `openai:gpt-4.1-mini`
through the chat launcher. Errors show the provider message and key setting
without the key value.

Chat sessions stream text before completion and save only the complete answer.
Local SSE tests cover early output, interrupted streams, and HTTP cleanup.

[Source](../../../../examples/06_factory/06_01_live_conversation/conversation.ex) ·
[Tests](../../../../test/examples/06_factory/06_01_live_conversation/conversation_test.exs) ·
[Run guide](../../../../examples/06_factory/README.md)
