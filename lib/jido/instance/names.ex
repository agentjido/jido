defmodule Jido.Instance.Names do
  @moduledoc false

  @doc false
  @spec exec_runner(atom() | nil) :: atom()
  def exec_runner(nil), do: Jido.ExecRunner
  def exec_runner(instance) when is_atom(instance), do: Module.concat(instance, ExecRunner)

  @doc false
  @spec registry(atom()) :: atom()
  def registry(instance) when is_atom(instance), do: Module.concat(instance, Registry)

  @doc false
  @spec registration_guard(atom()) :: atom()
  def registration_guard(instance) when is_atom(instance),
    do: Module.concat(instance, RegistrationGuard)

  @doc false
  @spec agent_supervisor(atom()) :: atom()
  def agent_supervisor(instance) when is_atom(instance),
    do: Module.concat(instance, AgentSupervisor)

  @doc false
  @spec task_supervisor(atom() | nil) :: atom()
  def task_supervisor(nil), do: Jido.Exec.TaskSupervisor
  def task_supervisor(instance) when is_atom(instance), do: Module.concat(instance, TaskSupervisor)

  def task_supervisor(instance) do
    raise ArgumentError, "Jido instance must be an atom or nil, got: #{inspect(instance)}"
  end

  @doc false
  @spec runtime_store(atom()) :: atom()
  def runtime_store(instance) when is_atom(instance), do: Module.concat(instance, RuntimeStore)

  @doc false
  @spec partition_key(term(), term() | nil) :: term()
  def partition_key(value, nil), do: value
  def partition_key(value, partition), do: {:partition, partition, value}

  @doc false
  @spec unwrap_partition_key(term()) :: {term() | nil, term()}
  def unwrap_partition_key({:partition, partition, value}), do: {partition, value}
  def unwrap_partition_key(value), do: {nil, value}
end
