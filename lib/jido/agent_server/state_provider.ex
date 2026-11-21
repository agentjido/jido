defmodule Jido.AgentServer.StateProvider do
  @moduledoc """
  An optional state source for a durable, module-defined Agent.

  Declare a provider with `state_provider Provider, options` in the Agent's
  `state` block. Its compile callback supplies the state schema and a static
  descriptor. The descriptor stays in the Agent module. An in-memory Agent
  command does not call the provider.

  The provider can use the trusted activation address and persistence profile.
  `open/5` owns the activation boundary. Call the supplied function to create
  or restore the Jido record. `refresh/3` runs before new work, but a durable
  continuation uses the state saved at its admission.

  `commit/5` must call the supplied function exactly once with the canonical
  candidate in the same transaction as its own writes. Return its payload
  only after the transaction commits. Return `{:error, {:rejected, reason}}`
  for an unchanged or rolled back write. Report uncertain commits with
  `{:error, :indeterminate}`. Jido publishes state and runs effects after
  a successful commit.
  """

  alias Jido.Agent
  alias Jido.Persistence.Config

  @type context :: %{address: Agent.Address.t(), persistence: Config.t()}
  @type result :: {:ok, term()} | {:error, term()}
  @type activation :: {:ok, Agent.t(), non_neg_integer(), non_neg_integer(), term(), map()} | {:error, term()}

  @callback compile_state!(term(), Macro.Env.t()) :: {Jido.Joi.schema(), term()}
  @callback open(term(), context(), :create | :restore, Agent.t(), (Agent.t() -> activation())) :: activation()
  @callback refresh(term(), context(), Agent.t()) :: {:ok, Agent.t()} | {:error, term()}
  @callback commit(term(), context(), Agent.t(), Agent.t(), (Agent.t() -> result())) :: result()

  @doc false
  def configured?(agent), do: declaration(agent) != nil

  @doc false
  def open(agent, context, mode, fun) do
    case declaration(agent) do
      nil -> fun.(agent)
      {provider, descriptor, _schema} -> provider.open(descriptor, context, mode, agent, fun)
    end
  end

  @doc false
  def refresh(agent, context) do
    case declaration(agent) do
      nil -> {:ok, agent}
      {provider, descriptor, _schema} -> provider.refresh(descriptor, context, agent)
    end
  end

  @doc false
  def commit(agent, %Agent{id: id, module: module} = candidate, context, fun) do
    case declaration(agent) do
      nil ->
        fun.(candidate)

      {provider, descriptor, _schema} ->
        save = fn
          %Agent{id: ^id, module: ^module, state: state} ->
            case Agent.Validation.transition(candidate, state) do
              {:ok, canonical} -> fun.(canonical)
              {:error, _error} -> {:error, {:rejected, :invalid_provider_state}}
            end

          _agent ->
            {:error, {:rejected, :invalid_provider_identity}}
        end

        case provider.commit(descriptor, context, agent, candidate, save) do
          {:error, {:rejected, reason}} -> {:error, {:state_provider_rejected, reason}}
          result -> result
        end
    end
  end

  defp declaration(%Agent{module: module}) do
    if function_exported?(module, :__jido_state_provider__, 0), do: module.__jido_state_provider__()
  end
end
