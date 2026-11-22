defmodule Jido.Examples.Signals.SignalSchemaAndContext.TenantRequest do
  alias Jido.Joi

  use Jido.Signal,
    type: "examples.requests.created",
    default_source: "/examples/requests",
    schema:
      Joi.object(%{
        request_id: Joi.string() |> Joi.min(1),
        operation: Joi.enum([:read, :write])
      })

  def new_for_tenant!(data, tenant_id) do
    signal = new!(data)
    {:ok, signal} = Jido.Signal.Context.put(signal, "tenantid", tenant_id)
    signal
  end
end
