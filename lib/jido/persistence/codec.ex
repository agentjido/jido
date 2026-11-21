defmodule Jido.Persistence.Codec do
  @moduledoc """
  Encodes logical Jido persistence values as Store bytes.

  A codec owns representation only. Record owners keep keys, versions,
  validation, ordering, and recovery policy.
  """

  @callback id() :: nonempty_binary()
  @callback version() :: pos_integer()
  @callback encode(term()) :: {:ok, binary()} | {:error, term()}
  @callback decode(binary(), keyword()) :: {:ok, term()} | {:error, term()}

  @spec open(module()) :: {:ok, module()} | {:error, term()}
  def open(codec) when is_atom(codec) and not is_nil(codec) do
    with {:module, ^codec} <- Code.ensure_loaded(codec),
         true <- function_exported?(codec, :id, 0),
         id when is_binary(id) and byte_size(id) > 0 <- codec.id(),
         version when is_integer(version) and version > 0 <- codec.version(),
         true <- function_exported?(codec, :encode, 1),
         true <- function_exported?(codec, :decode, 2) do
      {:ok, codec}
    else
      _ -> {:error, {:invalid_persistence_codec, codec}}
    end
  rescue
    error -> {:error, {:invalid_persistence_codec, codec, error}}
  end

  def open(codec), do: {:error, {:invalid_persistence_codec, codec}}

  @doc false
  @spec load_module(binary()) :: {:ok, module()} | {:error, term()}
  def load_module(name) when is_binary(name) do
    with {:ok, module} <- existing_atom(name),
         {:module, ^module} <- Code.ensure_loaded(module) do
      {:ok, module}
    else
      _ -> {:error, {:unavailable_persistence_module, name}}
    end
  end

  def load_module(value), do: {:error, {:invalid_persistence_module, value}}

  defp existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> {:error, {:unknown_persistence_atom, name}}
  end
end
