defmodule Jido.Flow.WaitTest do
  use ExUnit.Case, async: true

  require Jido.Authoring.Limits

  alias Jido.Authoring.Registry
  alias Jido.Flow
  alias Jido.Flow.{Codec, Ref}

  defmodule Authored do
    use Jido.Flow,
      name: "wait_for_decision"

    flow do
      await("approved",
        event: "order.approved",
        match: %{order_id: input(:order_id)}
      )

      timer("expired", after_ms: 60_000, needs: ["approved"])

      selection "decision" do
        await("accepted", event: "order.accepted", match: %{order_id: input(:order_id)})
        await("rejected", event: "order.rejected")
        timer("timed_out", after_ms: 86_400_000)
      end

      output(result("decision"))
    end
  end

  test "Await, Timer, and Selection normalize to the same canonical Wait form" do
    from_dsl = Authored.flow()
    from_map = wait_flow()
    registry = registry()

    assert {:ok, document} = Codec.encode_document(from_map, registry)
    assert {:ok, from_json} = Codec.decode_document(document, registry)

    assert from_dsl == from_map
    assert from_json == from_map

    assert Enum.all?(document["forms"], fn [_id, form, _needs] ->
             form["type"] == "wait"
           end)
  end

  test "keeps Wait clauses inside named graph forms" do
    flow = wait_flow()

    assert %Jido.Flow.Form.Wait{clauses: approved_clauses} = flow.forms["approved"]

    assert approved_clauses == [
             {:event, "approved", "order.approved", %{order_id: Ref.input(:order_id)}}
           ]

    assert %Jido.Flow.Form.Wait{clauses: [{:timer, "expired", 60_000}]} =
             flow.forms["expired"]

    assert flow.graph.dependencies["expired"] == %{data: [], control: ["approved"]}
    assert Map.keys(flow.graph.dependencies) == ["approved", "decision", "expired"]
  end

  test "includes event match references as data dependencies" do
    flow =
      Flow.new!(%{
        name: "wait_dependencies",
        forms: %{
          order: {__MODULE__.Noop, %{}},
          approved: %{
            type: :wait,
            clauses: [
              {:event, "approved", "order.approved", %{id: Ref.result(:order, :id)}}
            ]
          }
        },
        output: Ref.result(:approved)
      })

    assert {:ok, dependencies} = Flow.dependencies(flow)
    assert dependencies["approved"].data == ["order"]
  end

  defmodule Noop do
    use Jido.Action, name: "flow_wait_noop"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  test "rejects empty clauses, duplicate names, invalid matches, and invalid delays" do
    assert {:error, empty} = wait_with([])
    assert empty.details.reason == :empty_clauses

    assert {:error, duplicate} =
             wait_with([
               {:event, "same", "one", %{}},
               {:timer, "same", 1}
             ])

    assert duplicate.details.reason == :duplicate_clause

    assert {:error, match} = wait_with([{:event, "event", "order.event", true}])
    assert match.details.reason == :match

    assert {:error, delay} = wait_with([{:timer, "later", -1}])
    assert delay.details.reason == :delay

    maximum = Jido.Authoring.Limits.maximum_duration_ms()
    assert {:ok, _flow} = wait_with([{:timer, "latest", maximum}])
    assert {:error, too_long} = wait_with([{:timer, "later", maximum + 1}])
    assert too_long.details.reason == :delay
    assert too_long.details.maximum_duration_ms == maximum
  end

  test "rejects metadata that the Wait form cannot retain" do
    module = Module.concat(__MODULE__, "Metadata#{System.unique_integer([:positive])}")

    quoted =
      quote do
        defmodule unquote(module) do
          use Jido.Flow,
            name: "wait_metadata"

          flow do
            timer("later", after_ms: 1, meta: %{})
            output(result("later"))
          end
        end
      end

    assert_raise Spark.Error.DslError, ~r/unknown options.*meta/, fn ->
      Code.compile_quoted(quoted)
    end
  end

  defp wait_flow do
    Flow.new!(%{
      name: "wait_for_decision",
      forms: %{
        approved: %{
          type: :wait,
          clauses: [
            {:event, "approved", "order.approved", %{order_id: Ref.input(:order_id)}}
          ]
        },
        expired: %{
          type: :wait,
          clauses: [{:timer, "expired", 60_000}]
        },
        decision: %{
          type: :wait,
          clauses: [
            {:event, "accepted", "order.accepted", %{order_id: Ref.input(:order_id)}},
            {:event, "rejected", "order.rejected", %{}},
            {:timer, "timed_out", 86_400_000}
          ]
        }
      },
      needs: %{expired: ["approved"]},
      output: Ref.result(:decision)
    })
  end

  defp wait_with(clauses) do
    Flow.new(%{
      name: "invalid_wait",
      forms: %{wait: %{type: :wait, clauses: clauses}},
      output: Ref.result(:wait)
    })
  end

  defp registry do
    Registry.new!(%{
      {"atoms/order_id", 1} => {:atom, :order_id},
      {"schemas/empty", 1} => {:schema, []}
    })
  end
end
