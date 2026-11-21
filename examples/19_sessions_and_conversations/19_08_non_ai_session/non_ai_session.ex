defmodule Jido.Examples.Conversation.SupportCase do
  @moduledoc "Uses a Session and Thread for a non-AI support workflow."

  alias Jido.Session
  alias Jido.Thread.Entry

  @doc "Creates one application-owned support Session."
  def new(case_id) when is_binary(case_id) do
    Session.new(
      id: "support:#{case_id}",
      metadata: %{"case_id" => case_id, "purpose" => "support_workflow"}
    )
  end

  @doc "Appends one portable support event."
  def record(session, kind, payload) when is_atom(kind) and is_map(payload) do
    Session.append(session, Entry.new(kind: kind, payload: payload))
  end

  @doc "Returns the application-owned public event projection."
  def events(session) do
    Enum.map(session.thread.entries, fn entry ->
      %{sequence: entry.seq, type: Atom.to_string(entry.kind), data: entry.payload}
    end)
  end
end
