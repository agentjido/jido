defmodule JidoTest.SupervisorTest do
  use JidoTest.Case, async: true

  describe "Jido supervisor" do
    test "starts a Jido instance supervisor", %{jido: jido} do
      assert is_pid(Process.whereis(jido))
    end

    test "requires :name option" do
      assert_raise KeyError, ~r/:name/, fn ->
        Jido.start_link([])
      end
    end

    test "can be used as a child spec" do
      name = :"test_jido_#{System.unique_integer([:positive])}"
      spec = Jido.child_spec(name: name)
      assert spec.id == name
      assert spec.type == :supervisor
      assert spec.shutdown == 10_000
    end

    test "starts TaskSupervisor as child", %{jido: jido} do
      task_sup = Jido.task_supervisor_name(jido)
      assert Process.whereis(task_sup) != nil

      {:ok, task} = Task.Supervisor.start_child(task_sup, fn -> :ok end)
      assert is_pid(task)
    end

    test "starts Registry as child", %{jido: jido} do
      reg = Jido.registry_name(jido)
      assert Process.whereis(reg) != nil

      {:ok, _} = Registry.register(reg, "test_key", :test_value)
      assert [{registered_pid, :test_value}] = Registry.lookup(reg, "test_key")
      assert registered_pid == self()

      Registry.unregister(reg, "test_key")
    end

    test "starts AgentSupervisor (DynamicSupervisor) as child", %{jido: jido} do
      agent_sup = Jido.agent_supervisor_name(jido)
      assert Process.whereis(agent_sup) != nil

      assert DynamicSupervisor.count_children(agent_sup) == %{
               active: 0,
               specs: 0,
               supervisors: 0,
               workers: 0
             }
    end
  end
end
