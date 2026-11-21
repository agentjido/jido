Code.require_file("human_review.ex", __DIR__)

defmodule Jido.Examples.Guardrails.HumanReviewTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Durable
  alias Jido.Durable.Status
  alias Jido.Examples.Guardrails.HumanReview

  test "a durable approval resumes the Flow once" do
    jido = start_durable_jido()

    {:ok, request} =
      Jido.Signal.new(
        "examples.guardrails.review.requested",
        %{request_id: "review-1", content_digest: "sha256:abc"},
        source: "/examples/guardrails"
      )

    assert {:ok, %Status{state: :waiting, waits: [%{id: wait_id}], ref: ref}} =
             Durable.start(jido, HumanReview, request, now: 1_000)

    {:ok, approval} =
      Jido.Signal.new(
        "examples.guardrails.review.approved",
        %{request_id: "review-1", reviewer: "operator-7"},
        source: "/examples/guardrails"
      )

    assert {:ok, %Status{state: :completed}} =
             Durable.signal(jido, ref, wait_id, approval, now: 2_000)

    assert {:ok,
            %{
              request_id: "review-1",
              content_digest: "sha256:abc",
              status: :approved,
              evidence: %{request_id: "review-1", reviewer: "operator-7"}
            }} = Durable.result(jido, ref)

    assert {:ok, %Status{state: :completed, waits: []}} =
             Durable.signal(jido, ref, wait_id, approval, now: 3_000)

    assert {:ok, %{status: :approved}} = Durable.result(jido, ref)
  end

  defp start_durable_jido do
    suffix = System.unique_integer([:positive])
    jido = :"guardrail_human_review_#{suffix}"
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, "Store#{suffix}")}

    start_supervised!(
      {Jido, name: jido, namespace: "examples/guardrails/human-review/#{suffix}", persistence: persistence},
      id: jido
    )

    jido
  end
end
