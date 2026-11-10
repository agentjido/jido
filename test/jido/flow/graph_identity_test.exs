defmodule Jido.Flow.GraphIdentityTest do
  use Covenant.Case, component: "jido_action.flow", async: true
  @moduletag obligation: "jido_action.flow.I10"
  alias Jido.Error.ValidationError
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Test.Action.Fixtures.Actions.{Add, EchoParamsAction}
  alias Jido.Test.Flow.Fixtures.InlineAuthoring
  alias Jido.Test.Flow.Fixtures.InlineParityFlow

  test "equal inline DSL, and direct graph data has the same semantic identity" do
    dsl = InlineParityFlow.flow()
    direct = InlineAuthoring.direct_flow!()
    assert {:ok, built} = Jido.Test.Flow.Builder.new(InlineAuthoring.data())
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

            Jido.Test.Flow.Builder.new!(
              name: "reference_identity",
              components: [
                Jido.Test.Flow.Component.step!(
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
          assert {:ok, document, registry} = Jido.Test.Flow.GeneratedCodec.encode(flow)
          assert {:ok, restored} = Jido.Test.Flow.Codec.decode(document, registry)
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
    first = Jido.Test.Flow.Component.step!(name: "first", action: Add)

    final =
      Jido.Test.Flow.Component.step!(
        name: "final",
        action: Add,
        params: %{value: Ref.result("first", :value)},
        needs: ["gate"]
      )

    gate = Jido.Test.Flow.Component.step!(name: "gate", action: Add)

    flow =
      Jido.Test.Flow.Builder.new!(
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
    assert {:error, %ValidationError{}} =
             Jido.Test.Flow.Builder.new(
               name: "unknown",
               components: [
                 Jido.Test.Flow.Component.step!(name: "one", action: Add, needs: ["missing"])
               ],
               output: Ref.result("one")
             )

    assert {:error, %ValidationError{message: message}} =
             Jido.Test.Flow.Builder.new(
               name: "cycle",
               components: [
                 Jido.Test.Flow.Component.step!(name: "one", action: Add, needs: ["two"]),
                 Jido.Test.Flow.Component.step!(name: "two", action: Add, needs: ["one"])
               ],
               output: Ref.result("one")
             )

    assert message =~ "cycle"
  end

  test "description and component metadata do not change semantic identity" do
    flows =
      for {description, meta} <- [{nil, %{}}, {"Display text", %{note: "authored"}}] do
        Jido.Test.Flow.Builder.new!(%{
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
    one = Jido.Test.Flow.Component.step!(name: "one", action: Add)
    two = Jido.Test.Flow.Component.step!(name: "two", action: Add)

    first =
      Jido.Test.Flow.Builder.new!(
        name: "identity",
        components: [one, two],
        output: %{one: Ref.result("one"), two: Ref.result("two")}
      )

    second =
      Jido.Test.Flow.Builder.new!(
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
            action: Jido.Test.Action.Fixtures.Actions.Add,
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
             "f021cb99d1bd929129210e7ab2f4456e4053e8e13cc5af3db5fd33132baa6b92"
  end
end
