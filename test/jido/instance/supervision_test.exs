defmodule Jido.Instance.SupervisionTest do
  use Jido.Test.Case, async: false
  use Covenant.Case, component: "jido.instance", async: false

  setup :ensure_namespace_registry

  defp ensure_namespace_registry(context),
    do: Jido.Test.Instance.ContractSupport.ensure_namespace_registry(context)

  describe "Jido supervisor" do
    @tag obligation: "jido.instance.I2"
    test "starts a Jido instance supervisor", %{jido: jido} do
      assert is_pid(Process.whereis(jido))
    end

    @tag obligation: "jido.instance.I1"
    test "requires :name option" do
      assert {:error, %Jido.Error.ValidationError{}} = Jido.start_link([])
    end

    @tag obligation: ["jido.instance.I1", "jido.instance.I2"]
    test "can be used as a child spec" do
      name = :"test_jido_#{System.unique_integer([:positive])}"
      spec = Jido.child_spec(name: name)
      assert spec.id == name
      assert spec.type == :supervisor
      assert spec.shutdown == 10_000
    end

    @tag obligation: "jido.instance.I2"
    test "starts TaskSupervisor as child", %{jido: jido} do
      task_sup = Jido.Instance.Names.task_supervisor(jido)
      assert Process.whereis(task_sup) != nil

      {:ok, task} = Task.Supervisor.start_child(task_sup, fn -> :ok end)
      assert is_pid(task)
    end

    @tag obligation: "jido.instance.I2"
    test "starts Registry as child", %{jido: jido} do
      reg = Jido.Instance.Names.registry(jido)
      assert Process.whereis(reg) != nil

      {:ok, _} = Registry.register(reg, "test_key", :test_value)
      assert [{registered_pid, :test_value}] = Registry.lookup(reg, "test_key")
      assert registered_pid == self()

      Registry.unregister(reg, "test_key")
    end

    @tag obligation: "jido.instance.I2"
    test "starts AgentSupervisor (DynamicSupervisor) as child", %{jido: jido} do
      agent_sup = Jido.Instance.Names.agent_supervisor(jido)
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
