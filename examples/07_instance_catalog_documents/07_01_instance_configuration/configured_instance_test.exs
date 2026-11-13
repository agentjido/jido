Code.require_file("configured_instance.ex", __DIR__)

defmodule Jido.Examples.ConfiguredInstanceTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Examples.ConfiguredInstance

  test "a host application starts one configured Jido supervision tree" do
    assert ConfiguredInstance.config(max_tasks: 8, activation: [idle_residency_timeout: 250]) ==
             [max_tasks: 8, activation: [idle_residency_timeout: 250]]

    pid =
      start_supervised!({ConfiguredInstance, max_tasks: 8, activation: [idle_residency_timeout: 250]})

    assert Process.whereis(ConfiguredInstance) == pid
    assert Supervisor.which_children(pid) |> length() == 7
  end

  test "invalid runtime configuration fails before the supervisor starts" do
    assert {:error, %Jido.Error.ValidationError{details: %{code: :jido_instance_invalid_config}}} =
             Jido.start_link(name: :not_started, max_tasks: -1)

    refute Process.whereis(:not_started)
  end
end
