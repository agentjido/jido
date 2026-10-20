Code.require_file("support.ex", __DIR__)

defmodule JidoTest.InstanceOptionsTest do
  use ExUnit.Case, async: false
  use Covenant.Case, component: "jido.instance", async: false

  alias Jido.Instance.Options

  setup :ensure_namespace_registry

  defp ensure_namespace_registry(context),
    do: JidoTest.InstanceContractSupport.ensure_namespace_registry(context)

  @tag obligation: ["jido.instance.I1", "jido.instance.I4"]
  test "validation keeps exact defaults and accepts all boundary values" do
    name = unique_instance("defaults")
    assert {:ok, defaults} = Options.validate(name: name)
    assert defaults[:name] == name
    assert defaults[:max_tasks] == 1_000
    assert defaults[:persistence] == nil

    for max_tasks <- [0, :infinity], debug <- [nil, false, true, :verbose] do
      assert {:ok, validated} =
               Options.validate(
                 name: name,
                 otp_app: :jido,
                 namespace: "x",
                 debug: debug,
                 max_tasks: max_tasks,
                 agent_server: [turn_timeout: 10]
               )

      assert validated[:max_tasks] == max_tasks
      assert validated[:debug] == debug
      assert validated[:agent_server] == [turn_timeout: 10]
    end
  end

  @tag obligation: "jido.instance.I1"
  test "validation errors retain the rejected field" do
    name = unique_instance("invalid")

    invalid = [
      {:value, :invalid, :value, :invalid},
      {:unknown, [name: name, unknown: true], :keys, [:unknown]},
      {:name, [name: nil], :name, nil},
      {:otp_app, [name: name, otp_app: "jido"], :otp_app, "jido"},
      {:namespace, [name: name, namespace: ""], :namespace, ""},
      {:debug, [name: name, debug: :trace], :debug, :trace},
      {:max_tasks, [name: name, max_tasks: -1], :max_tasks, -1}
    ]

    for {_case, opts, key, value} <- invalid do
      assert {:error, error} = Options.validate(opts)
      assert Jido.Error.code(error) == :jido_instance_invalid_config
      assert Map.has_key?(error.details, key)
      assert error.details[key] == value
    end

    assert {:error, persistence_error} =
             Options.validate(name: name, persistence: :not_an_adapter)

    assert Jido.Error.code(persistence_error) == :jido_instance_invalid_config
    assert Map.has_key?(persistence_error.details, :reason)
  end

  defp unique_instance(label) do
    String.to_atom("jido_options_#{label}_#{System.unique_integer([:positive])}")
  end
end
