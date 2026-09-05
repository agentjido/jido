defmodule Jido.Examples.ContextCompaction.Compact do
  @moduledoc false
  alias Jido.Examples.LLM.Adapter

  use Jido.Action,
    name: "llm_compact_history",
    schema:
      Zoi.object(%{
        keep: Zoi.integer() |> Zoi.min(0),
        max_bytes: Zoi.integer() |> Zoi.min(1),
        required_facts: Zoi.list(Zoi.string()) |> Zoi.default([])
      })

  def run(input, %{agent_state: state} = context) do
    {prefix, suffix} = Enum.split(state.messages, max(length(state.messages) - input.keep, 0))

    with {:ok, raw} <-
           Adapter.call(context, :model, :summarize, %{summary: state.summary, messages: prefix}),
         {:ok, parsed} <- Adapter.parse(Zoi.object(%{summary: Zoi.string() |> Zoi.min(1)}), raw) do
      size = byte_size(parsed.summary) + Enum.sum(Enum.map(suffix, &byte_size(&1.content)))

      cond do
        not Enum.all?(input.required_facts, &String.contains?(parsed.summary, &1)) ->
          Adapter.invalid("summary lost a required fact")

        size > input.max_bytes ->
          Adapter.invalid("context byte limit exceeded")

        true ->
          {:ok, %{state | summary: parsed.summary, messages: suffix}}
      end
    end
  end
end

defmodule Jido.Examples.ContextCompaction.Reply do
  @moduledoc false
  alias Jido.Examples.LLM.Adapter
  use Jido.Action, name: "llm_compacted_reply", schema: Adapter.prompt_schema()

  def run(input, %{agent_state: state} = context) do
    summary = if state.summary == "", do: [], else: [%{role: :system, content: state.summary}]
    user = %{role: :user, content: input.prompt}

    with {:ok, raw} <-
           Adapter.call(context, :model, :complete, %{
             messages: summary ++ state.messages ++ [user]
           }),
         {:ok, result} <- Adapter.parse(Adapter.answer_schema(), raw) do
      {:ok,
       %{state | messages: state.messages ++ [user, %{role: :assistant, content: result.answer}]}}
    end
  end
end

defmodule Jido.Examples.ContextCompaction do
  @moduledoc "Compact committed history and retain queued messages. Limits measure UTF-8 bytes, not tokens."

  use Jido.Agent, name: "llm_compaction_agent"

  agent do
    schema Zoi.object(%{
             summary: Zoi.string() |> Zoi.default(""),
             messages: Zoi.list(Zoi.map()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/llm"

    route "llm.compact.append" do
      action %{text: text},
        name: "llm_compaction_append",
        schema: Zoi.object(%{text: Zoi.string() |> Zoi.min(1)}),
        context: context do
        message = %{role: :user, content: text}
        {:ok, %{context.agent_state | messages: context.agent_state.messages ++ [message]}}
      end

      define :append_message, args: [:text]
    end

    route "llm.compact.run", Jido.Examples.ContextCompaction.Compact do
      define :compact_history
    end

    route "llm.compact.reply", Jido.Examples.ContextCompaction.Reply do
      define :reply, args: [:prompt]
    end
  end
end
