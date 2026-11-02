defmodule Jido.AI.Reasoning.Result do
  @moduledoc "Builds the common terminal result for a reasoning Flow."

  @type status :: :completed | :blocked | :failed
  @type reason_code :: atom()
  @type t :: %{
          status: status(),
          output: term(),
          reason_code: reason_code(),
          reason: String.t() | nil,
          reasoning: map() | nil
        }

  @doc "Builds a terminal result."
  @spec new(status(), term(), reason_code(), String.t() | nil, map() | nil) :: t()
  def new(status, output, reason_code, reason, reasoning \\ nil)
      when status in [:completed, :blocked, :failed] and is_atom(reason_code) and
             (is_binary(reason) or is_nil(reason)) and (is_map(reasoning) or is_nil(reasoning)) do
    %{
      status: status,
      output: output,
      reason_code: reason_code,
      reason: reason,
      reasoning: reasoning
    }
  end

  @doc "Builds a completed result."
  @spec completed(term(), map() | nil) :: t()
  def completed(output, reasoning \\ nil), do: new(:completed, output, :none, nil, reasoning)

  @doc "Builds a blocked result."
  @spec blocked(reason_code(), String.t(), map() | nil) :: t()
  def blocked(reason_code, reason, reasoning \\ nil),
    do: new(:blocked, "", reason_code, reason, reasoning)

  @doc "Builds a failed result."
  @spec failed(reason_code(), String.t(), map() | nil) :: t()
  def failed(reason_code, reason, reasoning \\ nil),
    do: new(:failed, "", reason_code, reason, reasoning)
end
