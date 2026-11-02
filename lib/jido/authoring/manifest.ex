defmodule Jido.Authoring.Manifest do
  @moduledoc false

  alias Jido.Authoring.Registry

  @fields [:id, :kind, :vsn, :target, :name, :description]

  @type t :: %{
          required(:id) => Registry.stable_id(),
          required(:kind) => Registry.kind(),
          required(:vsn) => pos_integer(),
          required(:target) => term(),
          optional(:name) => String.t() | nil,
          optional(:description) => String.t() | nil,
          optional(:provider) => module(),
          optional(:application) => atom() | nil
        }

  @doc "Validates the static authoring manifest exported by one module."
  @spec validate(module(), term()) :: {:ok, [t()]} | {:error, term()}
  def validate(provider, manifests) when is_list(manifests) do
    if List.improper?(manifests) do
      {:error, {:invalid_authoring_manifest, provider, :improper_list}}
    else
      traverse(manifests, &validate_one(provider, &1))
    end
  end

  def validate(provider, manifest), do: validate(provider, [manifest])

  defp validate_one(provider, %{} = manifest) when not is_struct(manifest) do
    unknown = Map.keys(manifest) -- @fields
    missing = [:id, :kind, :vsn, :target] -- Map.keys(manifest)

    cond do
      unknown != [] ->
        {:error, {:invalid_authoring_manifest, provider, {:unknown_fields, Enum.sort(unknown)}}}

      missing != [] ->
        {:error, {:invalid_authoring_manifest, provider, {:missing_fields, missing}}}

      not valid_vsn?(manifest.vsn) ->
        {:error, {:invalid_authoring_manifest, provider, :vsn}}

      not valid_kind?(manifest.kind) ->
        {:error, {:invalid_authoring_manifest, provider, :kind}}

      not valid_text?(Map.get(manifest, :name)) ->
        {:error, {:invalid_authoring_manifest, provider, :name}}

      not valid_text?(Map.get(manifest, :description)) ->
        {:error, {:invalid_authoring_manifest, provider, :description}}

      true ->
        with {:ok, _reference} <- Registry.validate_reference({manifest.id, manifest.vsn}),
             :ok <- validate_target(manifest.kind, manifest.target) do
          {:ok, Map.put(manifest, :provider, provider)}
        else
          {:error, %Registry.Error{} = error} ->
            {:error, {:invalid_authoring_manifest, provider, error}}

          {:error, reason} ->
            {:error, {:invalid_authoring_manifest, provider, {:target, reason}}}
        end
    end
  end

  defp validate_one(provider, _manifest),
    do: {:error, {:invalid_authoring_manifest, provider, :map}}

  defp valid_vsn?(vsn), do: Registry.validate_vsn(vsn) == :ok
  defp valid_kind?(kind), do: is_atom(kind) and kind not in [nil, true, false, :alias]

  defp valid_text?(nil), do: true
  defp valid_text?(value), do: is_binary(value) and String.valid?(value)

  defp validate_target(kind, target) when kind in [:action, :flow] do
    if is_atom(target) and target not in [nil, true, false],
      do: :ok,
      else: {:error, "Action and Flow targets must be modules"}
  end

  defp validate_target(:atom, target) do
    if is_atom(target) and target not in [nil, true, false],
      do: :ok,
      else: {:error, "atom targets must be non-Boolean atoms"}
  end

  defp validate_target(:schema, target) do
    with :ok <- Jido.Authoring.validate_static(target),
         do: Jido.Authoring.Config.validate_map_schema(target)
  end

  defp validate_target(_kind, target), do: Jido.Authoring.validate_static(target)

  defp traverse(values, mapper) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, results} ->
      case mapper.(value) do
        {:ok, result} -> {:cont, {:ok, [result | results]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, _reason} = error -> error
    end
  end
end
