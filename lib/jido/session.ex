defmodule Jido.Session do
  @moduledoc """
  A portable conversation session that owns one `Jido.Thread`.

  A Session is an immutable value. An Agent can own it in state, or a trusted
  caller can supply it for one AI request and own its persistence boundary.
  """

  alias Jido.Thread

  @version 1
  @schema Zoi.struct(
            __MODULE__,
            %{
              version: Zoi.integer() |> Zoi.default(@version),
              id: Zoi.string() |> Zoi.min(1),
              rev: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
              thread: Thread.schema(),
              status: Zoi.enum([:open, :closed]) |> Zoi.default(:open),
              created_at: Zoi.integer(),
              updated_at: Zoi.integer(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @state_schema @schema
                |> Zoi.Schema.traverse(fn
                  %{coerce: _} = schema -> %{schema | coerce: false}
                  schema -> schema
                end)
                |> Map.put(:coerce, false)

  @doc "Returns the portable Session schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Returns the strict schema used when a Session is in Agent state."
  @spec state_schema() :: Zoi.schema()
  def state_schema, do: @state_schema

  @doc "Creates an open Session with one empty Thread."
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    now = Keyword.get(opts, :now, System.system_time(:millisecond))
    id = Keyword.get(opts, :id, "session_#{Jido.generate_id()}")
    thread = Keyword.get_lazy(opts, :thread, fn -> Thread.new(id: "#{id}:thread", now: now) end)

    %__MODULE__{
      version: @version,
      id: id,
      rev: thread.rev,
      thread: thread,
      status: :open,
      created_at: now,
      updated_at: now,
      metadata: Keyword.get(opts, :metadata, %{})
    }
    |> validate!()
  end

  @doc "Builds an open Session around an existing Thread."
  @spec from_thread(Thread.t(), keyword()) :: t()
  def from_thread(%Thread{} = thread, opts \\ []) do
    %__MODULE__{
      version: @version,
      id: Keyword.get(opts, :id, "session:#{thread.id}"),
      rev: thread.rev,
      thread: thread,
      status: :open,
      created_at: Keyword.get(opts, :created_at, thread.created_at),
      updated_at: Keyword.get(opts, :updated_at, thread.updated_at),
      metadata: Keyword.get(opts, :metadata, %{})
    }
    |> validate!()
  end

  @doc "Appends entries and returns the complete next Session."
  @spec append(t(), Thread.Entry.t() | map() | [Thread.Entry.t() | map()] | nil) :: t()
  def append(%__MODULE__{status: :closed}, _entries),
    do: raise(ArgumentError, "cannot append to a closed session")

  def append(%__MODULE__{} = session, entries) when entries in [nil, []], do: session

  def append(%__MODULE__{} = session, entries) do
    thread = Thread.append(session.thread, entries)

    %{
      session
      | rev: session.rev + (thread.rev - session.thread.rev),
        thread: thread,
        updated_at: thread.updated_at
    }
    |> validate!()
  end

  @doc "Replaces the portable Session metadata."
  @spec put_metadata(t(), map()) :: t()
  def put_metadata(%__MODULE__{} = session, metadata) when is_map(metadata) do
    case Jido.PortableTerm.validate(metadata, :session_metadata) do
      :ok ->
        %{session | rev: session.rev + 1, metadata: metadata, updated_at: now_after(session.updated_at)}
        |> validate!()

      {:error, _reason} ->
        raise ArgumentError, "invalid session metadata"
    end
  end

  @doc "Closes the Session."
  @spec close(t()) :: t()
  def close(%__MODULE__{status: :closed} = session), do: session

  def close(%__MODULE__{} = session) do
    %{session | rev: session.rev + 1, status: :closed, updated_at: now_after(session.updated_at)}
    |> validate!()
  end

  @doc "Returns true when the Session accepts entries."
  @spec open?(t()) :: boolean()
  def open?(%__MODULE__{status: status}), do: status == :open

  @doc "Returns a versioned portable map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = session) do
    validate!(session)

    %{
      "type" => "jido.session",
      "version" => @version,
      "id" => session.id,
      "rev" => session.rev,
      "thread" => Thread.encode(session.thread),
      "status" => Atom.to_string(session.status),
      "created_at" => session.created_at,
      "updated_at" => session.updated_at,
      "metadata" => session.metadata
    }
  end

  @doc "Decodes and validates a portable Session map."
  @spec decode(t() | map()) :: {:ok, t()} | {:error, :invalid_session | :unsupported_version}
  def decode(%__MODULE__{} = session), do: validate(session)

  def decode(map) when is_map(map) do
    with :ok <- document_version(map),
         true <- known_keys?(map),
         {:ok, thread} <- Thread.decode(field(map, :thread)),
         status when status in [:open, :closed] <- decode_status(field(map, :status)),
         session = %__MODULE__{
           version: @version,
           id: field(map, :id),
           rev: field(map, :rev) || 0,
           thread: thread,
           status: status,
           created_at: field(map, :created_at),
           updated_at: field(map, :updated_at),
           metadata: field(map, :metadata) || %{}
         },
         {:ok, session} <- validate(session) do
      {:ok, session}
    else
      {:error, :unsupported_version} = error -> error
      _other -> {:error, :invalid_session}
    end
  end

  def decode(_value), do: {:error, :invalid_session}

  @doc "Decodes and validates a portable Session map or raises on invalid data."
  @spec decode!(t() | map()) :: t()
  def decode!(value) do
    case decode(value) do
      {:ok, session} -> session
      {:error, reason} -> raise ArgumentError, "invalid session: #{inspect(reason)}"
    end
  end

  @doc false
  @spec validate(t()) :: {:ok, t()} | {:error, :invalid_session}
  def validate(%__MODULE__{} = session) do
    with {:ok, _value} <- Zoi.parse(@schema, session),
         true <- session.version == @version,
         true <- session.rev >= session.thread.rev,
         true <- session.updated_at >= session.created_at,
         {:ok, _thread} <- Thread.validate(session.thread),
         :ok <- Jido.PortableTerm.validate(session.metadata, :session_metadata) do
      {:ok, session}
    else
      _other -> {:error, :invalid_session}
    end
  end

  def validate(_value), do: {:error, :invalid_session}

  defp validate!(session) do
    case validate(session) do
      {:ok, valid} -> valid
      {:error, :invalid_session} -> raise ArgumentError, "invalid session"
    end
  end

  defp document_version(map) do
    case {field(map, :type), field(map, :version)} do
      {"jido.session", @version} -> :ok
      _other -> {:error, :unsupported_version}
    end
  end

  defp known_keys?(map) do
    keys = ~w(type version id rev thread status created_at updated_at metadata __struct__)
    allowed = keys ++ Enum.map(keys, &String.to_atom/1)
    Map.keys(map) -- allowed == []
  end

  defp decode_status(:open), do: :open
  defp decode_status(:closed), do: :closed
  defp decode_status("open"), do: :open
  defp decode_status("closed"), do: :closed
  defp decode_status(_status), do: nil
  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp now_after(previous), do: max(System.system_time(:millisecond), previous)
end

defimpl Runic.Identity.Projectable, for: Jido.Session do
  def identity_document(session), do: Jido.Session.encode(session)
end
