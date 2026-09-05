defmodule JidoCoreBench.RuntimeCases do
  @moduledoc false
  alias JidoCoreBench.Fixtures, as: F
  alias Jido.AgentServer, as: Server

  def workloads(payloads) do
    for kind <- payloads, mode <- [:call, :flow, :burst, :snapshot, :failure, :start_stop] do
      data = F.payload(kind)

      target =
        case mode do
          :flow -> F.flow()
          :failure -> JidoCoreBench.Fail
          _ -> JidoCoreBench.Add
        end

      workload =
        F.checked(
          "server/#{mode}/#{kind}",
          fn context ->
            a = F.agent(1, data, target)

            pid =
              if mode == :start_stop do
                nil
              else
                {:ok, pid} = Server.start_link(agent: a, jido: JidoCoreBench, register: false)
                pid
              end

            %{pid: pid, agent: a, signal: F.signal(), context: context}
          end,
          fn p ->
            case mode do
              :snapshot ->
                Server.snapshot(p.pid)

              :start_stop ->
                {:ok, child} =
                  Server.start_link(
                    agent: %{p.agent | id: "core-bench-lifecycle"},
                    jido: JidoCoreBench,
                    register: false
                  )

                F.barrier(p.context)
                :ok = Server.stop(child, :normal)
                Process.alive?(child)

              :burst ->
                for _ <- 1..20, do: Server.cast(p.pid, p.signal)
                # A synchronous call from the same sender is the completion barrier.
                Server.call(p.pid, p.signal, context: p.context)

              _ ->
                Server.call(p.pid, p.signal, context: p.context)
            end
          end,
          fn result ->
            case mode do
              :start_stop ->
                F.equal!(result, false)

              :snapshot ->
                snapshot = result
                F.equal!(snapshot.agent.state, %{count: 0, payload: data})

              :failure ->
                {:error, %Jido.Error.ExecutionError{}} = result
                :ok

              _ ->
                {:ok, a} = result

                expected =
                  case mode do
                    :flow -> 2
                    :burst -> 21
                    _ -> 1
                  end

                F.equal!(a.state, %{count: expected, payload: data})
            end
          end
        )

      workload =
        Map.put(workload, :verify, fn p, _result ->
          if mode == :failure do
            snapshot = Server.snapshot(p.pid)
            F.equal!({snapshot.agent, snapshot.state_version}, {p.agent, 0})
          else
            :ok
          end
        end)

      Map.put(workload, :cleanup, fn p ->
        if is_pid(p.pid) and Process.alive?(p.pid), do: Server.stop(p.pid, :normal)
        :ok
      end)
    end
  end
end
