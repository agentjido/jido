defmodule Jido.Examples.ContextMemory.TrimAndCompact.TrimHistory do
  use Jido.Action, name: "example_context_trim_history"

  @impl true
  def run(%{history: history, max_messages: max_messages, max_bytes: max_bytes}, _context) do
    {retained_reversed, bytes} =
      history
      |> Enum.reverse()
      |> Enum.reduce_while({[], 0}, fn message, {retained, used} ->
        size = byte_size(message.content)

        if length(retained) < max_messages and used + size <= max_bytes do
          {:cont, {[message | retained], used + size}}
        else
          {:halt, {retained, used}}
        end
      end)

    retained = retained_reversed
    dropped_count = length(history) - length(retained)
    dropped = Enum.take(history, dropped_count)

    {:ok,
     %{
       retained: retained,
       dropped: dropped,
       full_history_count: length(history),
       retained_count: length(retained),
       dropped_count: dropped_count,
       budget: %{
         max_messages: max_messages,
         max_bytes: max_bytes,
         used_bytes: bytes,
         estimated_tokens: div(bytes + 3, 4)
       }
     }}
  end
end

defmodule Jido.Examples.ContextMemory.TrimAndCompact.CompactDropped do
  use Jido.Action, name: "example_context_compact_dropped"

  @impl true
  def run(%{trimmed: %{dropped: []} = trimmed}, _context) do
    {:ok, Map.merge(trimmed, %{summary: nil, compaction_model_calls: 0})}
  end

  def run(%{trimmed: trimmed}, context) do
    client = Jido.AI.InferenceClient.Selection.client!(context)
    model_context = ReqLLM.Context.new(Enum.map(trimmed.dropped, &to_message/1))

    case client.compact_context("offline:compact", model_context,
           offline_summary: "Earlier discussion covered account setup and billing."
         ) do
      {:ok, compacted} ->
        {:ok,
         Map.merge(trimmed, %{
           summary: compacted.summary,
           compacted_source_messages: compacted.source_messages,
           compaction_model_calls: 1
         })}

      {:error, reason} ->
        {:error, Jido.Error.execution_error("context compaction failed", %{reason: reason})}
    end
  end

  defp to_message(%{role: :user, content: content}), do: ReqLLM.Context.user(content)
  defp to_message(%{role: :assistant, content: content}), do: ReqLLM.Context.assistant(content)
  defp to_message(%{role: :system, content: content}), do: ReqLLM.Context.system(content)
end

defmodule Jido.Examples.ContextMemory.TrimAndCompact do
  use Jido.Flow,
    name: "example_context_trim_and_compact",
    schema:
      Jido.Joi.object(%{
        history: Jido.Joi.list(Jido.Joi.map()),
        max_messages: Jido.Joi.integer() |> Jido.Joi.min(1),
        max_bytes: Jido.Joi.integer() |> Jido.Joi.min(1)
      })

  alias Jido.Examples.ContextMemory.TrimAndCompact.{CompactDropped, TrimHistory}

  flow do
    step "trim",
      action: TrimHistory,
      params: %{
        history: input(:history),
        max_messages: input(:max_messages),
        max_bytes: input(:max_bytes)
      }

    step "compact", action: CompactDropped, params: %{trimmed: result("trim")}
    output result("compact")
  end
end
