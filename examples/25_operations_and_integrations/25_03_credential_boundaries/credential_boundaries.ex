defmodule Jido.Examples.Operations.CredentialPreflight do
  @moduledoc "Checks credential availability without returning credential material."

  alias Jido.Joi

  use Jido.Action,
    name: "operations_credential_preflight",
    schema:
      Joi.object(
        %{
          provider: Joi.enum([:example_ai]),
          tenant: Joi.string()
        },
        unrecognized_keys: :error
      ),
    output_schema:
      Joi.object(%{
        provider: Joi.string(),
        tenant: Joi.string(),
        ready: Joi.boolean(),
        reason: Joi.string() |> Joi.nullable()
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
