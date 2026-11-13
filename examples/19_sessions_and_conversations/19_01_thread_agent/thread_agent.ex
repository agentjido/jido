defmodule Jido.Examples.Conversation.ThreadValue do
  @moduledoc "Creates, queries, and round-trips one portable Thread value."

  alias Jido.Thread
  alias Jido.Thread.Entry

  @doc "Builds one two-entry support Thread."
  def build do
    Thread.new(id: "support-thread", now: 100)
    |> Thread.append([
      Entry.new(id: "opened", kind: :case_opened, at: 101, payload: %{"case_id" => "case-7"}),
      Entry.new(id: "noted", kind: :note, at: 102, payload: %{"text" => "Customer replied"})
    ])
  end
end
