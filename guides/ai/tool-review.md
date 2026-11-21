# Tool Review

This guide makes a ReAct request wait for a person's decision before a tool runs. The wait is durable, so it survives a restart. Tool review needs an AgentServer with persistence, because a wait needs a host that can store it.

## Require review

Name the tools in `tool_policy.review`, or set `review_tools: true` to review every visible tool on that request. A review tool must also be visible, or the request returns an error.

```elixir
defmodule ToolReviewGuide.RefundOrder do
  use Jido.Action,
    name: "refund_order",
    description: "Refund one order",
    schema: Jido.Joi.object(%{order_id: Jido.Joi.string()})

  @impl true
  def run(%{order_id: order_id}, _context), do: {:ok, %{refunded: order_id}}
end

defmodule ToolReviewGuide.BillingAgent do
  use Jido.AI.Agent, name: "billing_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      tool_policy do
        review ["refund_order"]
        reason "Refunds need a manager"
      end
    end

    tools do
      action ToolReviewGuide.RefundOrder
    end
  end
end

defmodule ToolReviewGuide.LocalModel do
  @behaviour Jido.AI.InferenceClient

  @impl true
  def generate_text(model, context, _options) do
    {message, finish_reason} =
      case context |> ReqLLM.Context.to_list() |> List.last() do
        %{role: :tool} ->
          {ReqLLM.Context.assistant("The refund is done."), :stop}

        _user ->
          call = ReqLLM.ToolCall.new("call-1", "refund_order", ~s({"order_id":"ORD-77"}))
          {ReqLLM.Context.assistant("", tool_calls: [call]), :tool_calls}
      end

    {:ok,
     %ReqLLM.Response{
       id: "local",
       model: model,
       context: context,
       message: message,
       finish_reason: finish_reason,
       usage: %{input_tokens: 4, output_tokens: 3}
     }}
  end

  @impl true
  def evaluation_models, do: []

  for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks),
      {name, arity} not in [generate_text: 3, evaluation_models: 0] do
    @impl true
    def unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))),
      do: {:error, :not_supported}
  end
end
```

A request can narrow a `tool_policy` set on the Agent, but it cannot widen or remove it. A request that sends its own `tool_policy` keeps the Agent's review list:

| Field | Effect of a request value |
| --- | --- |
| `review` | Adds names to the Agent's list. A reviewed tool stays reviewed while it is selected. |
| `hidden` | Adds names to the Agent's list. |
| `visible` | Selects from the tools that the Agent leaves visible. |
| `requirement` | Applies only when the Agent's requirement is `:optional`. |

A request also cannot turn off `review_tools: true` set on the Agent.

## Know where review works

`cmd/3` and an AgentServer without persistence have no wait host. The request is blocked before any model call, and the tool cannot run.

```elixir
agent = ToolReviewGuide.BillingAgent.instantiate!(id: "direct-1")

{:ok, _agent, [%{signal: reply}]} =
  ToolReviewGuide.BillingAgent.cmd(
    agent,
    ToolReviewGuide.BillingAgent.request_signal!(%{input: "Refund order ORD-77."}),
    context: %{jido_ai_inference_client: ToolReviewGuide.LocalModel}
  )

%{
  status: :blocked,
  reason_code: :review,
  reason: "execution host does not support waits",
  model_calls: 0
} = reply.data
```

The check is on the host. Passing `jido_exec_capabilities` in the context does not get past it, because the execution layer controls that key.

## Start a durable Agent

Give the Jido instance persistence and give the Agent a long `turn_timeout`. [Make an Agent Durable](../durability/make-an-agent-durable.livemd) covers the options. Use `submit/3` so that your process can do other work while the request waits. `Jido.Persistence.File` keeps this example self-contained.

```elixir
review_dir = Path.join(System.tmp_dir!(), "tool-review-#{System.unique_integer([:positive])}")

Application.put_env(:jido, :ai_inference_client, ToolReviewGuide.LocalModel)
Process.register(self(), :billing_reviews)

{:ok, _instance} =
  Jido.start(name: ToolReviewGuide.Jido,
    namespace: "guides/tool-review",
    persistence: {Jido.Persistence.File, path: review_dir}
  )

{:ok, server} =
  Jido.start_agent(ToolReviewGuide.Jido, ToolReviewGuide.BillingAgent,
    id: "billing-1",
    turn_timeout: :infinity
  )

:ok = Jido.AgentServer.await_ready(server)

pending =
  Jido.AgentServer.submit(
    server,
    ToolReviewGuide.BillingAgent.request_signal!(%{input: "Refund order ORD-77."}),
    context: %{jido_ai_dispatch: {:named, target: {:name, :billing_reviews}, delivery_mode: :async}}
  )
```

## Tell the reviewer

The model call runs, and it requests the tool. A batch waits as one unit if any of its calls needs review. The Flow then publishes `jido.ai.review.requested` to the `:jido_ai_dispatch` target and opens the wait.

