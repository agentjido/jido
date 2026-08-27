defmodule Jido.Agent.Extension do
  @moduledoc """
  Defines the contract boundary for typed Agent extensions.

  The complete extension integration is added by the Agent extension layer.
  These callbacks keep extension-owned data separate from the root Agent.
  """

  @callback normalize(term()) :: {:ok, term()} | {:error, Exception.t()}
  @callback validate(term()) :: :ok | {:ok, term()} | {:error, Exception.t()}
  @callback validate_executable(term()) :: :ok | {:error, Exception.t()}
  @callback encode(term(), map()) :: {:ok, term()} | {:error, Exception.t()}
  @callback decode(term(), map()) :: {:ok, term()} | {:error, Exception.t()}
  @callback registry_values(term()) :: list()
  @callback compile(term(), map()) :: {:ok, term()} | {:error, Exception.t()}
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
