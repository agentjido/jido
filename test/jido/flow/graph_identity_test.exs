defmodule Jido.Flow.GraphIdentityTest do
  use Covenant.Case, component: "jido_action.flow", async: true
  @moduletag obligation: "jido_action.flow.I10"
  alias Jido.Flow.Error.InvalidDefinitionError
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.Actions.{Add, EchoParamsAction}
  alias JidoActionTest.Fixtures.InlineAuthoring
  alias JidoActionTest.Fixtures.InlineParityFlow

  test "equal inline DSL, and direct graph data has the same semantic identity" do
    dsl = InlineParityFlow.flow()
    direct = InlineAuthoring.direct_flow!()
    assert {:ok, built} = JidoActionTest.FlowBuilder.new(InlineAuthoring.data())
    assert {:ok, identity} = Flow.semantic_identity(dsl)
    assert %{version: 1, algorithm: :sha256, digest: digest, uuid: uuid} = identity
    assert is_binary(digest)
    assert is_binary(uuid)
    assert Flow.Identity.semantic_digest(dsl) == digest
    assert Flow.semantic_identity(direct) == {:ok, identity}
    assert Flow.semantic_identity(built) == {:ok, identity}
  end

  for field <- [:output, :params] do
    test "identity distinguishes references from literal maps in #{field}" do
      ref = Ref.input([])
      literal = %{source: ref.source, component: ref.component, path: ref.path}

      for {reference, data} <- [
            {ref, literal},
            {%{nested: ref}, %{nested: literal}},
            {Jido.Expr.new!(:==, [ref, %{value: 42}]), Jido.Expr.new!(:==, [literal, %{value: 42}])}
          ] do
        flows =
          for expression <- [reference, data] do
            params =
              if unquote(field) == :params do
                %{data: expression}
              else
                %{}
              end

            output =
              if unquote(field) == :output do
                %{data: expression}
              else
                Ref.result("echo")
              end

            JidoActionTest.FlowBuilder.new!(
              name: "reference_identity",
              components: [
                JidoActionTest.FlowComponent.step!(
                  name: "echo",
                  action: EchoParamsAction,
                  params: params
                )
              ],
              output: output
            )
          end

        [reference_flow, literal_flow] = flows
        refute Flow.semantic_identity(reference_flow) == Flow.semantic_identity(literal_flow)
        assert {:ok, reference_result} = Jido.Exec.run(reference_flow, %{value: 42})
        assert {:ok, literal_result} = Jido.Exec.run(literal_flow, %{value: 42})
        refute reference_result == literal_result

        refute workflow_log(reference_flow) == workflow_log(literal_flow)

        for flow <- flows do
          assert {:ok, document, registry} = JidoActionTest.GeneratedFlowCodec.encode(flow)
          assert {:ok, restored} = JidoActionTest.FlowCodec.decode(document, registry)
          assert restored == flow
          assert Flow.semantic_identity(restored) == Flow.semantic_identity(flow)

          assert {:flow, digest, nil, "echo"} =
                   Jido.Exec.compile!(flow)
                   |> Runic.Workflow.get_component("echo")
                   |> Map.fetch!(:id)

          assert digest == Flow.Identity.semantic_digest(flow)
        end
      end
    end
  end

  test "author order, reference order, and effective order stay separate" do
    first = JidoActionTest.FlowComponent.step!(name: "first", action: Add)

    final =
      JidoActionTest.FlowComponent.step!(
        name: "final",
        action: Add,
        params: %{value: Ref.result("first", :value)},
        needs: ["gate"]
      )

    gate = JidoActionTest.FlowComponent.step!(name: "gate", action: Add)

    flow =
      JidoActionTest.FlowBuilder.new!(
        name: "dependencies",
        components: [first, final, gate],
        output: Ref.result("final")
      )

    assert Map.keys(flow.components) |> Enum.sort() == ["final", "first", "gate"]

    assert {:ok, %{"final" => %{needs: ["gate"], references: ["first"], effective: ["first", "gate"]}}} =
             Flow.dependencies(flow)

    assert final.needs == ["gate"]
  end

  test "unknown references and cycles fail without changing author data" do
    assert {:error, %InvalidDefinitionError{}} =
             JidoActionTest.FlowBuilder.new(
               name: "unknown",
               components: [
                 JidoActionTest.FlowComponent.step!(name: "one", action: Add, needs: ["missing"])
               ],
               output: Ref.result("one")
             )

    assert {:error, %InvalidDefinitionError{message: message}} =
             JidoActionTest.FlowBuilder.new(
               name: "cycle",
               components: [
                 JidoActionTest.FlowComponent.step!(name: "one", action: Add, needs: ["two"]),
                 JidoActionTest.FlowComponent.step!(name: "two", action: Add, needs: ["one"])
               ],
               output: Ref.result("one")
             )

    assert message =~ "cycle"
  end

  test "description and component metadata do not change semantic identity" do
    flows =
      for {description, meta} <- [{nil, %{}}, {"Display text", %{note: "authored"}}] do
        JidoActionTest.FlowBuilder.new!(%{
          name: "metadata_identity",
          description: description,
          components: [
            %{kind: :step, name: "later", action: Add, needs: ["first"], meta: meta},
            %{kind: :step, name: "first", action: Add}
          ],
          output: Ref.result("later")
        })
      end

    [plain, annotated] = flows
    assert Flow.semantic_identity(plain) == Flow.semantic_identity(annotated)

    for flow <- flows do
      assert {:ok, identity} = Flow.semantic_identity(flow)
      assert {:ok, compiled} = Jido.Exec.compile(flow)
      assert {:flow, digest, nil, "first"} = Runic.Workflow.get_component(compiled, "first").id
      assert digest == identity.digest
    end
  end

  test "source order does not change semantic identity" do
    one = JidoActionTest.FlowComponent.step!(name: "one", action: Add)
    two = JidoActionTest.FlowComponent.step!(name: "two", action: Add)

    first =
      JidoActionTest.FlowBuilder.new!(
        name: "identity",
        components: [one, two],
        output: %{one: Ref.result("one"), two: Ref.result("two")}
      )

    second =
      JidoActionTest.FlowBuilder.new!(
        name: "identity",
        components: [two, one],
        output: %{one: Ref.result("one"), two: Ref.result("two")}
      )

    assert first == second
    assert Flow.semantic_identity(first) == Flow.semantic_identity(second)
  end

  defp workflow_log(flow), do: flow |> Jido.Exec.compile!() |> Runic.Workflow.build_log()

  # Durable Runic component IDs derive from this digest. Erlang guarantees
  # deterministic term encoding only within one OTP release, so this fixed
  # value must hold on every OTP version in the test matrix.
  test "semantic identity is stable across supported OTP releases" do
    flow =
      Jido.Flow.new!(%{
        name: "identity_golden",
        components: [
          %{
            kind: :step,
            name: "add",
            action: JidoActionTest.Fixtures.Actions.Add,
            params: %{value: Jido.Flow.Ref.input(:value), amount: 1},
            needs: [],
            meta: %{owner: "ignored"}
          }
        ],
        output: %{
          total: Jido.Flow.Ref.result("add", :value),
          label: "sum",
          items: [1, 2.5, :ok, nil]
        }
      })

    assert Jido.Flow.Identity.semantic_digest(flow) ==
             "ade8660d53bdbe9ca59c97470987906e9e0da539e272cc6aeb1e0511e4d13a30"
  end
end
