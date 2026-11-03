defmodule Jido.AgentServer.Directive.ProcessStart do
  use Jido.Agent.Directive, built_in: true
  alias Jido.Joi
  @moduledoc "Starts one untracked process under the Jido instance supervisor."

  @schema Joi.struct(
            __MODULE__,
            %{child_spec: Joi.any(description: "OTP child specification")},
            coerce: true
          )

  @typedoc "A request to start one independent OTP child under the Jido instance."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
