defmodule Jido.Authoring.Config do
  @moduledoc false

  alias Jido.Validation

  @maximum_name_bytes 256

  @doc false
  @spec validate_name(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_name(name, opts \\ [])

  def validate_name(name, opts) when is_binary(name) do
    subject = name_subject(opts)

    cond do
      not String.valid?(name) ->
        {:error, "#{subject} name must be valid UTF-8."}

      String.trim(name) == "" ->
        {:error, "#{subject} name cannot be blank."}

      byte_size(name) > @maximum_name_bytes ->
        {:error, "#{subject} name cannot exceed #{@maximum_name_bytes} bytes."}

      true ->
        :ok
    end
  end

  def validate_name(_name, opts) do
    {:error, "#{name_subject(opts)} name must be a string."}
  end

  @doc false
  @spec validate_config_schema(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_config_schema(value, _opts \\ [])

  def validate_config_schema([], _opts), do: :ok

  def validate_config_schema(value, _opts) do
    if Validation.zoi_schema?(value) do
      :ok
    else
      {:error, "must be a Zoi schema"}
    end
  end

  @doc false
  @spec validate_map_schema(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_map_schema(value, opts \\ []) do
    with :ok <- validate_config_schema(value, opts) do
      if value == [] or Validation.map_schema?(value) do
        :ok
      else
        {:error, "must accept map-shaped data"}
      end
    end
  end

  @doc false
  @spec validate_static_data(term()) ::
          :ok | {:error, Jido.Authoring.Error.InvalidError.t()}
  def validate_static_data(term), do: Jido.Authoring.validate_static(term)

  defp name_subject(opts) when is_list(opts) do
    case Keyword.get(opts, :subject, "Definition") do
      subject when is_binary(subject) and subject != "" -> subject
      _other -> "Definition"
    end
  end

  defp name_subject(_opts), do: "Definition"
end
