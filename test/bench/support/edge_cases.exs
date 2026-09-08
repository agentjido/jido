defmodule JidoCoreBench.EdgeCases do
  @moduledoc false
  alias JidoCoreBench.Fixtures, as: F
  alias Jido.Agent.Command.Runner

  def workloads(route_sizes) do
    context_cases() ++
      generated_codec_cases(route_sizes)
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
