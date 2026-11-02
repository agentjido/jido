defmodule Jido.Flow.Codec do
  @moduledoc false

  alias Jido.Authoring.Issue
  alias Jido.Flow
  alias Jido.Flow.{Definition, Error}
  alias Jido.Flow.Codec.{Paths, Reader, Writer}

  @type document :: %{required(String.t()) => term()}

  @doc false
  @spec __jido_authoring_codec__() :: %{type: String.t(), vsn: pos_integer(), encoder: module()}
  def __jido_authoring_codec__, do: %{type: "jido.flow", vsn: 2, encoder: Jido.Flow}

  @doc false
  @spec encode_document(term(), term()) :: {:ok, document()} | {:error, Exception.t()}
  def encode_document(%Flow{} = flow, %Jido.Authoring.Registry{} = registry) do
    with {:ok, flow} <- Flow.validate(flow), do: Writer.encode(flow, registry)
  end

  def encode_document(value, %Jido.Authoring.Registry{}),
    do: {:error, Error.validation_error("expected a Jido.Flow artifact", %{value: value})}

  def encode_document(_flow, registry),
    do:
      {:error,
       Error.validation_error("flow codec registry must be a Jido.Authoring.Registry", %{
         value: registry
       })}

  @doc false
  @spec decode_document(term(), term()) :: {:ok, Flow.t()} | {:error, [Issue.t()]}
  def decode_document(document, registry) do
    case diagnose(document, registry) do
      {:ok, flow} -> {:ok, flow}
      {:error, %Error.Invalid{errors: errors}} -> {:error, Enum.map(errors, &authoring_issue/1)}
    end
  end

  @doc false
  @spec diagnose(document(), Jido.Authoring.Registry.t()) ::
          {:ok, Flow.t()} | {:error, Error.Invalid.t()}
  def diagnose(document, %Jido.Authoring.Registry{} = registry) do
    case Reader.decode(document, registry) do
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

  def diagnose(_document, registry),
    do:
      failure([
        Error.validation_error("flow codec registry must be a Jido.Authoring.Registry", %{
          value: registry
        })
      ])

  defp authoring_issue(%Jido.Authoring.Registry.Error{} = error),
    do: authoring_issue(error, :reference)

  defp authoring_issue(%Error.InvalidDefinitionError{} = error),
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
