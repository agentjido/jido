defmodule Jido.Agent.Extension do
  @moduledoc """
  Defines the contract boundary for typed Agent extensions.

  An extension owns its declaration data and all processing for that data. Its
  callbacks never receive the root Agent. Version 1 extensions do not declare
  dependencies on other extensions.

  `encode/2` and `decode/2` receive the trusted Agent Registry. `compile/2`
  receives only the declaration metadata. A compile result is stored under
  the extension module in `Jido.Agent.Compiled.extension_plans`.

  The module returned by `spark_extension/0` can take part in Agent lowering
  when it exports `agent_extension/0` and `lower/1`. `agent_extension/0` must
  return this extension module. `lower/1` must return `{:ok, declaration}`,
  where `declaration` contains only `:data` and optional `:metadata` fields.
  """

  @callback normalize(term()) :: {:ok, term()} | {:error, Exception.t()}
  @callback validate(term()) :: :ok | {:error, Exception.t()}
  @callback validate_executable(term()) :: :ok | {:error, Exception.t()}
  @callback encode(term(), Jido.Agent.Registry.t()) ::
              {:ok, term()} | {:error, Exception.t()}
  @callback decode(term(), Jido.Agent.Registry.t()) ::
              {:ok, term()} | {:error, Exception.t()}
  @callback registry_values(term()) :: [{atom(), term()}]
  @callback compile(term(), Jido.Agent.Data.object()) ::
              {:ok, term()} | {:error, Exception.t()}
  @callback spark_extension() :: module() | nil

  @optional_callbacks normalize: 1,
                      validate: 1,
                      validate_executable: 1,
                      encode: 2,
                      decode: 2,
                      registry_values: 1,
                      compile: 2,
                      spark_extension: 0
end
