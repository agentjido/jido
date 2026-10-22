defmodule Jido.Instance.Options do
  @moduledoc false

  alias Jido.Error

  @allowed_keys [
    :agent_server,
    :debug,
    :max_tasks,
    :name,
    :namespace,
    :otp_app,
    :persistence
  ]
  @definition_keys [:namespace, :otp_app, :persistence]
  @default_max_tasks 1_000

  @doc false
  @spec validate_definition!(term()) :: keyword() | no_return()
  def validate_definition!(opts) do
    with true <- Keyword.keyword?(opts),
         :ok <- validate_known_keys(opts, @definition_keys),
         :ok <- validate_unique_keys(opts),
         :ok <- require_otp_app(opts) do
      opts
    else
      false ->
        raise_invalid("use Jido options must be a keyword list", %{value: opts})

      {:error, error} ->
        raise error
    end
  end

  @doc false
  @spec validate(term()) :: {:ok, keyword()} | {:error, Error.ValidationError.t()}
  def validate(opts) do
    with true <- Keyword.keyword?(opts),
         :ok <- validate_known_keys(opts),
         :ok <- validate_unique_keys(opts),
         :ok <- validate_name(Keyword.get(opts, :name)),
         :ok <- validate_otp_app(opts),
         :ok <- validate_namespace(Keyword.get(opts, :namespace)),
         :ok <- validate_debug(Keyword.get(opts, :debug)),
         :ok <- Jido.AgentServer.validate_defaults(Keyword.get(opts, :agent_server, [])),
         :ok <- validate_max_tasks(Keyword.get(opts, :max_tasks, @default_max_tasks)),
         {:ok, persistence} <- validate_persistence(Keyword.get(opts, :persistence)) do
      validated =
        opts
        |> Keyword.put_new(:max_tasks, @default_max_tasks)
        |> Keyword.put(:persistence, persistence)

      {:ok, validated}
    else
      false -> invalid("Jido instance options must be a keyword list", %{value: opts})
      {:error, _error} = error -> error
    end
  end

  @doc false
  @spec validate!(term()) :: keyword() | no_return()
  def validate!(opts) do
    case validate(opts) do
      {:ok, validated} -> validated
      {:error, error} -> raise error
    end
  end

  defp validate_known_keys(opts, allowed_keys \\ @allowed_keys) do
    unknown_keys =
      opts
      |> Keyword.keys()
      |> Enum.reject(&(&1 in allowed_keys))
      |> Enum.uniq()

    case unknown_keys do
      [] -> :ok
      keys -> invalid("Jido instance options contain unknown keys", %{keys: keys})
    end
  end

  defp validate_unique_keys(opts) do
    keys = Keyword.keys(opts)

    case keys -- Enum.uniq(keys) do
      [] ->
        :ok

      duplicates ->
        invalid("Jido instance options must contain unique keys", %{
          keys: Enum.uniq(duplicates)
        })
    end
  end

  defp validate_name(name) when is_atom(name) and not is_nil(name), do: :ok

  defp validate_name(name),
    do: invalid("Jido instance name must be a non-nil atom", %{name: name})

  defp require_otp_app(opts) do
    if Keyword.has_key?(opts, :otp_app),
      do: :ok,
      else: invalid("use Jido requires otp_app", %{otp_app: nil})
  end

  defp validate_otp_app(opts) do
    case Keyword.fetch(opts, :otp_app) do
      :error -> :ok
      {:ok, otp_app} when is_atom(otp_app) and not is_nil(otp_app) -> :ok
      {:ok, otp_app} -> invalid("otp_app must be a non-nil atom", %{otp_app: otp_app})
    end
  end

  defp validate_namespace(nil), do: :ok

  defp validate_namespace(namespace) when is_binary(namespace) and byte_size(namespace) > 0,
    do: :ok

  defp validate_namespace(namespace),
    do: invalid("Jido instance namespace must be a nonempty binary", %{namespace: namespace})

  defp validate_debug(debug) when debug in [nil, false, true, :verbose], do: :ok

  defp validate_debug(debug),
    do: invalid("debug must be false, true, or :verbose", %{debug: debug})

  defp validate_max_tasks(:infinity), do: :ok
  defp validate_max_tasks(max_tasks) when is_integer(max_tasks) and max_tasks >= 0, do: :ok

  defp validate_max_tasks(max_tasks),
    do: invalid("max_tasks must be :infinity or a nonnegative integer", %{max_tasks: max_tasks})

  defp validate_persistence(persistence) do
    case Jido.Persistence.resolve_config(persistence, nil) do
      {:ok, config} -> {:ok, config}
      {:error, reason} -> invalid("Jido instance persistence is invalid", %{reason: reason})
    end
  end

  defp invalid(message, details) do
    {:error,
     Error.validation_error(message,
       kind: :config,
       subject: __MODULE__,
       details: Map.put(details, :code, :jido_instance_invalid_config)
     )}
  end

  defp raise_invalid(message, details) do
    {:error, error} = invalid(message, details)
    raise error
  end
end