Durable Turn context must be portable, so the target is a registered name, not a PID. With a PID target, `await/2` returns a `Jido.Error.ValidationError` with the code `:non_portable_term`, and the request does not run.

```elixir
review =
  receive do
    {:signal, %{type: "jido.ai.review.requested"} = signal} -> signal.data
  after
    5_000 -> raise "no review request arrived"
  end

%{
  options: [:approved, :denied],
  policy_reason: "Refunds need a manager",
  tool_calls: [%{name: "refund_order", arguments: %{"order_id" => "ORD-77"}}]
} = review

true = review.expires_at_ms - review.timestamp_ms == 300_000
```

The expiry is fixed at 5 minutes. To change it, write your own review Flow.

## Find the wait

`Jido.AgentServer.status/2` lists open waits, even without a dispatch target. The wait has three options, and the two event options name the values a decision must match.

```elixir
find_wait = fn find_wait, attempts ->
  case Jido.AgentServer.status(server) do
    %{active: %{stage: :waiting}, waits: [wait]} -> wait
    _status when attempts > 0 ->
      Process.sleep(10)
      find_wait.(find_wait, attempts - 1)
  end
end

wait = find_wait.(find_wait, 500)

["approved", "denied", "expired"] = Enum.map(wait.options, & &1.name)
approved = Enum.find(wait.options, &(&1.name == "approved"))

"jido.ai.review.approved" = approved.event
true = approved.match.review_id == review.review_id
```

## Approve the call

A decision is a Signal with the option's event type. Its data must hold the option's `match` values. Add `actor_id` and `reason` for your audit trail. Jido records both.

`Jido.AgentServer.deliver_wait/4` rejects data that does not match.

```elixir
{:error, %Jido.Error.ValidationError{details: %{reason: :unmatched_input}}} =
  Jido.AgentServer.deliver_wait(
    server,
    wait.id,
    Jido.Signal.new!("jido.ai.review.approved", %{review_id: "forged"}, source: "/billing/reviews")
  )

decision = Map.merge(approved.match, %{actor_id: "manager-12", reason: "Damaged in transit"})

:ok =
  Jido.AgentServer.deliver_wait(
    server,
    wait.id,
    Jido.Signal.new!("jido.ai.review.approved", decision, source: "/billing/reviews")
  )

{:ok, reviewed_agent, [%{signal: approved_reply}]} = Jido.AgentServer.await(pending, 5_000)

%{status: :completed, output: "The refund is done.", tool_calls: 1} = approved_reply.data
[%{review: %{required: true, status: :approved}, output: %{"refunded" => "ORD-77"}}] = approved_reply.data.tool_attempts
```

The Thread now holds two `:ai_review` entries, one for the request and one for the decision.

```elixir
[requested, resolved] = Jido.Thread.filter_by_kind(reviewed_agent.state.session.thread, :ai_review)

"requested" = requested.payload["status"]
%{"status" => "approved", "decision" => %{"actor_id" => "manager-12", "reason" => "Damaged in transit"}} = resolved.payload
```

## Deny a call

A denial ends the request as `:blocked` with reason code `:review`. The tool does not run, and the model is not called again. An unanswered wait does the same with the reason `"tool review expired"` when the 5 minutes pass.

```elixir
pending =
  Jido.AgentServer.submit(
    server,
    ToolReviewGuide.BillingAgent.request_signal!(%{input: "Refund order ORD-78."})
  )

wait = find_wait.(find_wait, 500)
denied = Enum.find(wait.options, &(&1.name == "denied"))

:ok =
  Jido.AgentServer.deliver_wait(
    server,
    wait.id,
    Jido.Signal.new!("jido.ai.review.denied", denied.match, source: "/billing/reviews")
  )

{:ok, _agent, [%{signal: denied_reply}]} = Jido.AgentServer.await(pending, 5_000)

%{status: :blocked, reason_code: :review, reason: "tool use was denied", tool_calls: 0} = denied_reply.data

:ok = Jido.stop_agent(ToolReviewGuide.Jido, server)
:ok = Jido.stop(ToolReviewGuide.Jido)
Application.delete_env(:jido, :ai_inference_client)
Process.unregister(:billing_reviews)
File.rm_rf!(review_dir)
```

Messages from a request that ends `:blocked` stay out of later model context. See [Thread Projection](thread-projection.md).

## Survive a restart

The wait is part of the durable Turn. If the AgentServer hibernates or restarts, `Jido.thaw/4` restores it with the same wait ID, and you can deliver the decision to the restored server. A pending handle from before the restart returns an error, so read the result from the Agent's Session after the decision.

## Related

- [Durable Turns and Flows](../durability/durable-turns-and-flows.livemd)
- [Flow Waits](../flow-runtime/flow-waits.md)
- [Tools and Toolsets](tools-skills-and-toolsets.livemd)
