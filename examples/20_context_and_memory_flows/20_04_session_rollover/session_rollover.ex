defmodule Jido.Examples.ContextMemory.SessionRollover.RollOver do
  use Jido.Action, name: "example_context_session_rollover"

  @impl true
  def run(%{session: encoded, expected_rev: expected_rev, new_session_id: new_id, summary: summary}, _context) do
    with {:ok, session} <- Jido.Session.decode(encoded),
         :ok <- current_revision(session, expected_rev) do
      closed = Jido.Session.close(session)

      next =
        Jido.Session.new(
          id: new_id,
          now: closed.updated_at + 1,
          metadata: %{
            "lineage" => %{
              "previous_session_id" => session.id,
              "previous_session_rev" => session.rev,
              "summary_kind" => "lossy_model_compaction"
            }
          }
        )
        |> Jido.Session.append(%{
          kind: :context_summary,
          payload: %{
            "summary" => summary,
            "source_session_id" => session.id,
            "source_rev" => session.rev
          },
          refs: %{"source_session_id" => session.id}
        })

      {:ok,
       %{
         archived_session: Jido.Session.encode(closed),
         next_session: Jido.Session.encode(next),
         replay: %{
           source_session_id: session.id,
           source_rev: session.rev,
           summary: summary,
           complete: false
         }
       }}
    else
      {:error, :invalid_session} ->
        {:error, Jido.Error.validation_error("session document is invalid")}

      {:error, :stale_revision} ->
        {:error,
         Jido.Error.validation_error("session revision is stale", %{
           expected_rev: expected_rev
         })}
    end
  end

  defp current_revision(%Jido.Session{rev: rev}, rev), do: :ok
  defp current_revision(_session, _expected), do: {:error, :stale_revision}
end

defmodule Jido.Examples.ContextMemory.SessionRollover do
  use Jido.Flow,
    name: "example_context_session_rollover",
    schema:
      Jido.Joi.object(%{
        session: Jido.Joi.map(),
        expected_rev: Jido.Joi.integer() |> Jido.Joi.min(0),
        new_session_id: Jido.Joi.string() |> Jido.Joi.min(1),
        summary: Jido.Joi.string() |> Jido.Joi.min(1)
      })

  flow do
    step "rollover",
      action: Jido.Examples.ContextMemory.SessionRollover.RollOver,
      params: %{
        session: input(:session),
        expected_rev: input(:expected_rev),
        new_session_id: input(:new_session_id),
        summary: input(:summary)
      }

    output result("rollover")
  end
end
