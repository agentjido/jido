defmodule Jido.Durable.ApiTest do
  use Jido.Test.Case, async: false

  alias Jido.Durable
  alias Jido.Durable.Status

  defmodule ReadSignal do
    use Jido.Action, name: "durable_read_signal"

    @impl true
    def run(%{value: value}, %{signal: signal}) do
      {:ok, %{value: value + 1, signal_id: signal.id, signal_type: signal.type}}
    end
  end

  defmodule DirectFlow do
    use Jido.Flow, name: "durable_direct_flow"

    flow do
      step "read", action: ReadSignal, params: %{value: input(:value)}
      output result("read")
    end
  end

  defmodule OtherFlow do
    use Jido.Flow, name: "durable_other_flow"

    flow do
      step "other", action: ReadSignal, params: %{value: input(:value)}
      output %{other: result("other")}
    end
  end

  defmodule WaitFlow do
    use Jido.Flow, name: "durable_wait_flow"

    flow do
      selection "decision" do
        await "approved",
          event: "durable.approved",
          match: %{request_id: input(:request_id)}

        timer "expired", after_ms: 1_000
      end

      output result("decision")
    end
  end

  setup c do
    table = Module.concat(__MODULE__, Store)
    persistence = {Jido.Persistence.ETS, table: table}
    jido = :"jido_durable_test_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido, name: jido, namespace: "jido/durable/#{System.unique_integer([:positive])}", persistence: persistence},
      id: jido
    )

    %{bare_jido: c.jido, jido: jido}
  end

  test "runs a Flow from a Signal and stores its result", c do
    input = signal("durable.start", %{value: 4})

    assert {:ok, %Status{state: :completed, waits: [], ref: ref}} =
             Durable.start(c.jido, DirectFlow, input)

    assert Durable.result(c.jido, ref) ==
             {:ok, %{value: 5, signal_id: input.id, signal_type: "durable.start"}}

    assert {:ok, %Status{state: :completed}} = Durable.status(c.jido, ref)

    refute Runic.Runner.lookup(Jido.Instance.Names.exec_runner(c.jido), Durable.Ref.execution_id(ref))
  end

  test "lowers one Action to the same durable Flow path", c do
    input = signal("durable.action", %{value: 8})
    signal_id = input.id

    assert {:ok, %Status{state: :completed, ref: ref}} =
             Durable.start(c.jido, ReadSignal, input)

    assert {:ok, %{value: 9, signal_id: ^signal_id}} =
             Durable.result(c.jido, ref)
  end

  test "saves a wait Signal before resume and makes equal retries inert", c do
    input = signal("durable.request", %{request_id: "r1"})

    assert {:ok,
            %Status{
              state: :waiting,
              waits: [%{id: wait_id}],
              next_wake_at: 1_100,
              ref: ref
            }} =
             Durable.start(c.jido, WaitFlow, input, now: 100)

    approval = signal("durable.approved", %{request_id: "r1", actor: "operator"})
    assert :ok = Durable.signal(c.jido, ref, wait_id, approval, now: 200)
    assert :ok = Durable.signal(c.jido, ref, wait_id, approval, now: 200)

    assert {:ok, %Status{state: :waiting}} = Durable.status(c.jido, ref)

    assert {:ok, %Status{state: :completed}} =
             Durable.resume(c.jido, ref, now: 200)

    assert {:ok, %{selected: "approved", value: %{request_id: "r1", actor: "operator"}}} =
             Durable.result(c.jido, ref)
  end

  test "rejects a conflicting retry with the same Signal ID", c do
    input = signal("durable.request", %{request_id: "r1"})

    assert {:ok, %Status{waits: [%{id: wait_id}], ref: ref}} =
             Durable.start(c.jido, WaitFlow, input, now: 100)

    approval = signal("durable.approved", %{request_id: "r1"})
    assert :ok = Durable.signal(c.jido, ref, wait_id, approval, now: 200)

    conflicting = %{approval | data: %{request_id: "r1", changed: true}}

    assert {:error, %{details: %{reason: :conflicting_input_id}}} =
             Durable.signal(c.jido, ref, wait_id, conflicting, now: 200)
  end

  test "lets a host resume a saved timer at its wake time", c do
    input = signal("durable.request", %{request_id: "r2"})

    assert {:ok, %Status{state: :waiting, next_wake_at: 1_100, ref: ref}} =
             Durable.start(c.jido, WaitFlow, input, now: 100)

    assert {:ok, %Status{state: :completed}} =
             Durable.resume(c.jido, ref, now: 1_100)

    assert {:ok, %{selected: "expired", value: %{fired_at: 1_100}}} =
             Durable.result(c.jido, ref)
  end

  test "uses only instance persistence and requires portable context", c do
    input = signal("durable.start", %{value: 1})

    assert {:error, %Jido.Error.ValidationError{}} =
             Durable.start(c.bare_jido, DirectFlow, input)

    assert {:error, %Jido.Error.ValidationError{details: %{unsupported: [:persistence]}}} =
             Durable.start(c.jido, DirectFlow, input, persistence: Jido.Persistence.ETS)

    assert {:error, %Jido.Error.ExecutionError{details: %{reason: :non_portable_durable_value}}} =
             Durable.start(c.jido, DirectFlow, input, context: %{caller: self()})
  end

  test "rejects execution ID reuse with changed input or definition", c do
    input = signal("durable.start", %{value: 1})

    assert {:ok, %Status{ref: ref}} =
             Durable.start(c.jido, DirectFlow, input)

    assert {:ok, %Status{state: :completed, ref: ^ref}} =
             Durable.start(c.jido, DirectFlow, input)

    changed = %{input | data: %{value: 2}}

    assert {:error, :execution_input_changed} =
             Durable.start(c.jido, DirectFlow, changed, id: ref.id)

    assert {:error, :execution_definition_changed} =
             Durable.start(c.jido, OtherFlow, input, id: ref.id)
  end

  test "rejects invalid execution options without raising", c do
    input = signal("durable.start", %{value: 1})

    invalid_options = [
      [timeout: "1"],
      [max_attempts: "1"],
      [backoff: :unknown],
      [base_delay_ms: -1],
      [max_delay_ms: :infinity],
      [max_concurrency: 0],
      [max_attempts: 1, max_attempts: 2]
    ]

    for exec_opts <- invalid_options do
      assert {:error, %Jido.Error.ValidationError{}} =
               Durable.start(c.jido, DirectFlow, input, exec_opts: exec_opts)
    end
  end

  test "public read and resume operations reject an invalid reference", c do
    assert {:error, %Jido.Error.ValidationError{}} = Durable.resume(c.jido, :invalid)
    assert {:error, %Jido.Error.ValidationError{}} = Durable.status(c.jido, :invalid)
    assert {:error, %Jido.Error.ValidationError{}} = Durable.result(c.jido, :invalid)
  end
end
