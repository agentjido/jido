defmodule JidoTest.Actions.DirectivesTest do
  use JidoTest.Case, async: true
  alias Jido.Actions.Directives

  describe "EnqueueAction" do
    test "creates enqueue directive with params" do
      params = %{test_param: "value"}

      assert {:ok, %{}, directive} =
               Directives.EnqueueAction.run(%{action: :test_action, params: params}, %{})

      assert directive.action == :test_action
      assert directive.params == params
      assert directive.context == %{}
    end

    test "creates enqueue directive with default empty params" do
      assert {:ok, %{}, directive} = Directives.EnqueueAction.run(%{action: :test_action}, %{})
      assert directive.action == :test_action
      assert directive.params == %{}
    end
  end

  describe "RegisterAction" do
    test "creates register directive" do
      assert {:ok, %{}, directive} =
               Directives.RegisterAction.run(%{action_module: TestModule}, %{})

      assert directive.action_module == TestModule
    end
  end

  describe "DeregisterAction" do
    test "creates deregister directive" do
      assert {:ok, %{}, directive} =
               Directives.DeregisterAction.run(%{action_module: TestModule}, %{})

      assert directive.action_module == TestModule
    end

    test "prevents deregistering itself" do
      assert {:error, :cannot_deregister_self} =
               Directives.DeregisterAction.run(%{action_module: Directives.DeregisterAction}, %{})
    end
  end

  describe "Spawn" do
    test "creates spawn directive" do
      args = [1, 2, 3]
      assert {:ok, %{}, directive} = Directives.Spawn.run(%{module: TestModule, args: args}, %{})
      assert directive.module == TestModule
      assert directive.args == args
    end
  end

  describe "Kill" do
    test "creates kill directive" do
      pid = self()
      assert {:ok, %{}, directive} = Directives.Kill.run(%{pid: pid}, %{})
      assert directive.pid == pid
    end
  end

  describe "AddRoute" do
    test "creates add route directive" do
      path = "user.created"
      target = :process_user

      assert {:ok, %{}, directive} =
               Directives.AddRoute.run(%{path: path, target: target}, %{})

      assert directive.path == path
      assert directive.target == target
    end

    test "creates add route directive with instruction target" do
      path = "order.placed"
      target = %Jido.Instruction{action: :process_order, params: %{priority: :high}}

      assert {:ok, %{}, directive} =
               Directives.AddRoute.run(%{path: path, target: target}, %{})

      assert directive.path == path
      assert directive.target == target
    end
  end

  describe "RemoveRoute" do
    test "creates remove route directive" do
      path = "user.deleted"

      assert {:ok, %{}, directive} =
               Directives.RemoveRoute.run(%{path: path}, %{})

      assert directive.path == path
    end
  end
end
