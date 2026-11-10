defmodule Jido.Flow.Codec do
  @moduledoc false

  @behaviour Jido.Codec.Contract

  alias Jido.Catalog
  alias Jido.Catalog.Error, as: CatalogError
  alias Jido.Codec.Issue
  alias Jido.Error
  alias Jido.Flow
  alias Jido.Flow.Definition
  alias Jido.Flow.Codec.{Paths, Reader, Writer}

  @type document :: %{required(String.t()) => term()}

  @impl true
  def type, do: "jido.flow"

  @impl true
  def version, do: 2

  @impl true
  def target, do: Jido.Flow

  @impl true
  @spec encode(term(), term()) :: {:ok, document()} | {:error, Exception.t()}
  def encode(%Flow{} = flow, catalog) when is_struct(catalog, Catalog) or catalog == :current do
    with {:ok, flow} <- Flow.validate(flow), do: Writer.encode(flow, catalog)
  end

  def encode(value, catalog) when is_struct(catalog, Catalog) or catalog == :current,
    do: {:error, Error.validation_error("expected a Jido.Flow artifact", %{value: value})}

  def encode(_flow, catalog),
    do:
      {:error,
       Error.validation_error("flow codec catalog must be a Jido.Catalog", %{
         value: catalog
       })}

  @impl true
  @spec decode(term(), term()) :: {:ok, Flow.t()} | {:error, [Issue.t()]}
  def decode(document, registry) do
    case diagnose(document, registry) do
      {:ok, flow} -> {:ok, flow}
      {:error, %Error.Invalid{errors: errors}} -> {:error, Enum.map(errors, &authoring_issue/1)}
    end
  end

  @doc false
  @spec diagnose(document(), Catalog.source()) ::
          {:ok, Flow.t()} | {:error, Error.Invalid.t()}
  def diagnose(document, catalog) when is_struct(catalog, Catalog) or catalog == :current do
    case Reader.decode(document, catalog) do
      {:ok, attrs, paths} ->
        case Definition.diagnose_lowered(attrs) do
          {:ok, attrs} ->
            {:ok, struct!(Flow, attrs)}

          {:error, issues} ->
            errors =
              Enum.map(issues, fn issue ->
                error = %{
                  issue.error
                  | details: Map.put(issue.error.details, :path, issue.location)
                }

                Paths.error(error, paths)
              end)

            failure(errors)
        end

      {:error, errors} ->
        failure(errors)
    end
  end

  def diagnose(_document, catalog),
    do:
      failure([
        Error.validation_error("flow codec catalog must be a Jido.Catalog", %{
          value: catalog
        })
      ])

  defp authoring_issue(%CatalogError{} = error),
    do: authoring_issue(error, :reference)

  defp authoring_issue(%Error.ValidationError{} = error),
    do: authoring_issue(error, :invalid_definition)

  defp authoring_issue(error), do: authoring_issue(error, :invalid_document)

  defp authoring_issue(error, default_code) do
    details = if is_map(error) and is_map(Map.get(error, :details)), do: error.details, else: %{}
    code = Map.get(details, :code, default_code)
    path = Map.get(details, :path, [])

    message =
      if is_map(error) and Map.get(error, :__exception__),
        do: Exception.message(error),
        else: inspect(error)

    Issue.new(code, path, message, details: Map.drop(details, [:code, :path]))
  end

  defp failure(errors), do: {:error, %Error.Invalid{errors: errors}}
end

defimpl Jido.Codec.Encoder, for: Jido.Flow do
  def codec(_flow), do: {:ok, Jido.Flow.Codec}
end
