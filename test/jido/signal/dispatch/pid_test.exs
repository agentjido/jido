defmodule Jido.Signal.Dispatch.PidAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Dispatch

  defmodule Receiver do
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))

    @impl true
    def init(opts), do: {:ok, Keyword.fetch!(opts, :owner)}

    @impl true
    def handle_call(message, _from, owner) do
      send(owner, {:received_call, message})
      {:reply, :ok, owner}
    end

    @impl true
    def handle_info(message, owner) do
      send(owner, {:received_message, message})
      {:noreply, owner}
    end
  end

  test "parses PID and named targets through one Zoi schema" do
    assert {:ok, {:pid, pid_opts}} = Dispatch.validate_opts({:pid, target: self()})
    assert pid_opts == [target: self(), delivery_mode: :async, timeout: 5_000]

    assert {:ok, {:named, named_opts}} =
             Dispatch.validate_opts({:named, target: {:name, __MODULE__}})

    assert named_opts == [
             target: {:name, __MODULE__},
             delivery_mode: :async,
             timeout: 5_000
           ]

    assert {:error, reason} = Dispatch.validate_opts({:named, target: {:name, nil}})
    assert reason =~ "registered name"
  end

  test "rejects remote PID targets at validation and dispatch boundaries" do
    target = JidoSignalTest.Case.remote_pid()
    assert {:error, _reason} = Dispatch.validate_opts({:pid, target: target})
    assert {:error, _reason} = Dispatch.dispatch(signal(), {:pid, target: target})
  end

  test "delivers async and sync messages to a PID" do
    receiver = start_supervised!({Receiver, owner: self()})
    signal = signal()

    assert :ok = Dispatch.dispatch(signal, {:pid, target: receiver})
    assert self() == :sys.get_state(receiver)
    assert_received {:received_message, {:signal, ^signal}}

    assert :ok =
             Dispatch.dispatch(
               signal,
               {:pid, target: receiver, message_format: &{:custom, &1}}
             )

    assert self() == :sys.get_state(receiver)
    assert_received {:received_message, {:custom, ^signal}}

    assert :ok = Dispatch.dispatch(signal, {:pid, target: receiver, delivery_mode: :sync})
    assert_received {:received_call, {:signal, ^signal}}
  end

  test "validates the OTP receive timeout boundary before delivery" do
    receiver = start_supervised!({Receiver, owner: self()})
    event = signal()

    assert :ok =
             Dispatch.dispatch(
               event,
               {:pid, target: receiver, delivery_mode: :sync, timeout: 4_294_967_295}
             )

    assert_received {:received_call, {:signal, ^event}}

    for adapter <- [:pid, :named], timeout <- [4_294_967_296, 10_000_000_000_000] do
      target = if adapter == :pid, do: receiver, else: {:name, :unused_signal_receiver}
      config = {adapter, target: target, delivery_mode: :sync, timeout: timeout}
      assert {:error, _} = Dispatch.validate_opts(config)
      assert {:error, _} = Dispatch.dispatch(event, config)
    end

    refute_received {:received_call, {:signal, ^event}}
  end

  test "resolves a registered process for named delivery" do
    name = Module.concat(__MODULE__, "Receiver#{System.unique_integer([:positive])}")
    receiver = start_supervised!({Receiver, owner: self(), name: name})
    assert Process.whereis(name) == receiver
    signal = signal()

    assert :ok = Dispatch.dispatch(signal, {:named, target: {:name, name}})
    assert self() == :sys.get_state(receiver)
    assert_received {:received_message, {:signal, ^signal}}

    assert :ok =
             Dispatch.dispatch(signal, {:named, target: {:name, name}, delivery_mode: :sync})

    assert_received {:received_call, {:signal, ^signal}}
  end

  test "returns stable errors for missing and dead processes" do
    signal = signal()
    dead = spawn(fn -> :ok end)
    monitor = Process.monitor(dead)
    assert_receive {:DOWN, ^monitor, :process, ^dead, _reason}, 1_000

    assert {:error, :process_not_alive} = Dispatch.dispatch(signal, {:pid, target: dead})

    assert {:error, :process_not_found} =
             Dispatch.dispatch(signal, {:named, target: {:name, :missing_signal_target}})
  end

  test "does not call the current process synchronously" do
    signal = signal()

    assert {:error, {:calling_self, {GenServer, :call, [pid, {:signal, ^signal}, 5_000]}}} =
             Dispatch.dispatch(signal, {:pid, target: self(), delivery_mode: :sync})

    assert pid == self()
  end

  test "normalizes synchronous process exits" do
    signal = signal()

    blocked = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> if Process.alive?(blocked), do: Process.exit(blocked, :kill) end)

    assert {:error, :timeout} =
             Dispatch.dispatch(signal, {:pid, target: blocked, delivery_mode: :sync, timeout: 1})

    crashing =
      spawn(fn ->
        receive do
          {:"$gen_call", _from, _message} -> exit(:receiver_failed)
        end
      end)

    on_exit(fn -> if Process.alive?(crashing), do: Process.exit(crashing, :kill) end)

    assert {:error, {:receiver_failed, {GenServer, :call, _details}}} =
             Dispatch.dispatch(signal, {:pid, target: crashing, delivery_mode: :sync})
  end

  test "normalizes successful synchronous replies and continues list delivery" do
    signal = signal()
    receiver = reply_once({:ok, :accepted})

    assert :ok =
             Dispatch.dispatch(signal, [
               {:pid, target: receiver, delivery_mode: :sync},
               {:pid, target: self()}
             ])

    assert_received {:signal, ^signal}
  end

  test "keeps synchronous error replies" do
    signal = signal()
    receiver = reply_once({:error, :rejected})

    assert {:error, :rejected} =
             Dispatch.dispatch(signal, {:pid, target: receiver, delivery_mode: :sync})
  end

  defp signal, do: Signal.new!("dispatch.process", %{}, source: "/test")

  defp reply_once(reply) do
    start_supervised!(
      {Task,
       fn ->
         receive do
           {:"$gen_call", from, _message} -> GenServer.reply(from, reply)
         end
       end}
    )
  end
end
