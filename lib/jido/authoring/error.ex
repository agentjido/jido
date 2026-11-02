defmodule Jido.Authoring.Error do
  @moduledoc "Defines classified errors from the runtime authoring boundary."

  use Splode,
    error_classes: [
      invalid: __MODULE__.Invalid,
      internal: __MODULE__.Internal
    ],
    unknown_error: __MODULE__.Internal.UnknownError

  @type code :: atom()

  defmodule Invalid do
    @moduledoc false
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Internal do
    @moduledoc false
    use Splode.ErrorClass, class: :internal

    defmodule UnknownError do
      @moduledoc false
      use Splode.Error,
        class: :internal,
        fields: [message: "Unknown authoring error", error: nil, details: %{}]

      @spec message(map()) :: String.t()
      def message(%{error: error}) when not is_nil(error), do: normalize_message(error)
      def message(%{message: message}), do: message

      defp normalize_message(message) when is_binary(message), do: message
      defp normalize_message(message) when is_atom(message), do: Atom.to_string(message)
      defp normalize_message(message), do: inspect(message)
    end
  end

  defmodule InvalidError do
    @moduledoc "An invalid authoring value, document, or option."
    use Splode.Error,
      class: :invalid,
      fields: [message: "Invalid authoring data", code: nil, details: %{}]

    @type t :: %__MODULE__{message: String.t(), code: atom(), details: map()}
  end

  defmodule InternalError do
    @moduledoc "An authoring codec or Registry lifecycle failure."
    use Splode.Error,
      class: :internal,
      fields: [message: "Authoring failed", code: nil, details: %{}]

    @type t :: %__MODULE__{message: String.t(), code: atom(), details: map()}
  end

  @doc "Creates an invalid authoring error."
  @spec invalid(code(), String.t(), map()) :: InvalidError.t()
  def invalid(code, message, details \\ %{}),
    do:
      InvalidError.exception(
        code: code,
        message: message,
        details: normalize_details(details)
      )

  @doc "Creates an internal authoring error."
  @spec internal(code(), String.t(), map()) :: InternalError.t()
  def internal(code, message, details \\ %{}),
    do:
      InternalError.exception(
        code: code,
        message: message,
        details: normalize_details(details)
      )

  defp normalize_details(details) when is_map(details), do: details
  defp normalize_details(_details), do: %{}
end
