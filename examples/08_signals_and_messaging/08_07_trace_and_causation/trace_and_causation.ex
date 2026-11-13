defmodule Jido.Examples.Signals.TraceAndCausation do
  alias Jido.Signal.Context
  alias Jido.Trace

  def journey do
    request = Jido.Signal.new!("examples.trace.request", %{}, source: "/client")
    root = Trace.new()
    {:ok, request} = Context.put_trace(request, root)
    {:ok, request} = Context.put(request, "jidocorrelationid", request.id)

    child = Jido.Signal.new!("examples.trace.child", %{}, source: "/coordinator")
    child_trace = Trace.child(root, causation_id: request.id)
    {:ok, child} = Context.put_trace(child, child_trace)
    {:ok, child} = Context.put(child, "jidocorrelationid", request.id)

    reply = Jido.Signal.new!("examples.trace.reply", %{}, source: "/worker")
    reply_trace = Trace.child(child_trace, causation_id: child.id)
    {:ok, reply} = Context.put_trace(reply, reply_trace)
    {:ok, reply} = Context.put(reply, "jidocorrelationid", request.id)

    %{
      request: request,
      child: child,
      reply: reply,
      trace_links: %{request: root, child: child_trace, reply: reply_trace}
    }
  end
end
