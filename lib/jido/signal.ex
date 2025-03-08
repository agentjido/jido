defmodule Jido.Signal do
  @moduledoc """
  Defines the core Signal structure in Jido, implementing the CloudEvents specification (v1.0.2)
  with Jido-specific extensions for agent-based systems.

  https://cloudevents.io/

  ## Overview

  Signals are the universal message format in Jido, serving as the nervous system of your
  agent-based application. Every event, command, and state change flows through the system
  as a Signal, providing:

  - Standardized event structure (CloudEvents v1.0.2 compatible)
  - Rich metadata and context tracking
  - Built-in instruction handling
  - Flexible dispatch configuration
  - Automatic serialization

  ## CloudEvents Compliance

  Each Signal implements the CloudEvents v1.0.2 specification with these required fields:

  - `specversion`: Always "1.0.2"
  - `id`: Unique identifier (UUID v4)
  - `source`: Origin of the event ("/service/component")
  - `type`: Classification of the event ("domain.entity.action")

  And optional fields:

  - `subject`: Specific subject of the event
  - `time`: Timestamp in ISO 8601 format
  - `datacontenttype`: Media type of the data (defaults to "application/json")
  - `dataschema`: Schema defining the data structure
  - `data`: The actual event payload

  ## Jido Extensions

  Beyond the CloudEvents spec, Signals include Jido-specific fields:

  - `jido_dispatch`: Routing and delivery configuration (optional)

  ## Creating Signals

  Signals can be created in several ways:

  ```elixir
  # Basic event
  {:ok, signal} = Signal.new(%{
    type: "user.created",
    source: "/auth/registration",
    data: %{user_id: "123", email: "user@example.com"}
  })

  # With instructions
  {:ok, signal} = Signal.new(%{
    type: "order.process",
    source: "/orders",
    data: %{order_id: "456"},
    jido_instructions: [
      ProcessOrder,
      {NotifyUser, %{template: "order_confirmation"}}
    ]
  })

  # With dispatch config
  {:ok, signal} = Signal.new(%{
    type: "metrics.collected",
    source: "/monitoring",
    data: %{cpu: 80, memory: 70},
    jido_dispatch: {:pubsub, topic: "metrics"}
  })
  ```

  ## Signal Types

  Signal types are strings, but typically use a hierarchical dot notation:

  ```
  <domain>.<entity>.<action>[.<qualifier>]
  ```

  Examples:
  - `user.profile.updated`
  - `order.payment.processed.success`
  - `system.metrics.collected`

  Guidelines for type naming:
  - Use lowercase with dots
  - Keep segments meaningful
  - Order from general to specific
  - Include qualifiers when needed

  ## Data Content Types

  The `datacontenttype` field indicates the format of the `data` field:

  - `application/json` (default) - JSON-structured data
  - `text/plain` - Unstructured text
  - `application/octet-stream` - Binary data
  - Custom MIME types for specific formats

  ## Instruction Handling

  Signals can carry instructions for agents to execute:

  ```elixir
  Signal.new(%{
    type: "task.assigned",
    source: "/workflow",
    jido_instructions: [
      ValidateTask,
      {AssignTask, %{worker: "agent_1"}},
      NotifyAssignment
    ]
  })
  ```

  Instructions are normalized and validated during Signal creation.

  ## Dispatch Configuration

  The `jido_dispatch` field controls how the Signal is delivered:

  ```elixir
  # Single dispatch config
  jido_dispatch: {:pubsub, topic: "events"}

  # Multiple dispatch targets
  jido_dispatch: [
    {:pubsub, topic: "events"},
    {:logger, level: :info},
    {:webhook, url: "https://api.example.com/webhook"}
  ]
  ```

  ## See Also

  - `Jido.Instruction` - Instruction specification
  - `Jido.Signal.Router` - Signal routing
  - `Jido.Signal.Dispatch` - Dispatch handling
  - CloudEvents spec: https://cloudevents.io/
  """
  alias Jido.Signal.Dispatch
  alias Jido.Signal.ID
  use TypedStruct

  @derive {Jason.Encoder,
           only: [
             :id,
             :source,
             :type,
             :subject,
             :time,
             :datacontenttype,
             :dataschema,
             :data,
             :specversion
           ]}

  typedstruct do
    field(:specversion, String.t(), default: "1.0.2")
    field(:id, String.t(), enforce: true, default: ID.generate!())
    field(:source, String.t(), enforce: true)
    field(:type, String.t(), enforce: true)
    field(:subject, String.t())
    field(:time, String.t())
    field(:datacontenttype, String.t())
    field(:dataschema, String.t())
    field(:data, term())
    # Jido-specific fields
    field(:jido_dispatch, Dispatch.dispatch_configs())
  end

  @doc """
  Creates a new Signal struct, raising an error if invalid.

  ## Parameters

  - `attrs`: A map or keyword list containing the Signal attributes.

  ## Returns

  `Signal.t()` if the attributes are valid.

  ## Raises

  `RuntimeError` if the attributes are invalid.

  ## Examples

      iex> Jido.Signal.new!(%{type: "example.event", source: "/example"})
      %Jido.Signal{type: "example.event", source: "/example", ...}

      iex> Jido.Signal.new!(type: "example.event", source: "/example")
      %Jido.Signal{type: "example.event", source: "/example", ...}

  """
  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, signal} -> signal
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Creates a new Signal struct.

  ## Parameters

  - `attrs`: A map or keyword list containing the Signal attributes.

  ## Returns

  `{:ok, Signal.t()}` if the attributes are valid, `{:error, String.t()}` otherwise.

  ## Examples

      iex> Jido.Signal.new(%{type: "example.event", source: "/example", id: "123"})
      {:ok, %Jido.Signal{type: "example.event", source: "/example", id: "123", ...}}

      iex> Jido.Signal.new(type: "example.event", source: "/example")
      {:ok, %Jido.Signal{type: "example.event", source: "/example", ...}}

  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_list(attrs) do
    attrs |> Map.new() |> new()
  end

  def new(attrs) when is_map(attrs) do
    caller =
      Process.info(self(), :current_stacktrace)
      |> elem(1)
      |> Enum.find(fn {mod, _fun, _arity, _info} ->
        mod_str = to_string(mod)
        mod_str != "Elixir.Jido.Signal" and mod_str != "Elixir.Process"
      end)
      |> elem(0)
      |> to_string()

    defaults = %{
      "specversion" => "1.0.2",
      "id" => ID.generate!(),
      "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => caller
    }

    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.merge(defaults, fn _k, user_val, _default_val -> user_val end)
    |> from_map()
  end

  @doc """
  Creates a new Signal struct from a map.

  ## Parameters

  - `map`: A map containing the Signal attributes.

  ## Returns

  `{:ok, Signal.t()}` if the map is valid, `{:error, String.t()}` otherwise.

  ## Examples

      iex> Jido.Signal.from_map(%{"type" => "example.event", "source" => "/example", "id" => "123"})
      {:ok, %Jido.Signal{type: "example.event", source: "/example", id: "123", ...}}

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with :ok <- parse_specversion(map),
         {:ok, type} <- parse_type(map),
         {:ok, source} <- parse_source(map),
         {:ok, id} <- parse_id(map),
         {:ok, subject} <- parse_subject(map),
         {:ok, time} <- parse_time(map),
         {:ok, datacontenttype} <- parse_datacontenttype(map),
         {:ok, dataschema} <- parse_dataschema(map),
         {:ok, data} <- parse_data(map["data"]),
         {:ok, jido_dispatch} <- parse_jido_dispatch(map["jido_dispatch"]) do
      event = %__MODULE__{
        specversion: "1.0.2",
        type: type,
        source: source,
        id: id,
        subject: subject,
        time: time,
        datacontenttype: datacontenttype || if(data, do: "application/json"),
        dataschema: dataschema,
        data: data,
        jido_dispatch: jido_dispatch
      }

      {:ok, event}
    else
      {:error, reason} -> {:error, "parse error: #{reason}"}
    end
  end

  def map_to_signal_data(signals, fields \\ [])

  @spec map_to_signal_data(list(struct), Keyword.t()) :: list(t())
  def map_to_signal_data(signals, fields) when is_list(signals) do
    Enum.map(signals, &map_to_signal_data(&1, fields))
  end

  alias Jido.Signal.Serialization.TypeProvider

  @spec map_to_signal_data(struct, Keyword.t()) :: t()
  def map_to_signal_data(signal, _fields) do
    %__MODULE__{
      id: ID.generate(),
      source: "http://example.com/bank",
      type: TypeProvider.to_string(signal),
      data: signal
    }
  end

  # Parser functions for standard CloudEvents fields
  defp parse_specversion(%{"specversion" => "1.0.2"}), do: :ok
  defp parse_specversion(%{"specversion" => x}), do: {:error, "unexpected specversion #{x}"}
  defp parse_specversion(_), do: {:error, "missing specversion"}

  defp parse_type(%{"type" => type}) when byte_size(type) > 0, do: {:ok, type}
  defp parse_type(_), do: {:error, "missing type"}

  defp parse_source(%{"source" => source}) when byte_size(source) > 0, do: {:ok, source}
  defp parse_source(_), do: {:error, "missing source"}

  defp parse_id(%{"id" => id}) when byte_size(id) > 0, do: {:ok, id}
  defp parse_id(%{"id" => ""}), do: {:error, "id given but empty"}
  defp parse_id(_), do: {:ok, ID.generate!()}

  defp parse_subject(%{"subject" => sub}) when byte_size(sub) > 0, do: {:ok, sub}
  defp parse_subject(%{"subject" => ""}), do: {:error, "subject given but empty"}
  defp parse_subject(_), do: {:ok, nil}

  defp parse_time(%{"time" => time}) when byte_size(time) > 0, do: {:ok, time}
  defp parse_time(%{"time" => ""}), do: {:error, "time given but empty"}
  defp parse_time(_), do: {:ok, nil}

  defp parse_datacontenttype(%{"datacontenttype" => ct}) when byte_size(ct) > 0, do: {:ok, ct}

  defp parse_datacontenttype(%{"datacontenttype" => ""}),
    do: {:error, "datacontenttype given but empty"}

  defp parse_datacontenttype(_), do: {:ok, nil}

  defp parse_dataschema(%{"dataschema" => schema}) when byte_size(schema) > 0, do: {:ok, schema}
  defp parse_dataschema(%{"dataschema" => ""}), do: {:error, "dataschema given but empty"}
  defp parse_dataschema(_), do: {:ok, nil}

  defp parse_data(""), do: {:error, "data field given but empty"}
  defp parse_data(data), do: {:ok, data}

  defp parse_jido_dispatch(nil), do: {:ok, nil}

  defp parse_jido_dispatch({adapter, opts} = config) when is_atom(adapter) and is_list(opts) do
    {:ok, config}
  end

  defp parse_jido_dispatch(config) when is_list(config) do
    {:ok, config}
  end

  defp parse_jido_dispatch(_), do: {:error, "invalid dispatch config"}
end
