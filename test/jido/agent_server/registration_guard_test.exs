defmodule JidoTest.AgentServer.RegistrationGuardTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer.RegistrationGuard, as: Guard

  test "recovery stops an orphan before it reuses the Agent identity", c do
    {activation, activation_ref} = spawn_monitor(fn -> receive do: (:stop -> :ok) end)
    {owner, owner_ref} = spawn_monitor(fn -> receive do: (:stop -> :ok) end)

    on_exit(fn ->
      Process.exit(activation, :kill)
      Process.exit(owner, :kill)
    end)

    key = Guard.registry_key(unique_id(), nil)
    assert :ok = Guard.claim(c.jido, key, owner, activation)
    assert {:error, {:already_started, ^owner}} = Guard.claim(c.jido, key, self(), nil)
    assert Process.alive?(owner)

    Process.exit(activation, :kill)
    assert_receive {:DOWN, ^activation_ref, :process, ^activation, :killed}
    assert :ok = Guard.claim(c.jido, key, self(), nil)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :killed}
    assert :ok = Guard.claim(c.jido, key, self(), nil)
  end
end
