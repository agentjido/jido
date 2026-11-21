defmodule Jido.Session do
  alias Jido.Joi

  @moduledoc """
  A portable Agent Session that owns one `Jido.Thread`.

  A Session is an immutable value. An Agent or a trusted caller can own it.
  The value does not own a process, storage adapter, or feature-specific
  projection.
  """

  alias Jido.Thread
  alias Runic.Identity.{Canonical, CanonicalError}

  @version 1
  @fields %{
    version: Joi.integer() |> Joi.default(@version),
    id: Joi.string() |> Joi.min(1),
    rev: Joi.integer() |> Joi.min(0) |> Joi.default(0),
    thread: Joi.struct(Thread),
    status: Joi.enum([:open, :closed]) |> Joi.default(:open),
    created_at: Joi.integer(),
    updated_at: Joi.integer(),
    metadata: Joi.map() |> Joi.default(%{})
  }
  @schema Joi.struct(__MODULE__, %{@fields | thread: Thread.schema()})
  @value_schema Joi.struct(__MODULE__, @fields)
  @state_schema Joi.refine(@value_schema, {__MODULE__, :validate_state, []})

  @document_fields ~w(type version id rev thread status created_at updated_at metadata)a
  @string_fields Map.new(@document_fields, &{Atom.to_string(&1), &1})

  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc "Returns the schema for the shape of a portable Session."
  @spec schema() :: Joi.schema()
  def schema, do: @schema

  @doc "Returns the schema that validates a portable Session in Agent state."
  @spec state_schema() :: Joi.schema()
  def state_schema, do: @state_schema

  @doc "Creates an open Session with an empty Thread or a supplied Thread."
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    now = Keyword.get(opts, :now, System.system_time(:millisecond))
    id = Keyword.get_lazy(opts, :id, fn -> "session_#{Jido.Id.uuid7()}" end)
    thread = Keyword.get_lazy(opts, :thread, fn -> Thread.new(id: "#{id}:thread", now: now) end)

    build(thread, id, now, now, Keyword.get(opts, :metadata, %{}))
  end

  @doc "Builds an open Session around an existing Thread."
  @spec from_thread(Thread.t(), keyword()) :: t()
  def from_thread(%Thread{} = thread, opts \\ []) do
    build(
      thread,
      Keyword.get_lazy(opts, :id, fn -> "session:#{thread.id}" end),
      Keyword.get(opts, :created_at, thread.created_at),
      Keyword.get(opts, :updated_at, thread.updated_at),
      Keyword.get(opts, :metadata, %{})
    )
  end

  defp build(thread, id, created_at, updated_at, metadata) do
    %__MODULE__{
      version: @version,
      id: id,
      rev: thread.rev,
      thread: thread,
      status: :open,
      created_at: created_at,
      updated_at: updated_at,
      metadata: metadata
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
        updated_at: max(session.updated_at, thread.updated_at)
    }
    |> validate!(:thread)
  end

  @doc "Replaces the portable Session metadata."
  @spec put_metadata(t(), map()) :: t()
  def put_metadata(%__MODULE__{} = session, metadata) when is_map(metadata) do
    case Jido.Codec.Term.validate(metadata, :session_metadata) do
      :ok ->
        %{session | rev: session.rev + 1, metadata: metadata, updated_at: now_after(session.updated_at)}
        |> validate!(:metadata)

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
    validate!(session, :thread)
    thread = encode_thread!(session.thread)

    %{
      "type" => "jido.session",
      "version" => @version,
      "id" => session.id,
      "rev" => session.rev,
      "thread" => thread,
      "status" => Atom.to_string(session.status),
      "created_at" => session.created_at,
      "updated_at" => session.updated_at,
      "metadata" => session.metadata
    }
  end

  @doc false
  @spec encode_for_runic(t()) :: {:ok, map()} | {:error, :invalid_session | :invalid_session_identity}
  def encode_for_runic(%__MODULE__{} = session) do
    document = encode(session)
    _canonical = Canonical.encode!(document)
    {:ok, document}
  rescue
    CanonicalError -> {:error, :invalid_session_identity}
    ArgumentError -> {:error, :invalid_session}
  end

  defp encode_thread!(thread) do
    if thread_entries_valid?(thread), do: Thread.encode(thread), else: raise(ArgumentError, "invalid thread")
  rescue
    ArgumentError -> raise ArgumentError, "invalid session"
  end

  @doc "Decodes and validates a portable Session map."
  @spec decode(t() | map()) :: {:ok, t()} | {:error, :invalid_session | :unsupported_version}
  def decode(%__MODULE__{} = session), do: validate(session)

  def decode(map) when is_map(map) do
    with {:ok, fields} <- document_fields(map),
         :ok <- document_version(fields),
         true <- Map.keys(fields) -- @document_fields == [],
         thread = Map.get(fields, :thread),
         true <- thread_entries_valid?(thread),
         {:ok, thread} <- Thread.decode(thread),
         status when status in [:open, :closed] <- decode_status(Map.get(fields, :status)),
         session = %__MODULE__{
           version: @version,
           id: Map.get(fields, :id),
           rev: default(Map.get(fields, :rev), 0),
           thread: thread,
           status: status,
           created_at: Map.get(fields, :created_at),
           updated_at: Map.get(fields, :updated_at),
           metadata: default(Map.get(fields, :metadata), %{})
         } do
      validate_checked(session, :thread)
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
  def validate(%__MODULE__{} = session), do: validate_checked(session, nil)
  def validate(_value), do: {:error, :invalid_session}

  @doc false
  def validate_state(session, _opts) do
    if valid_invariants?(session, nil), do: :ok, else: {:error, "invalid session"}
  end

  defp validate_checked(session, checked) do
    if Joi.validate(@value_schema, session) == :ok and valid_invariants?(session, checked) do
      {:ok, session}
    else
      {:error, :invalid_session}
    end
  end

  defp valid_invariants?(%__MODULE__{thread: %Thread{rev: thread_rev}} = session, checked) do
    session.version == @version and session.rev >= thread_rev and session.updated_at >= session.created_at and
      (checked == :thread or valid_thread?(session.thread)) and
      (checked == :metadata or Jido.Codec.Term.validate(session.metadata, :session_metadata) == :ok)
  end

  defp valid_invariants?(_session, _checked), do: false

  defp valid_thread?(thread) do
    thread_entries_valid?(thread) and match?({:ok, _}, Thread.validate(thread))
  end

  # Thread enumerates entries after an is_list/1 check, which also accepts improper lists.
  defp thread_entries_valid?(%Thread{} = thread) do
    entries = Map.get(thread, :entries)
    is_list(entries) and not List.improper?(entries)
  end

  defp thread_entries_valid?(document) when is_map(document) do
    entries = Map.get(document, :entries, Map.get(document, "entries"))
    not (is_list(entries) and List.improper?(entries))
  end

  defp thread_entries_valid?(_value), do: false

  defp validate!(session, checked \\ nil) do
    case validate_checked(session, checked) do
      {:ok, valid} -> valid
      {:error, :invalid_session} -> raise ArgumentError, "invalid session"
    end
  end

  defp document_version(%{type: "jido.session", version: @version}), do: :ok
  defp document_version(_fields), do: {:error, :unsupported_version}

  defp document_fields(map) do
    Enum.reduce_while(Map.to_list(map), {:ok, %{}}, fn {spelling, value}, {:ok, fields} ->
      key = Map.get(@string_fields, spelling, spelling)

      if Map.get(fields, key, value) === value do
        {:cont, {:ok, Map.put(fields, key, value)}}
      else
        {:halt, {:error, :invalid_session}}
      end
    end)
  end

  defp default(nil, value), do: value
  defp default(value, _default), do: value
  defp decode_status(:open), do: :open
  defp decode_status(:closed), do: :closed
  defp decode_status("open"), do: :open
  defp decode_status("closed"), do: :closed
  defp decode_status(_status), do: nil
  defp now_after(previous), do: max(System.system_time(:millisecond), previous)
end

defimpl Runic.Identity.Projectable, for: Jido.Session do
  def identity_document(session), do: Jido.Session.encode(session)
end
