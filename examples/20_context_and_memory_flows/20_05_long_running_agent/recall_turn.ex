defmodule Jido.Examples.ContextMemory.LongRunning.RecallTurn do
  alias Jido.Joi

  alias Jido.Examples.ContextMemory.LongRunning.Transcript
  alias Jido.Thread.Entry

  @page_bytes 512

  use Jido.Action,
    name: "recall_turn",
    description: "Read one page of an archived message by Turn number, message number, and byte offset",
    schema:
      Joi.object(%{
        number: Joi.integer(gte: 1),
        message: Joi.integer(gte: 1) |> Joi.default(1),
        offset: Joi.integer(gte: 0) |> Joi.default(0)
      })

  @impl true
  def run(%{number: number, message: index, offset: offset}, %{transcript_table: table}) do
    case Transcript.read(table, number) do
      {:ok, record} -> page(record, index, offset)
      {:error, :not_found} -> {:ok, %{turn: number, status: "not_found"}}
      {:error, _reason} = error -> error
    end
  end

  defp page(record, index, offset) do
    messages =
      for entry <- record.entries,
          {:ok, %{kind: :ai_message, payload: payload}} <- [Entry.decode(entry)],
          do: payload

    case Enum.fetch(messages, index - 1) do
      {:ok, payload} ->
        # Use JSON so callers can page through tool calls, metadata, and tool results too.
        text = JSON.encode!(payload)
        excerpt = String.byte_slice(text, offset, @page_bytes)
        next = offset + byte_size(excerpt)

        {:ok,
         %{
           turn: record.number,
           message: index,
           excerpt: excerpt,
           next_offset: if(excerpt != "" and next < byte_size(text), do: next),
           next_message: if(index < length(messages), do: index + 1)
         }}

      :error ->
        {:ok, %{turn: record.number, message: index, status: "not_found"}}
    end
  end
end
