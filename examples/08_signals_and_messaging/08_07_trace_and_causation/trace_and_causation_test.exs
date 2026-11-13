Code.require_file("trace_and_causation.ex", __DIR__)

defmodule Jido.Examples.Signals.TraceAndCausationTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Signals.TraceAndCausation
  alias Jido.Signal.Context

  test "keeps one trace and correlation ID across child work and reply" do
    journey = TraceAndCausation.journey()
    request_trace = Context.get_trace(journey.request)
    child_trace = Context.get_trace(journey.child)
    reply_trace = Context.get_trace(journey.reply)

    assert child_trace.trace_id == request_trace.trace_id
    assert child_trace.span_id == journey.trace_links.child.span_id
    assert journey.trace_links.child.parent_span_id == request_trace.span_id
    assert child_trace.causation_id == journey.request.id

    assert reply_trace.trace_id == request_trace.trace_id
    assert reply_trace.span_id == journey.trace_links.reply.span_id
    assert journey.trace_links.reply.parent_span_id == child_trace.span_id
    assert reply_trace.causation_id == journey.child.id

    correlation = Context.get(journey.request, "jidocorrelationid")

    assert Enum.all?(
             [journey.request, journey.child, journey.reply],
             &(Context.get(&1, "jidocorrelationid") == correlation)
           )
  end
end
