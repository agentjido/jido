Code.require_file("support/suite.exs", __DIR__)

defmodule JidoCoreBench.AdmissionCapture do
  @moduledoc false
  alias Jido.AgentServer, as: Server
  alias JidoCoreBench.{Fixtures, Measure, Suite}

  def run do
    {:ok, supervisor} = Jido.start_link(name: JidoCoreBench)
    :erlang.trace_pattern({Task.Supervisor, :async, 2}, true, [])

    try do
      for kind <- [:small, :large_map, :large_list, :large_binary] do
        capture(kind)
      end
    after
      :erlang.trace_pattern({Task.Supervisor, :async, 2}, false, [])
      Supervisor.stop(supervisor)
    end
  end

  defp capture(kind) do
    payload = Fixtures.payload(kind)
    agent = Fixtures.agent(1, payload, JidoCoreBench.Add, [JidoCoreBench.AdmitPlugin])
    {:ok, server} = Server.start_link(agent: agent, jido: JidoCoreBench, register: false)
    :erlang.trace(server, true, [:call, {:tracer, self()}])

    try do
      {:ok, result} = Server.call(server, Fixtures.signal())
      Fixtures.equal!(result.state, %{count: 1, payload: payload})
      :erlang.trace(server, false, [:call])
      ref = :erlang.trace_delivered(server)

      receive do
        {:trace_delivered, ^server, ^ref} -> :ok
      after
        5_000 -> raise "admission call trace did not complete"
      end

      fun =
        receive do
          {:trace, ^server, :call, {Task.Supervisor, :async, [_supervisor, fun]}}
          when is_function(fun, 0) ->
            fun
        after
          5_000 -> raise "admission task function was not captured"
        end

      receive do
        {:trace, ^server, :call, {Task.Supervisor, :async, _args}} ->
          raise "more than one task function was captured"
      after
        0 -> :ok
      end

      Suite.ensure_idle!()
      {:env, env} = Function.info(fun, :env)

      %{
        payload: kind,
        captures_server_state: Enum.any?(env, &match?(%Jido.AgentServer.State{}, &1)),
        function_term: Measure.term_size(fun)
      }
    after
      :erlang.trace(server, false, [:call])
      Server.stop(server, :normal)
    end
  end
end

{opts, args, invalid} = OptionParser.parse(System.argv(), strict: [output: :string])

if args != [] or invalid != [],
  do: raise(ArgumentError, "usage: mix run bench/capture_admission.exs --output PATH")

cases = JidoCoreBench.AdmissionCapture.run()

report =
  Map.merge(JidoCoreBench.Suite.metadata(), %{
    schema_version: 1,
    method:
      "trace the actual admission function argument; check result and cleanup; copy that function into a receiver",
    limitations: [
      "This is a traced diagnostic. It supplies no timing evidence.",
      "Copied function heap size is one argument transfer, not total task traffic.",
      "Binary payloads can be shared; heap size does not include their full byte size."
    ],
    cases: cases
  })

output = Keyword.get(opts, :output, "bench/results/admission-capture.json")
File.mkdir_p!(Path.dirname(output))
File.write!(output, JSON.encode!(report))
IO.puts("Wrote #{output}")
