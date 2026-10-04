defmodule JidoTest.Persistence.Conformance.RegistryTest do
  use ExUnit.Case, async: true

  @moduletag :persistence

  alias JidoTest.Persistence.Profiles

  test "every built-in persistence adapter has an active or explained profile" do
    discovered =
      :jido
      |> Application.spec(:modules)
      |> Enum.filter(&public_persistence_module?/1)
      |> Enum.filter(&persistence_adapter?/1)
      |> MapSet.new()

    assert discovered == Profiles.adapter_modules()

    for {_name, profile} <- Profiles.all() do
      assert profile.status == :active or is_binary(profile.reason)
    end
  end

  defp public_persistence_module?(module) do
    case module |> Atom.to_string() |> String.split(".") do
      ["Elixir", "Jido", "Persistence", _name] -> true
      _other -> false
    end
  end

  defp persistence_adapter?(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        Jido.Persistence.Adapter in List.wrap(module.module_info(:attributes)[:behaviour])

      {:error, _reason} ->
        false
    end
  end
end

for profile <- JidoTest.Persistence.Profiles.active(:local) do
  defmodule Module.concat(
              JidoTest.Persistence.Conformance.Local,
              Macro.camelize(to_string(profile))
            ) do
    use JidoTest.Persistence.Case, profile: profile
    use JidoTest.Persistence.Contracts.Store
    use JidoTest.Persistence.Contracts.Agent
    use JidoTest.Persistence.Contracts.Recovery
  end
end
