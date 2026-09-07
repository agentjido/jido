defmodule JidoCoreBench.BudgetAgent do
  @moduledoc false
  use Jido.Agent,
    name: "core_bench_budget",
    max_state_size: 2_000_000,
    schema: Zoi.object(%{count: Zoi.integer(), payload: Zoi.any()})
end

defmodule JidoCoreBench.EdgeCases do
  @moduledoc false
  alias JidoCoreBench.Fixtures, as: F
  alias Jido.Agent.Command.Runner

  def workloads(thread_sizes, route_sizes) do
    thread_filters(thread_sizes) ++
      context_cases() ++
      generated_codec_cases(route_sizes) ++
      budget_cases()
  end

  defp budget_cases do
    for payload <- [:small, :large_list],
        {mode, module, limit} <- [
          {:unlimited, Jido.Agent, nil},
          {:module, JidoCoreBench.BudgetAgent, nil},
          {:stricter, JidoCoreBench.BudgetAgent, 1_000_000}
        ],
        operation <- [:check, :transition] do
      F.checked(
        "state/budget_batch/#{payload}/#{mode}/#{operation}",
        fn _ -> %{F.agent(1, F.payload(payload)) | module: module, max_state_size: limit} end,
        fn agent ->
          for _ <- 1..100 do
            case operation do
              :check ->
                Jido.Agent.StateBudget.check(agent)

              :transition ->
                candidate = %{agent | module: Jido.Agent, max_state_size: nil}
                Jido.Agent.StateBudget.transition(agent, candidate)
            end
          end
        end,
        fn results -> F.equal!(length(results), 100) end
      )
      |> Map.put(:verify, fn agent, results ->
        expected =
          if operation == :check,
            do: agent,
            else: %{agent | max_state_size: if(mode == :module, do: 2_000_000, else: limit)}

        Enum.each(results, &F.equal!(&1, {:ok, expected}))
        :ok
      end)
    end
  end

  defp thread_filters(sizes) do
    for n <- sizes,
        {mode, kinds} <- [single: :message, multiple: [:message, :tool], missing: :absent] do
      entries =
        for i <- 1..n do
          %{id: "entry-#{i}", at: 1, kind: Enum.at([:note, :message, :tool], rem(i, 3))}
        end

      expected =
        for entry <- entries, entry.kind in List.wrap(kinds), do: {entry.id, entry.kind}

      F.checked(
        "thread/filter/#{n}/#{mode}",
        fn _ -> Jido.Thread.append(Jido.Thread.new(id: "bench-filter", now: 1), entries) end,
        &Jido.Thread.filter_by_kind(&1, kinds),
        &F.equal!(Enum.map(&1, fn entry -> {entry.id, entry.kind} end), expected)
      )
    end
  end

  defp context_cases do
    for n <- [0, 1_000, 10_000], mode <- [:prepare, :reject] do
      caller = if n == 0, do: %{}, else: Map.new(1..n, &{&1, %{value: &1}})

      caller =
        if mode == :reject,
          do: Map.merge(caller, %{agent_id: nil, agent_state: nil, signal: nil}),
          else: caller

      F.checked(
        "command/context/#{n}/#{mode}",
        fn context -> {F.agent(1, nil), F.signal(), Map.merge(caller, context)} end,
        fn {agent, signal, context} -> Runner.prepare(agent, signal, context: context) end,
        fn result ->
          case {mode, result} do
            {:prepare, {:ok, %Runner.Prepared{}}} ->
              :ok

            {:reject, {:error, %Jido.Error.ValidationError{message: message}}} ->
              F.equal!(message, "Agent command context contains reserved keys")
          end
        end
      )
      |> Map.put(:verify, fn {agent, signal, context}, result ->
        case result do
          {:ok, prepared} ->
            F.equal!(prepared.agent, agent)
            F.equal!(prepared.signal, signal)

            F.equal!(
              prepared.context,
              Map.merge(context, %{agent_id: agent.id, agent_state: agent.state, signal: signal})
            )

          {:error, error} ->
            keys = Map.keys(context) |> Enum.filter(&(&1 in [:agent_id, :agent_state, :signal]))
            F.equal!(error.details, %{keys: keys})
        end
      end)
    end
  end

  defp generated_codec_cases(sizes) do
    for n <- sizes do
      F.checked(
        "codec/generated/#{n}",
        fn _ -> F.definition(n) end,
        &Jido.Agent.Codec.encode/1,
        fn {:ok, document, _registry} -> F.equal!(length(document["routes"]), n) end
      )
      |> Map.put(:verify, fn definition, {:ok, document, registry} ->
        F.equal!(Jido.Agent.Codec.decode(document, registry), {:ok, definition})
      end)
    end
  end
end
