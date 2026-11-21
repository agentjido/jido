defmodule Jido.Examples.Signals.SignalSchemaAndContext.TenantRequest do
  use Jido.Signal,
    type: "examples.requests.created",
    default_source: "/examples/requests",
    schema:
      Jido.Joi.object(%{
        request_id: Jido.Joi.string() |> Jido.Joi.min(1),
        operation: Jido.Joi.enum([:read, :write])
      })

  def new_for_tenant!(data, tenant_id) do
    signal = new!(data)
    {:ok, signal} = Jido.Signal.Context.put(signal, "tenantid", tenant_id)
    signal
  end
end
