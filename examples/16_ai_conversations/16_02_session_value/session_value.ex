defmodule Jido.Examples.AI.SessionValue do
  @moduledoc "Creates, records, projects, encodes, and closes one portable Session value."

  alias Jido.AI.Thread.Projection
  alias Jido.Session

  @doc "Creates an open Session with lesson metadata."
  def new(opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{"example" => "session_value"})
    Session.new(Keyword.put(opts, :metadata, metadata))
  end

  @doc "Appends one complete local user and assistant exchange."
  def record(%Session{} = session, note, at \\ System.system_time(:millisecond)) when is_binary(note) do
    with {:ok, session} <- Projection.append(session, %{role: :user, content: note}, %{}, at),
         {:ok, session} <-
           Projection.append(session, %{role: :assistant, content: "Recorded: #{note}"}, %{}, at + 1) do
      {:ok, session}
    end
  end

  @doc "Returns the complete messages that can enter a later model request."
  def messages(%Session{} = session), do: Projection.messages(session)

  @doc "Closes the immutable Session value."
  def close(%Session{} = session), do: Session.close(session)
end
