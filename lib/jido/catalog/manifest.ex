defmodule Jido.Catalog.Manifest do
  @moduledoc """
  A validated static Catalog contribution from one OTP application.

  Manifest validation adds the provider and application to every Entry. It
  does not publish the entries or resolve conflicts across packages.
  """

  alias Jido.Catalog.Entry

  @enforce_keys [:provider, :application, :entries]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          provider: module(),
          application: atom(),
          entries: [Entry.t()]
        }

  @doc "Builds one static package Manifest."
  @spec new(module(), atom(), term()) :: {:ok, t()} | {:error, term()}
  def new(provider, application, entries)
      when is_atom(provider) and provider not in [nil, true, false] and is_atom(application) and
             application not in [nil, true, false] and is_list(entries) do
    if List.improper?(entries) do
      {:error, {:invalid_catalog_manifest, provider, :improper_list}}
    else
      with {:ok, entries} <- build_entries(entries, provider, application) do
        {:ok, %__MODULE__{provider: provider, application: application, entries: entries}}
      end
    end
  end

  def new(provider, _application, _entries) when provider in [nil, true, false] or not is_atom(provider),
    do: {:error, {:invalid_catalog_manifest, provider, :provider}}

  def new(provider, application, _entries)
      when application in [nil, true, false] or not is_atom(application),
      do: {:error, {:invalid_catalog_manifest, provider, {:application, application}}}

  def new(provider, _application, _entries),
    do: {:error, {:invalid_catalog_manifest, provider, :entries}}

  @doc "Builds one Manifest or raises `ArgumentError`."
  @spec new!(module(), atom(), term()) :: t()
  def new!(provider, application, entries) do
    case new(provider, application, entries) do
      {:ok, manifest} -> manifest
      {:error, reason} -> raise ArgumentError, "invalid Catalog Manifest: #{inspect(reason)}"
    end
  end

  defp build_entries(entries, provider, application) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, valid} ->
      case build_entry(entry, provider, application) do
        {:ok, entry} -> {:cont, {:ok, [entry | valid]}}
        {:error, reason} -> {:halt, {:error, {:invalid_catalog_manifest, provider, reason}}}
      end
    end)
    |> case do
      {:ok, valid} -> {:ok, Enum.sort_by(valid, &Entry.sort_key/1)}
      {:error, _reason} = error -> error
    end
  end

  defp build_entry(%Entry{} = entry, provider, application) do
    if entry.provider == provider and entry.application == application,
      do: Entry.new(entry),
      else: {:error, {:entry_owner, Entry.reference(entry)}}
  end

  defp build_entry(%{} = entry, provider, application) when not is_struct(entry) do
    entry
    |> Map.put_new(:provider, provider)
    |> Map.put_new(:application, application)
    |> Entry.new()
    |> case do
      {:ok, %Entry{provider: ^provider, application: ^application} = entry} -> {:ok, entry}
      {:ok, entry} -> {:error, {:entry_owner, Entry.reference(entry)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_entry(_entry, _provider, _application),
    do: {:error, {:invalid_catalog_entry, :entry, :map}}
end
