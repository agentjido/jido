# Reuse the current delivery protocol; keep external fault controls in tests.
unless Code.ensure_loaded?(Jido.Examples.RecoverableDelivery) do
  {:ok, _, _} =
    Kernel.ParallelCompiler.compile(
      Path.wildcard(
        Path.expand(
          "../../../examples/10_persistence/10_07_recoverable_delivery/**/*.ex",
          __DIR__
        )
      ),
      return_diagnostics: true
    )
end

defmodule JidoTest.RecoverableDeliverySink do
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: address(opts[:jido]))
  def init(opts), do: {:ok, %{records: %{}, attempts: [], hold: :none, opts: opts}}
  def records(jido), do: GenServer.call(address(jido), :records)
  def attempts(jido), do: GenServer.call(address(jido), :attempts)
  def hold(jido, stage), do: GenServer.call(address(jido), {:hold, stage})

  def deliver(jido, directive) do
    {stage, observer} = GenServer.call(address(jido), {:attempt, directive, self()})
    barrier(stage, :before_write, observer, directive.effect_id)
    result = GenServer.call(address(jido), {:write, directive})
    barrier(stage, :after_write, observer, directive.effect_id)
    result
  end

  def handle_call(:records, _, s), do: {:reply, s.records, s}
  def handle_call(:attempts, _, s), do: {:reply, Enum.reverse(s.attempts), s}
  def handle_call({:hold, stage}, _, s), do: {:reply, :ok, %{s | hold: stage}}

  def handle_call({:attempt, d, worker}, _, s) do
    send(s.opts[:observer], {:effect_attempt, d.effect_id, worker})
    s.opts[:on_attempt].(d.effect_id)

    {:reply, {s.hold, s.opts[:observer]},
     %{s | attempts: [%{effect_id: d.effect_id, worker: worker} | s.attempts]}}
  end

  def handle_call({:write, d}, _, s) do
    case Map.fetch(s.records, d.effect_id) do
      :error -> {:reply, :ok, %{s | records: Map.put(s.records, d.effect_id, d.value)}}
      {:ok, value} when value == d.value -> {:reply, :ok, s}
      _ -> {:reply, {:error, :effect_identity_conflict}, s}
    end
  end

  defp barrier(stage, stage, observer, id) do
    send(observer, {:effect_barrier, stage, id, self()})
    receive do: (:release -> :ok)
  end

  defp barrier(_, _, _, _), do: :ok
  defp address(jido), do: {:via, Registry, {Jido.registry_name(jido), {__MODULE__, :sink}}}
end

defmodule JidoTest.RecoverableDeliveryAgent do
  def definition do
    definition = Jido.Examples.RecoverableDelivery.definition()

    %{
      definition
      | module: __MODULE__,
        plugins:
          Enum.map(
            definition.plugins,
            &%{&1 | data: %{sink: JidoTest.RecoverableDeliverySink}}
          )
    }
  end

  def instantiate!(opts), do: Jido.Agent.instantiate!(definition(), opts)
  defdelegate record_and_deliver_signal(data), to: Jido.Examples.RecoverableDelivery
end
