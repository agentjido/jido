defmodule Jido.Flow.CompoundPolicyTest do
  use ExUnit.Case, async: true

  require Jido.Authoring.Limits

  alias Jido.Flow
  alias Jido.Flow.Ref

  defmodule Echo do
    use Jido.Action, name: "flow_compound_policy_echo"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule AuthoredMap do
    use Jido.Flow, name: "flow_compound_complete_policy"

    alias Jido.Flow.CompoundPolicyTest.Echo

    flow do
      map("work",
        collection: [],
        action: Echo,
        params: %{},
        policy: %{timeout_ms: 250, retry: %{max_attempts: 2, delay_ms: 10}}
      )

      output(result("work"))
    end
  end

  test "Map owns its item error policy" do
    assert_nested_policy_error(%{
      type: :map,
      collection: Ref.input(:items),
      call: collect_call(),
      on_error: :collect_errors
    })
  end

  test "Parallel owns its shared error policy" do
    assert_nested_policy_error(%{
      type: :parallel,
      actions: [{"one", collect_call()}],
      on_error: :collect_errors
    })
  end

  test "Reduce supports fail-fast body calls only" do
    assert_nested_policy_error(%{
      type: :reduce,
      collection: Ref.input(:items),
      initial: %{},
      call: collect_call()
    })
  end

  test "Iterate supports fail-fast body calls only" do
    assert_nested_policy_error(%{
      type: :iterate,
      state_schema: [],
      initial: %{},
      repeat: 1,
      call: collect_call()
    })
  end

  test "Choice supports fail-fast selected calls only" do
    assert_nested_policy_error(%{
      type: :choice,
      options: [{"one", true, collect_call()}],
      fallback: Echo
    })

    assert_nested_policy_error(%{
      type: :choice,
      options: [{"one", true, Echo}],
      fallback: collect_call()
    })
  end

  test "compound Action shorthand keeps one complete call policy" do
    policy = %{timeout_ms: 250, retry: %{max_attempts: 2, delay_ms: 10}}

    for form <- compound_forms(policy) do
      flow =
        Flow.new!(%{
          name: "compound_complete_policy",
          forms: %{work: form},
          output: Ref.result(:work)
        })

      assert flow.forms["work"].call.policy == %{
               timeout_ms: 250,
               retry: %{
                 max_attempts: 2,
                 backoff: :fixed,
                 base_delay_ms: 10,
                 max_delay_ms: 10
               }
             }
    end
  end

  test "DSL, map, and Codec use the same complete compound call policy" do
    policy = %{timeout_ms: 250, retry: %{max_attempts: 2, delay_ms: 10}}

    from_map =
      Flow.new!(%{
        name: "flow_compound_complete_policy",
        forms: %{
          work: %{
            type: :map,
            collection: [],
            action: Echo,
            params: %{},
            policy: policy
          }
        },
        output: Ref.result(:work)
      })

    registry =
      Jido.Authoring.Registry.new!(%{
        {"actions/echo", 1} => {:action, Echo},
        {"schemas/empty", 1} => {:schema, []}
      })

    assert AuthoredMap.flow() == from_map
    assert {:ok, document} = Jido.Flow.Codec.encode_document(from_map, registry)
    assert {:ok, ^from_map} = Jido.Flow.Codec.decode_document(document, registry)
  end

  test "compound Action shorthand rejects an invalid complete call policy" do
    policy = %{retry: %{max_attempts: 0}}

    for form <- compound_forms(policy) do
      assert {:error, error} =
               Flow.new(%{
                 name: "invalid_compound_complete_policy",
                 forms: %{work: form},
                 output: Ref.result(:work)
               })

      assert error.details.reason == :invalid_call_policy
    end
  end

  test "call policy durations use the shared authoring duration limit" do
    maximum = Jido.Authoring.Limits.maximum_duration_ms()

    assert {:ok, %{timeout_ms: ^maximum}} =
             Jido.Flow.CallPolicy.normalize(%{timeout_ms: maximum})

    for policy <- [
          %{timeout_ms: maximum + 1},
          %{retry: %{max_attempts: 2, delay_ms: maximum + 1}},
          %{
            retry: %{
              max_attempts: 2,
              backoff: :exponential,
              base_delay_ms: 1,
              max_delay_ms: maximum + 1
            }
          }
        ] do
      assert {:error, error} =
               Flow.new(%{
                 name: "bounded_policy",
                 forms: %{work: %{type: :call, action: Echo, policy: policy}},
                 output: Ref.result(:work)
               })

      assert error.details.reason == :invalid_call_policy
    end
  end

  defp assert_nested_policy_error(form) do
    assert {:error, error} =
             Flow.new(%{
               name: "invalid_compound_policy",
               forms: %{work: form},
               output: Ref.result(:work)
             })

    assert error.details.reason == :nested_on_error
    assert error.details.on_error == :collect_errors
  end

  defp collect_call do
    %{
      type: :call,
      action: Echo,
      params: %{},
      on_error: :collect_errors
    }
  end

  defp compound_forms(policy) do
    [
      %{
        type: :map,
        collection: [],
        action: Echo,
        policy: policy
      },
      %{
        type: :reduce,
        collection: [],
        initial: %{},
        action: Echo,
        policy: policy
      },
      %{
        type: :iterate,
        state_schema: [],
        initial: %{},
        repeat: 1,
        action: Echo,
        policy: policy
      }
    ]
  end
end
