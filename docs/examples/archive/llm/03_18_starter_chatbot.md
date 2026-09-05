> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Starter Chatbot

- **ID:** `03_18_starter_chatbot`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Provide a minimal multi-turn assistant with application-owned message history.
- **User story:** As a user, I send several messages and receive answers that use prior context.
- **Trigger or input:** `chat.message` Signal with text and session metadata.
- **Agent state:** Messages, processed message IDs, conversation settings, last model usage, and turn count.
- **Actions or Flow:** One Action builds model input from Actor history, calls the model adapter, and appends the answer.
- **External interactions:** LLM. A fake model provides deterministic replies.
- **Runtime Directives or capabilities:** An `Emit` can deliver the answer after commit.
- **Expected result:** The user and assistant messages enter Actor state in stable order.
- **Failure cases:** Empty message, context limit, model timeout, invalid response, or duplicate message.
- **Jido features under pressure:** Actor-owned history, context building, model adapter, delivery, and sensitive data.
- **Source framework and links:** [LlamaIndex: starter example](https://docs.llamaindex.ai/en/stable/getting_started/starter_example/), [PydanticAI: chat app](https://pydantic.dev/docs/ai/examples/conversational-agents/chat-app/)

## Best-effort implementation

- `git show 357b22a:lib/examples/03_llm/03_18_starter_chatbot/starter_chatbot.ex`
- `git show 357b22a:test/examples/03_llm/03_18_starter_chatbot/starter_chatbot_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
