defmodule JidoCoreBench.AuthoringCases do
  @moduledoc false
  alias Jido.Authoring.Registry
  alias JidoCoreBench.Fixtures, as: F

  def workloads(sizes) do
    definitions =
      for size <- sizes do
        F.checked(
          "authoring/definition/#{size}",
          fn _ -> F.definition(size) end,
          fn definition ->
            definition |> Map.from_struct() |> Map.drop([:id, :state]) |> Jido.Agent.define()
          end,
          fn {:ok, definition} -> F.equal!(length(definition.routes), size) end
        )
        |> Map.put(:verify, fn definition, result -> F.equal!(result, {:ok, definition}) end)
      end

    definitions ++ registry_cases() ++ codec_cases(sizes)
  end

  defp codec_cases(sizes) do
    for size <- sizes, operation <- [:encode, :decode, :decode_instance] do
      F.checked(
        "authoring/codec/routes_#{size}/#{operation}",
        fn _ ->
          definition = F.definition(size, JidoCoreBench.Add, [JidoCoreBench.PreparePlugin])
          registry = JidoTest.AgentRegistry.for(definition)
          {:ok, document} = JidoTest.AgentRegistry.encode(definition, registry)
          %{definition: definition, document: document, registry: registry}
        end,
        fn prepared ->
          case operation do
            :encode ->
              JidoTest.AgentRegistry.encode(prepared.definition, prepared.registry)

            :decode ->
              JidoTest.AgentRegistry.decode(prepared.document, prepared.registry)

            :decode_instance ->
              with {:ok, definition} <-
                     JidoTest.AgentRegistry.decode(prepared.document, prepared.registry),
                   do: Jido.Agent.instantiate(definition, id: "decoded")
          end
        end,
        fn result -> F.equal!(elem(result, 0), :ok) end
      )
      |> Map.put(:verify, fn prepared, result ->
        expected =
          case operation do
            :encode -> prepared.document
            :decode -> prepared.definition
            :decode_instance -> Jido.Agent.instantiate!(prepared.definition, id: "decoded")
          end

        F.equal!(result, {:ok, expected})
      end)
    end
  end

  defp registry_cases do
    for size <- [1, 256], shape <- [:flat, :nested], operation <- [:resolve, :reference] do
      F.checked(
        "authoring/registry/#{size}/#{shape}/#{operation}",
        fn _ ->
          entries =
            Map.new(1..size, fn index ->
              value = if shape == :nested, do: %{index: index}, else: index
              {{"data/#{index}", 1}, {:data, value}}
            end)

          registry = Registry.new!(entries)
          value = if shape == :nested, do: %{index: size}, else: size
          {registry, {"data/#{size}", 1}, value}
        end,
        fn {registry, identifier, value} ->
          case operation do
            :resolve -> Registry.resolve(registry, identifier, :data)
            :reference -> Registry.reference(registry, :data, value)
          end
        end,
        fn result ->
          value = if shape == :nested, do: %{index: size}, else: size
          expected = if operation == :resolve, do: value, else: {"data/#{size}", 1}
          F.equal!(result, {:ok, expected})
        end
      )
    end
  end
end
