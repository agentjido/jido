> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Agent-owned history

Jido v3 stores message history as application-owned Agent state. The application
defines the schema, appends messages, chooses model context, and controls
retention. History does not require a Plugin or Directive.

The Thread Plugin and its Set Directive have been removed. `Jido.Thread`,
`Jido.Thread.Entry`, and their normalization helper remain optional data tools.
Generic Plugin ownership and state validation remain supported.

## Migration

Remove `Jido.Plugin.Thread` from the Agent's `plugins` list. Declare a history
field in its schema. For a message list, use:

```elixir
schema: Zoi.object(%{messages: Zoi.list(Zoi.map()) |> Zoi.default([])})
```

Replace the old return form:

```elixir
{:ok, next_state, [Jido.Plugin.Thread.set(next_thread) | directives]}
```

with a complete application state update:

```elixir
messages = next_state.messages ++ [user_message, assistant_message]
{:ok, %{next_state | messages: messages}, directives}
```

Return an error when the operation fails. The Server validates the candidate
and commits only a successful Turn. Delivery, scheduling, and child operations
can still use Directives after that commit.

Applications that want to keep the Thread value can declare the same `thread`
field explicitly:

```elixir
schema: Zoi.object(%{thread: Jido.Thread.schema() |> Zoi.nullable() |> Zoi.default(nil)})

# After computing next_thread:
{:ok, %{next_state | thread: next_thread}, directives}
```

Keeping the same field and value shape avoids a history-format conversion.
If an application changes stored Thread values to message lists, it must map
the existing entries to its chosen fields before restoring that state. Decide
which IDs, timestamps, references, and payload fields to retain. There is no
automatic checkpoint conversion.

Stored Agent definitions or pending Directives that name the removed Plugin
modules also need migration before reuse.

The optional Thread helper still has convenience operations that read the
clock and generate missing IDs. Explicit time and identity inputs remain a
separate follow-up in [issue #14](https://github.com/mikehostetler/jido_v3/issues/14).

## Integration evidence

- [Conversation History](../../examples/03_llm/03_02_conversation_history/conversation_history.ex)
  keeps user and assistant messages across Turns and rejects duplicate input.
- [ReAct integration](../../test/examples/08_applications/08_07_react/react_test.exs) checks prior
  context, intermediate state visibility, failure, and scheduled follow-up.
- [Coordinator integration](../../test/examples/08_applications/08_06_coordinator/coordinator_test.exs)
  keeps delegation history while child work and scheduled Signals run.
- [Plugin tests](../../test/jido/plugin/built_ins_test.exs) use a local Credits
  Plugin to retain state-only Plugin coverage without the removed Thread API.
