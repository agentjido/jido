defmodule Jido.Joi do
  @moduledoc """
  The Jido data-schema facade.

  Joi exposes the Zoi 0.19 schema API that Jido uses. Joi schemas are ordinary
  Zoi schemas. The facade adds Jido policies for input parsing, checked state
  initialization, exact stored-value validation, and JSON Schema projection.

  Use `parse/3` for external input, `initialize/3` to create stored state, and
  `validate/3` to check an existing stored value.
  """

  @type schema :: Zoi.schema()
  @type input :: Zoi.input()
  @type result :: Zoi.result()
  @type options :: Zoi.options()
  @type error :: Zoi.Error.t()

  # This is the complete public Zoi 0.19 function surface. The explicit list is
  # a version manifest. A Zoi upgrade must update this list in review.
  @zoi_delegates [
    any: 0,
    any: 1,
    array: 0,
    array: 1,
    array: 2,
    atom: 0,
    atom: 1,
    base64: 0,
    base64: 1,
    base64url: 0,
    base64url: 1,
    boolean: 0,
    boolean: 1,
    codec: 3,
    coerce: 1,
    contains: 2,
    contains: 3,
    date: 0,
    date: 1,
    datetime: 0,
    datetime: 1,
    decimal: 0,
    decimal: 1,
    default: 2,
    default: 3,
    describe: 1,
    description: 1,
    discriminated_union: 2,
    discriminated_union: 3,
    downcase: 1,
    downcase: 2,
    email: 0,
    email: 1,
    encode: 2,
    encode: 3,
    encode!: 2,
    encode!: 3,
    ends_with: 2,
    ends_with: 3,
    enum: 1,
    enum: 2,
    example: 1,
    exclusive_union: 1,
    exclusive_union: 2,
    extend: 2,
    extend: 3,
    float: 0,
    float: 1,
    from_json_schema: 1,
    function: 0,
    function: 1,
    gt: 2,
    gt: 3,
    gte: 2,
    gte: 3,
    hex: 0,
    hex: 1,
    integer: 0,
    integer: 1,
    intersection: 1,
    intersection: 2,
    ipv4: 0,
    ipv4: 1,
    ipv6: 0,
    ipv6: 1,
    json: 0,
    json: 1,
    jwt: 0,
    jwt: 1,
    keyword: 1,
    keyword: 2,
    lazy: 1,
    lazy: 2,
    length: 2,
    length: 3,
    list: 0,
    list: 1,
    list: 2,
    literal: 1,
    literal: 2,
    lt: 2,
    lt: 3,
    lte: 2,
    lte: 3,
    macro: 0,
    macro: 1,
    map: 0,
    map: 1,
    map: 2,
    map: 3,
    map_set: 0,
    map_set: 1,
    map_set: 2,
    max: 2,
    max: 3,
    metadata: 1,
    min: 2,
    min: 3,
    module: 0,
    module: 1,
    multiple_of: 2,
    multiple_of: 3,
    naive_datetime: 0,
    naive_datetime: 1,
    negative: 1,
    negative: 2,
    non_negative: 1,
    non_negative: 2,
    none: 0,
    none: 1,
    null: 0,
    null: 1,
    nullable: 1,
    nullable: 2,
    nullish: 1,
    nullish: 2,
    number: 0,
    number: 1,
    object: 1,
    object: 2,
    omit: 2,
    one_of: 2,
    one_of: 3,
    optional: 1,
    pick: 2,
    pid: 0,
    pid: 1,
    port: 0,
    port: 1,
    positive: 1,
    positive: 2,
    prettify_errors: 1,
    reference: 0,
    reference: 1,
    refine: 2,
    regex: 2,
    regex: 3,
    required: 1,
    starts_with: 2,
    starts_with: 3,
    string: 0,
    string: 1,
    string_boolean: 0,
    string_boolean: 1,
    struct: 1,
    struct: 2,
    struct: 3,
    time: 0,
    time: 1,
    to_downcase: 1,
    to_struct: 2,
    to_upcase: 1,
    transform: 2,
    treefy_errors: 1,
    trim: 1,
    tuple: 1,
    tuple: 2,
    type_spec: 1,
    type_spec: 2,
    union: 1,
    union: 2,
    upcase: 1,
    upcase: 2,
    url: 0,
    url: 1,
    uuid: 0,
    uuid: 1
  ]
  @zoi_overrides [parse: 2, parse: 3, parse!: 2, parse!: 3, to_json_schema: 1]

  for {name, arity} <- @zoi_delegates do
    args = Macro.generate_arguments(arity, __MODULE__)
    defdelegate unquote(name)(unquote_splicing(args)), to: Zoi
  end

  @doc "Parse external input with a Joi schema."
  @spec parse(schema(), input(), options()) :: result()
  def parse(schema, input, opts \\ []), do: Zoi.parse(schema, input, opts)

  @doc "Parse external input and raise `Jido.Joi.ParseError` on failure."
  @spec parse!(schema(), input(), options()) :: term()
  def parse!(schema, input, opts \\ []) do
    case parse(schema, input, opts) do
      {:ok, value} -> value
      {:error, errors} -> raise Jido.Joi.ParseError, errors: errors
    end
  end

  @doc "Initialize stored state with checked defaults."
  @spec initialize(schema(), input(), options()) :: result()
  def initialize(schema, input, opts \\ []) do
    Jido.Joi.Runtime.initialize(schema, input, opts)
  end

  @doc "Validate an existing stored value without changing it."
  @spec validate(schema(), input(), options()) :: :ok | {:error, [error()]}
  def validate(schema, value, opts \\ []) do
    Jido.Joi.Runtime.validate(schema, value, opts)
  end

  @doc "Project a Joi schema to the common Jido JSON Schema form."
  @spec to_json_schema(schema()) :: map()
  def to_json_schema(schema), do: Zoi.to_json_schema(schema)

  @doc false
  def facade_exports, do: Enum.sort(@zoi_delegates ++ @zoi_overrides)

  @doc false
  def facade_complete? do
    Enum.sort(Zoi.__info__(:functions)) == facade_exports()
  end
end

defmodule Jido.Joi.ParseError do
  @moduledoc "Raised when `Jido.Joi.parse!/3` cannot parse input."
  defexception [:errors]

  @impl true
  def message(%__MODULE__{errors: errors}) when is_list(errors) do
    """
    Parsing error:

    #{Jido.Joi.prettify_errors(errors)}
    """
  end
end
