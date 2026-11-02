defmodule Jido.Joi.Error do
  @moduledoc "Helpers for Joi parse errors."

  @type t :: Jido.Joi.error()

  @error_delegates [
    custom_error: 0,
    custom_error: 1,
    greater_than: 2,
    greater_than: 3,
    greater_than_or_equal_to: 2,
    greater_than_or_equal_to: 3,
    invalid_contains: 2,
    invalid_contains: 3,
    invalid_ending_string: 1,
    invalid_ending_string: 2,
    invalid_enum_value: 1,
    invalid_enum_value: 2,
    invalid_format: 1,
    invalid_format: 2,
    invalid_length: 2,
    invalid_length: 3,
    invalid_literal: 1,
    invalid_literal: 2,
    invalid_starting_string: 1,
    invalid_starting_string: 2,
    invalid_tuple: 2,
    invalid_tuple: 3,
    invalid_type: 1,
    invalid_type: 2,
    invalid_url: 1,
    invalid_url: 2,
    less_than: 2,
    less_than: 3,
    less_than_or_equal_to: 2,
    less_than_or_equal_to: 3,
    message: 1,
    multiple_of: 1,
    multiple_of: 2,
    new: 0,
    new: 1,
    not_in_values: 1,
    not_in_values: 2,
    not_unique: 0,
    not_unique: 1,
    prepend_path: 2,
    put_issue_opt: 3,
    required: 1,
    required: 2,
    unrecognized_key: 1
  ]

  for {name, arity} <- @error_delegates do
    args = Macro.generate_arguments(arity, __MODULE__)
    defdelegate unquote(name)(unquote_splicing(args)), to: Zoi.Error
  end

  @spec code(t()) :: atom()
  def code(%{code: code}), do: code

  @spec path(t()) :: [term()]
  def path(%{path: path}), do: path

  @spec message_text(t()) :: String.t()
  def message_text(%{message: message}), do: message

  @spec changed_value?(t()) :: boolean()
  def changed_value?(%{code: :joi_changed_value}), do: true
  def changed_value?(_error), do: false
end
