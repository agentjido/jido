defmodule Jido.Authoring.SharedModuleTest do
  use Covenant.Case, component: "jido_action.action", async: true

  alias Jido.{Exec, Flow, Instruction}
  alias Jido.Flow.Ref

  defmodule Echo do
    use Jido.Action,
      name: "shared_echo",
      description: "Returns its input",
      schema: Zoi.object(%{value: Zoi.integer()}, unrecognized_keys: :preserve),
      output_schema: Zoi.object(%{value: Zoi.integer()}, unrecognized_keys: :preserve)

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule EchoFlow do
    use Jido.Flow,
      name: "shared_echo_flow",
      description: "Returns its input through a Flow",
      schema: Zoi.object(%{value: Zoi.integer()}, unrecognized_keys: :preserve),
      output_schema: Zoi.object(%{value: Zoi.integer()}, unrecognized_keys: :preserve)

    flow do
      step "echo", action: Echo, params: input()
      output result("echo")
    end
  end

  defmodule PreparedFlow do
    use Jido.Flow,
      name: "shared_prepared_flow",
      schema: Zoi.object(%{value: Zoi.integer()}, unrecognized_keys: :preserve),
      output_schema:
        Zoi.object(%{value: Zoi.integer()}, unrecognized_keys: :preserve)
        |> Zoi.transform({Jido.Authoring.SharedModuleTest, :observe_output, []})

    @impl Jido.Action
    def on_before_validate_params(params) do
      send(params.observer, :prepared_input)
      {:ok, Map.update!(params, :value, &(&1 + 1))}
    end

    flow do
      step "echo", action: Echo, params: input()
      output result("echo")
    end
  end

  @tag obligation: ["jido_action.action.I1", "jido_action.action.I2"]
  test "Action and Flow modules share the Action contract and retain distinct kinds" do
    for {module, kind} <- [{Echo, :action}, {EchoFlow, :flow}] do
      assert module.__info__(:attributes)[:behaviour] == [Jido.Action]
      assert module.__jido_authoring_kind__() == kind
      assert {:ok, %Instruction{kind: ^kind, target: ^module}} = Instruction.resolve(module)
      assert :ok = Instruction.validate(module)
    end
  end

  @tag obligation: "jido_action.action.I1"
  test "shared metadata descriptions preserve schemas and distinguish module kinds" do
    for {module, kind} <- [{Echo, "action"}, {EchoFlow, "flow"}] do
      json = module.authoring_contract()
      assert json["kind"] == kind
      assert json["name"] == module.name()
      assert json["description"] == module.description()
      assert json["input_schema"]["properties"]["value"]["type"] == "integer"
      assert json["output_schema"]["properties"]["value"]["type"] == "integer"
      assert Jason.decode!(Jason.encode!(json)) == json
      assert module.schema() == Echo.schema()
      assert module.output_schema() == Echo.output_schema()
    end
  end

  @tag obligation: "jido_action.action.I1"
  test "Flow validation runs once at each boundary with native child steps" do
    input = %{value: 1, observer: self()}

    for concurrency <- [1, 4] do
      assert Exec.run(PreparedFlow, input, %{}, max_concurrency: concurrency) ==
               {:ok, %{value: 2, observer: self()}}

      assert_received :prepared_input
      assert_received :validated_output
      refute_received :prepared_input
      refute_received :validated_output
    end

    assert {:ok, workflow} = Exec.compile(PreparedFlow)
    assert %Jido.Exec.Node.Action{} = Runic.Workflow.get_component(workflow, "echo")
  end

  @tag obligation: "jido_action.action.I1"
  test "a shared Flow target stays native when nested and bound as an Instruction" do
    parent =
      Flow.new!(%{
        name: "shared_parent",
        components: [%{kind: :subflow, name: "child", flow: EchoFlow, params: Ref.input([])}],
        output: Ref.result("child")
      })

    assert Exec.run(Instruction.new!(target: EchoFlow, params: %{value: 3})) == {:ok, %{value: 3}}
    assert Exec.run(parent, %{value: 3}) == {:ok, %{value: 3}}
    assert EchoFlow.run(%{value: 3}, %{}) == {:ok, %{value: 3}}
  end

  @tag obligation: "jido_action.action.I1"
  test "shared Flow modules do not become Action targets in component fields" do
    for component <- [
          %{kind: :step, name: "child", action: EchoFlow, params: %{value: 1}},
          %{kind: :map, name: "child", action: EchoFlow, collection: [], params: %{value: 1}}
        ] do
      flow =
        Flow.new!(%{name: "wrong_kind", components: [component], output: Ref.result("child")})

      assert {:error, error} = Exec.compile(flow)
      assert error.details.actual == :flow
      assert error.details.expected == :action
    end
  end

  @tag obligation: "jido_action.action.I2"
  test "shared configuration evaluates module options and schemas once" do
    for kind <- [:action, :flow] do
      module = Module.concat(__MODULE__, "Counted#{kind}#{System.unique_integer([:positive])}")

      on_exit(fn ->
        :code.purge(module)
        :code.delete(module)
        :code.purge(module)
      end)

      using = if kind == :action, do: Jido.Action, else: Jido.Flow

      body =
        if kind == :action do
          quote do
            @impl Jido.Action
            def run(params, _context), do: {:ok, params}
          end
        else
          quote do
            flow do
              step "echo", action: Jido.Authoring.SharedModuleTest.Echo, params: input()
              output result("echo")
            end
          end
        end

      Module.create(
        module,
        quote do
          use unquote(using), Jido.Authoring.SharedModuleTest.counted_options()
          unquote(body)
        end,
        Macro.Env.location(__ENV__)
      )

      assert_received :built_options
      refute_received :built_options
      assert_received :built_schema
      refute_received :built_schema
      assert {:ok, %{value: 1}} = module.validate_params(%{value: 1})
      assert module.schema() == module.schema()
      assert module.authoring_contract() == module.authoring_contract()
      refute_received :built_schema
    end
  end

  def counted_options do
    send(self(), :built_options)
    send(self(), :built_schema)
    [name: "counted_shared", schema: Zoi.object(%{value: Zoi.integer()})]
  end

  def observe_output(output, _opts) do
    send(output.observer, :validated_output)
    output
  end
end
