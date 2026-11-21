Code.require_file("transcript.ex", __DIR__)
Code.require_file("recall_turn.ex", __DIR__)
Code.require_file("long_running.ex", __DIR__)
Code.require_file("support/offline_client.ex", __DIR__)

defmodule Jido.Examples.ContextMemory.LongRunning.Demo do
  alias Jido.Examples.ContextMemory.LongRunning
  alias Jido.Examples.ContextMemory.LongRunning.{Agent, OfflineClient, Transcript}

  def run(args) do
    opts = OptionParser.parse!(args, strict: [turns: :integer, compaction: :string, directory: :string])
    {opts, []} = opts
    turns = Keyword.get(opts, :turns, 1_000)
    true = turns >= 6

    compaction =
      case Keyword.get(opts, :compaction, "deterministic") do
        "deterministic" -> :deterministic
        "model" -> {:model, "offline:archive-summary", OfflineClient}
        other -> raise ArgumentError, "unknown compaction mode #{inspect(other)}"
      end

    destination = opts[:directory]
    path = destination || Path.join(System.tmp_dir!(), "jido-transcript-#{Jido.Id.uuid7()}")
    File.mkdir!(path)

    try do
      run_at(path, turns, compaction)
      if destination, do: IO.puts("Saved transcript database in #{path}")
    after
      if is_nil(destination), do: File.rm_rf!(path)
    end
  end

  defp run_at(path, turns, compaction) do
    instance = __MODULE__
    namespace = "example/long-running"
    address = Jido.Agent.Address.new!(namespace: namespace, id: "conversation")

    {:ok, table} = Transcript.open(Transcript, Path.join(path, "transcript.dets"))

    try do
      {:ok, _supervisor} =
        Jido.start_link(
          name: instance,
          namespace: namespace,
          persistence: {Jido.Persistence.File, path: Path.join(path, "agent")}
        )

      try do
        {:ok, ^address} = Jido.create_agent(instance, address, Agent)
        {:ok, _server} = Jido.activate_agent(instance, address)
        app = %{instance: instance, address: address, table: table, inference: OfflineClient, compaction: compaction}

        for number <- 1..turns do
          input = if number == turns, do: "Recall turn 1", else: "Observation #{number}"
          {:ok, %{number: ^number, status: :completed} = record} = LongRunning.ask(app, input)
          if rem(number, 4) == 0, do: :ok = LongRunning.compact(app)
          if rem(number, 100) == 0, do: IO.puts("Committed and archived #{number} Turns")

          if number == turns do
            true = Enum.any?(record.entries, fn entry -> entry["payload"]["role"] == "tool" end)
            true = Enum.any?(record.entries, fn entry -> inspect(entry["payload"]["content"]) =~ "Observation 1" end)
          end
        end

        ^turns = Transcript.count(table)
        {:ok, %{entries: [_ | _]}} = Transcript.read(table, 1)
        {:ok, session} = LongRunning.window(app)
        {:ok, messages} = Jido.AI.Thread.Projection.messages(session)
        false = Enum.any?(messages, &(&1.content == "Observation 1"))
        {:ok, server} = Jido.resolve_agent(instance, address)
        %{agent_revision: ^turns, agent: %{state: %{session: nil}}} = Jido.AgentServer.snapshot(server)

        IO.puts("Archived #{turns} Turns. The final Turn recalled Turn 1 by tool.")
      after
        :ok = Jido.stop(instance)
      end
    after
      :ok = Transcript.close(table)
    end
  end
end

Jido.Examples.ContextMemory.LongRunning.Demo.run(System.argv())
