defmodule JidoTest.Persistence.CheckpointIdentityProbe do
  @moduledoc false
  use Jido.Agent, name: "test_checkpoint_identity"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  def store_mismatched_checkpoint(store, requested_id, checkpoint_id) do
    agent = new!(id: requested_id, state: %{count: 7})

    with :ok <-
           Jido.Persistence.save_agent(store, agent, namespace: "persistence-probe", revision: 3) do
      JidoTest.Persistence.ProbeStore.rewrite_record(store, requested_id, fn record ->
        put_in(record.checkpoint.id, checkpoint_id)
      end)
    end
  end
end

defmodule JidoTest.Persistence.CheckpointPortabilityProbe do
  @moduledoc false
  use Jido.Agent, name: "test_checkpoint_portability"

  agent do
    schema Zoi.object(%{payload: Zoi.map() |> Zoi.default(%{})})
  end

  def store_payload(store, id, payload) do
    with :ok <-
           Jido.Persistence.save_agent(store, new!(id: id),
             namespace: "persistence-probe",
             revision: 3
           ) do
      JidoTest.Persistence.ProbeStore.rewrite_record(store, id, fn record ->
        put_in(record.checkpoint.state.payload, payload)
      end)
    end
  end
end

defmodule JidoTest.Persistence.IndeterminateWriteProbe do
  @moduledoc false
  use Jido.Agent, name: "test_indeterminate_write"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/test/persistence/indeterminate_write"

    route "test.persistence.indeterminate_write.increment", as: :increment do
      action input,
        schema: Zoi.object(%{request_id: Zoi.string() |> Zoi.min(1), amount: Zoi.integer()}),
        context: context do
        next = %{context.agent_state | count: context.agent_state.count + input.amount}

        output =
          Jido.Signal.new!(
            "test.persistence.indeterminate_write.applied",
            %{request_id: input.request_id, count: next.count},
            source: "/test/persistence/indeterminate_write"
          )

        directives =
          if sink = context[:reply_to],
            do: [Jido.Agent.Directive.emit_to_pid(output, sink)],
            else: []

        {:ok, next, directives}
      end
    end
  end
end
