defmodule Jido.InstanceHelpersTest do
  use JidoTest.Case, async: false

  test "script startup and shutdown are idempotent", %{jido: jido} do
    name = Module.concat(jido, Script)
    on_exit(fn -> Jido.stop(name) end)
    assert {:ok, pid} = Jido.start(name: name)
    assert {:ok, ^pid} = Jido.start(name: name)
    ref = Process.monitor(pid)
    assert :ok = Jido.stop(name)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert :ok = Jido.stop(name)
  end

  test "default debug helpers set and clear the default instance overrides" do
    instance = Jido.default_instance()
    previous = :persistent_term.get({:jido_debug, instance}, nil)

    on_exit(fn ->
      if previous,
        do: :persistent_term.put({:jido_debug, instance}, previous),
        else: Jido.Debug.disable(instance)
    end)

    assert instance == Jido.Default
    assert :ok = Jido.debug(:on)
    assert Jido.debug() == :on
    assert :ok = Jido.debug(:verbose, redact: false)
    assert Jido.Debug.override(instance, :redact_sensitive) == false
    assert :ok = Jido.debug(:off)
    assert Jido.debug() == :off
  end

  test "invalid parent bindings are rejected and missing metadata is normalized", %{jido: jido} do
    for binding <- [:invalid, %{parent_id: 42, tag: :child}] do
      assert :ok = Jido.RuntimeStore.put(jido, :agent_relationships, "child", binding)
      assert :error = Jido.agent_parent_binding(jido, "child")
    end

    binding = %{parent_id: "parent", tag: :child, meta: :invalid}
    assert :ok = Jido.RuntimeStore.put(jido, :agent_relationships, "child", binding)

    assert {:ok, %{parent_id: "parent", parent_partition: nil, tag: :child, meta: %{}}} =
             Jido.agent_parent_binding(jido, "child")

    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    assert {:error, :not_found} = Jido.stop_agent(jido, pid)
  end
end
