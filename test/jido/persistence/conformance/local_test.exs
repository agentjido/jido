defmodule Jido.Persistence.Conformance.RegistryTest do
  use ExUnit.Case, async: true

  @moduletag :persistence

  alias Jido.Test.Persistence.Profiles

  test "every built-in persistence adapter has an active or explained profile" do
    assert Profiles.discovered_adapter_modules() == Profiles.adapter_modules()

    for {_name, profile} <- Profiles.all() do
      assert profile.status == :active or is_binary(profile.reason)
    end
  end
end

for profile <- Jido.Test.Persistence.Profiles.active(:local) do
  defmodule Module.concat(
              Jido.Persistence.Conformance.Local,
              Macro.camelize(to_string(profile))
            ) do
    use Jido.Test.Persistence.Case, profile: profile
    use Jido.Test.Persistence.Contracts.Store
  end
end
