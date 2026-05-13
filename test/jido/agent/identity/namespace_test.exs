defmodule JidoTest.Agent.Identity.NamespaceTest do
  use ExUnit.Case, async: false

  test "core Jido application does not define Jido.Identity modules" do
    assert {:ok, modules} = :application.get_key(:jido, :modules)

    identity_modules =
      Enum.filter(modules, fn module ->
        module
        |> Atom.to_string()
        |> String.starts_with?("Elixir.Jido.Identity")
      end)

    assert identity_modules == []
  end

  test "a jido_identity-style package can own Jido.Identity beside core identity" do
    compiled =
      Code.compile_string("""
      defmodule Jido.Identity do
        defstruct [:principal_id]

        def new(principal_id), do: %__MODULE__{principal_id: principal_id}
      end
      """)

    on_exit(fn ->
      :code.purge(Jido.Identity)
      :code.delete(Jido.Identity)
    end)

    assert [{Jido.Identity, _bytecode}] = compiled

    assert %{__struct__: Jido.Identity, principal_id: "agent_123"} =
             apply(Jido.Identity, :new, ["agent_123"])

    assert %Jido.Agent.Identity{} = Jido.Agent.Identity.new()
  end
end
