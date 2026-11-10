defmodule Jido.Exec.Wait do
  @moduledoc """
  Portable data for one suspended Flow wait.

  A wait has a stable execution-scoped ID, a Flow path, resolved event or
  timer options, and the UTC time when it opened. It has no process, storage,
  or AgentServer state.
  """

  @enforce_keys [:id, :execution_id, :path, :options, :opened_at]
  defstruct @enforce_keys

  @typedoc "A non-empty stable ID for one open Flow wait."
  @type id :: String.t()

  @typedoc "A host clock in UTC Unix milliseconds."
  @type clock :: non_neg_integer() | (-> non_neg_integer())

  @typedoc "One event or timer option."
  @type option :: %{
          name: String.t(),
          event: String.t() | nil,
          match: map(),
          deadline: non_neg_integer() | nil
        }

  @typedoc "An accepted wait input."
  @type input :: %{
          id: String.t(),
          wait_id: id(),
          event: String.t(),
          payload: map()
        }

  @typedoc "An accepted input with host-assigned time and receipt order."
  @type candidate :: %{
          input: input(),
          accepted_at: non_neg_integer(),
          order: non_neg_integer()
        }

  @typedoc "Portable data for one open Flow wait."
  @type t :: %__MODULE__{
          id: id(),
          execution_id: term(),
          path: [String.t()],
          options: [option()],
          opened_at: non_neg_integer()
        }

  @doc false
  @spec record(map()) :: {:ok, map()} | {:error, Exception.t()}
  def record(attrs) when is_map(attrs) do
    with {:ok, wait} <- new(attrs),
         true <- Map.has_key?(attrs, :node_hash) and Map.has_key?(attrs, :input_id) do
      {:ok,
       wait
       |> Map.from_struct()
       |> Map.merge(%{
         type: :jido_wait_request,
         version: 1,
         node_hash: attrs.node_hash,
         input_id: attrs.input_id
       })}
    else
      false -> error(:invalid_wait)
      {:error, _reason} = error -> error
    end
  end

  def record(_attrs), do: error(:invalid_wait)

  @doc false
  @spec from_record!(map()) :: t()
  def from_record!(record) do
    case new(record) do
      {:ok, wait} -> wait
      {:error, error} -> raise error
    end
  end

  @doc "Creates and validates one portable wait value."
  @spec new(map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%{
        id: id,
        execution_id: execution_id,
        path: path,
        options: options,
        opened_at: opened_at
      }) do
    if valid_id?(id) and Jido.Codec.Term.valid?(execution_id) and valid_path?(path) and
         valid_options?(options) and is_integer(opened_at) and opened_at >= 0 do
      {:ok,
       %__MODULE__{
         id: id,
         execution_id: execution_id,
         path: path,
         options: options,
         opened_at: opened_at
       }}
    else
      error(:invalid_wait)
    end
  end

  def new(_attrs), do: error(:invalid_wait)

  @doc "Builds a portable input for one wait from a Signal."
  @spec input(id(), Jido.Signal.t()) :: {:ok, input()} | {:error, Exception.t()}
  def input(wait_id, %Jido.Signal{} = signal) do
    input = %{id: signal.id, event: signal.type, payload: signal.data, wait_id: wait_id}

    with :ok <- validate_input(input, 0), do: {:ok, input}
  end

  def input(_wait_id, _signal), do: error(:invalid_input)

  @doc false
  @spec validate_input(term(), integer()) :: :ok | {:error, Exception.t()}
  def validate_input(
        %{id: id, event: event, payload: payload, wait_id: wait_id} = input,
        now
      )
      when is_binary(id) and byte_size(id) > 0 and is_binary(event) and byte_size(event) > 0 and
             is_binary(wait_id) and byte_size(wait_id) > 0 and is_map(payload) and
             not is_struct(payload) and is_integer(now) and now >= 0 do
    if map_size(input) == 4, do: Jido.Codec.Term.validate(input, :wait_event), else: error(:invalid_input)
  end

  def validate_input(_input, now) when not (is_integer(now) and now >= 0),
    do: error(:invalid_clock)

  def validate_input(_input, _now), do: error(:invalid_input)

  @doc false
  @spec validate_candidates(term()) :: :ok | {:error, Exception.t()}
  def validate_candidates(candidates) when is_list(candidates) do
    if not List.improper?(candidates) and Enum.all?(candidates, &valid_candidate?/1),
      do: :ok,
      else: error(:invalid_candidate)
  end

  def validate_candidates(_candidates), do: error(:invalid_candidate)

  @doc "Checks an event name and payload against this wait."
  @spec matches?(t(), String.t(), map()) :: boolean()
  def matches?(%__MODULE__{} = wait, event, payload)
      when is_binary(event) and is_map(payload) and not is_struct(payload),
      do: Enum.any?(wait.options, &matches_option?(&1, event, payload))

  def matches?(_wait, _event, _payload), do: false

  @doc "Returns the earliest timer deadline, or `nil`."
  @spec next_deadline([t()]) :: non_neg_integer() | nil
  def next_deadline(waits) when is_list(waits) do
    for wait <- waits,
        option <- wait.options,
        is_integer(option.deadline),
        reduce: nil do
      nil -> option.deadline
      deadline -> min(deadline, option.deadline)
    end
  end

  @doc false
  @spec choose(t(), [candidate()], non_neg_integer()) :: map() | nil
  def choose(%__MODULE__{} = wait, candidates, now) do
    wait.options
    |> Enum.with_index()
    |> Enum.flat_map(fn {option, index} -> choices(option, index, candidates, now) end)
    |> Enum.min_by(&{&1.at, &1.order}, fn -> nil end)
  end

  @doc false
  @spec result(t(), map()) :: map()
  def result(%__MODULE__{} = wait, choice) do
    value = if choice.input, do: choice.input.payload, else: %{fired_at: choice.at}

    if length(wait.options) == 1,
      do: value,
      else: %{
        selected: choice.option.name,
        value: value,
        accepted_at: choice.at,
        input_id: if(choice.input, do: choice.input.id)
      }
  end

  defp choices(%{deadline: deadline} = option, index, _candidates, now)
       when is_integer(deadline) do
    if deadline <= now,
      do: [%{option: option, at: deadline, order: {0, index}, input: nil}],
      else: []
  end

  defp choices(option, index, candidates, now) do
    for candidate <- candidates,
        candidate.accepted_at <= now,
        matches_option?(option, candidate.input.event, candidate.input.payload),
        do: %{
          option: option,
          at: candidate.accepted_at,
          order: {1, candidate.order, index},
          input: candidate.input
        }
  end

  defp matches_option?(option, event, payload),
    do:
      is_nil(option.deadline) and option.event == event and
        Enum.all?(option.match, fn {key, value} -> Map.fetch(payload, key) == {:ok, value} end)

  defp valid_id?(id), do: is_binary(id) and byte_size(id) > 0

  defp valid_path?(path),
    do: is_list(path) and not List.improper?(path) and Enum.all?(path, &is_binary/1)

  defp valid_options?(options),
    do:
      is_list(options) and options != [] and not List.improper?(options) and
        Enum.all?(options, &valid_option?/1)

  defp valid_option?(%{name: name, event: event, match: match, deadline: deadline} = option) do
    map_size(option) == 4 and is_binary(name) and byte_size(name) > 0 and
      (is_nil(event) or (is_binary(event) and byte_size(event) > 0)) and is_map(match) and
      not is_struct(match) and (is_nil(deadline) or (is_integer(deadline) and deadline >= 0)) and
      ((is_nil(event) and is_integer(deadline)) or (is_binary(event) and is_nil(deadline))) and
      Jido.Codec.Term.valid?(match)
  end

  defp valid_option?(_option), do: false

  defp valid_candidate?(%{
         input: %{id: id, event: event, payload: payload},
         accepted_at: at,
         order: order
       }) do
    is_binary(id) and byte_size(id) > 0 and is_binary(event) and byte_size(event) > 0 and
      is_map(payload) and not is_struct(payload) and is_integer(at) and at >= 0 and
      is_integer(order) and order >= 0
  end

  defp valid_candidate?(_candidate), do: false

  defp error(reason),
    do: {:error, Jido.Error.config_error("wait operation rejected", %{reason: reason})}
end
