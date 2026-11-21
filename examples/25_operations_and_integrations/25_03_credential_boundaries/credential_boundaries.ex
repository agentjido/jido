defmodule Jido.Examples.Operations.CredentialPreflight do
  @moduledoc "Checks credential availability without returning credential material."

  use Jido.Action,
    name: "operations_credential_preflight",
    schema:
      Jido.Joi.object(
        %{
          provider: Jido.Joi.enum([:example_ai]),
          tenant: Jido.Joi.string()
        },
        unrecognized_keys: :error
      ),
    output_schema:
      Jido.Joi.object(%{
        provider: Jido.Joi.string(),
        tenant: Jido.Joi.string(),
        ready: Jido.Joi.boolean(),
        reason: Jido.Joi.string() |> Jido.Joi.nullable()
      })

  @impl true
  def run(%{provider: :example_ai, tenant: tenant}, context) do
    credential = get_in(context, [:runtime_environment, "EXAMPLE_AI_TOKEN"])

    {ready, reason} =
      if is_binary(credential) and byte_size(credential) >= 8,
        do: {true, nil},
        else: {false, "credential is missing or invalid"}

    {:ok, %{provider: "example_ai", tenant: tenant, ready: ready, reason: reason}}
  end
end
