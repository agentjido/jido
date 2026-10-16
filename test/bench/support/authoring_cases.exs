defmodule JidoCoreBench.AuthoringCases do
  @moduledoc false
  alias Jido.Agent.Codec
  alias Jido.Codec.Registry
  alias JidoCoreBench.Fixtures, as: F

  def workloads(sizes) do
    definitions =
      for size <- sizes do
        F.checked(
          "authoring/definition/#{size}",
          fn _ -> F.definition(size) end,
          fn definition ->
            definition |> Map.from_struct() |> Map.drop([:id, :state]) |> Jido.Agent.new()
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
          {:ok, document, registry} = Codec.encode(definition)
          %{definition: definition, document: document, registry: registry}
        end,
        fn prepared ->
          case operation do
            :encode -> Codec.encode(prepared.definition, prepared.registry)
            :decode -> Codec.decode(prepared.document, prepared.registry)
            :decode_instance -> Codec.decode(prepared.document, prepared.registry, id: "decoded")
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
    for size <- [1, 256], shape <- [:flat, :nested], operation <- [:derive, :encode] do
      F.checked(
        "authoring/registry/#{size}/#{shape}/#{operation}",
        fn _ ->
          values = for n <- 1..size, do: %URI{host: "host-#{n}", port: n}

          data =
            if shape == :nested, do: Enum.map(values, &%{value: {:item, [&1, &1]}}), else: values

          definition = %{F.definition() | metadata: %{items: data}}
          {:ok, document, registry} = Codec.encode(definition)
          {definition, document, registry}
        end,
        fn {definition, _document, _registry} ->
          case operation do
            :derive ->
              with {:ok, entries} <- Codec.registry_entries(definition),
                   do: Registry.derive(entries)

            :encode ->
              Codec.encode(definition)
          end
        end,
        fn result -> F.equal!(elem(result, 0), :ok) end
      )
      |> Map.put(:verify, fn {definition, document, registry}, result ->
        case operation do
          :derive ->
            F.equal!(result, {:ok, registry})

          :encode ->
            F.equal!(result, {:ok, document, registry})
            F.equal!(Codec.decode(document, registry), {:ok, definition})
        end
      end)
    end
  end
end
