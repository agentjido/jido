defmodule Jido.Examples.Operations.AuthorizeOperation do
  @moduledoc "Applies application authorization before a sensitive operation."

  use Jido.Action,
    name: "operations_authorize_operation",
    schema:
      Jido.Joi.object(
        %{
          operation: Jido.Joi.enum([:read_status, :restart_service]),
          tenant: Jido.Joi.string()
        },
        unrecognized_keys: :error
      )

  @impl true
  def run(input, %{principal: %{tenant: tenant, roles: roles}}) do
    allowed? =
      input.tenant == tenant and
        (input.operation == :read_status or :operator in roles)

    if allowed?, do: {:ok, input}, else: {:error, :not_authorized}
  end

  def run(_input, _context), do: {:error, :not_authenticated}
end

defmodule Jido.Examples.Operations.SimulateAllowedOperation do
  @moduledoc "Simulates one allowlisted operation without invoking the OS."

  use Jido.Action, name: "operations_simulate_allowed_operation"

  @impl true
  def run(%{operation: operation, tenant: tenant}, _context) do
    {:ok, %{operation: Atom.to_string(operation), tenant: tenant, status: "simulated"}}
  end
end

defmodule Jido.Examples.Operations.SecureOperationFlow do
  @moduledoc "Authorizes one allowlisted application operation before execution."

  use Jido.Flow,
    name: "operations_secure_operation_flow",
    schema:
      Jido.Joi.object(
        %{
          operation: Jido.Joi.enum([:read_status, :restart_service]),
          tenant: Jido.Joi.string()
        },
        unrecognized_keys: :error
      )

  flow do
    step "authorize",
      action: Jido.Examples.Operations.AuthorizeOperation,
      params: %{operation: input(:operation), tenant: input(:tenant)}

    step "execute",
      action: Jido.Examples.Operations.SimulateAllowedOperation,
      params: result("authorize")

    output result("execute")
  end
end
