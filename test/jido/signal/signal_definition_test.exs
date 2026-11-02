defmodule Jido.Signal.DefinitionTest do
  use JidoSignalTest.Case, async: true

  alias Jido.Signal.ID

  defmodule UserCreated do
    use Jido.Signal,
      type: "user.created",
      default_source: "/accounts",
      datacontenttype: "application/json",
      dataschema: "https://example.com/schemas/user-created",
      schema:
        Zoi.object(%{
          user_id: Zoi.string(),
          email:
            Zoi.string()
            |> Zoi.refine({Jido.Signal.DefinitionTest, :valid_email, []}),
          count: Zoi.integer() |> Zoi.default(1)
        })
  end

  defmodule ExplicitSource do
    use Jido.Signal,
      type: "explicit.source",
      schema: Zoi.object(%{value: Zoi.string()})
  end

  defmodule TextMessage do
    use Jido.Signal,
      type: "text.message",
      default_source: "/messages",
      schema: Zoi.string()
  end

  defmodule OpaqueMessage do
    use Jido.Signal,
      type: "opaque.message",
      default_source: "/messages"
  end

  defmodule MarkerOnly do
    def __signal_definition__, do: %{}
  end

  describe "typed Signal construction" do
    test "uses configured envelope values and validates data" do
      assert {:ok, signal} =
               UserCreated.new(%{user_id: "123", email: "user@example.com"})

      assert signal.type == "user.created"
      assert signal.source == "/accounts"
      assert signal.specversion == "1.0"
      assert signal.time == nil
      assert signal.datacontenttype == "application/json"
      assert signal.dataschema == "https://example.com/schemas/user-created"
      assert signal.data.count == 1
      assert ID.valid?(signal.id)
    end

    test "supports an explicit source override" do
      assert {:ok, signal} =
               UserCreated.new(
                 %{user_id: "123", email: "user@example.com"},
                 source: "/imports"
               )

      assert signal.source == "/imports"
    end

    test "requires source when the definition has no default" do
      assert {:error, error} = ExplicitSource.new(%{value: "test"})
      assert error =~ "source"

      assert {:ok, signal} = ExplicitSource.new(%{value: "test"}, source: "/test")
      assert signal.source == "/test"
    end

    test "returns Zoi validation errors without a package wrapper" do
      assert {:error, [%Zoi.Error{} = error]} =
               UserCreated.new(%{user_id: "123", email: "not-an-email"})

      assert error.path == [:email]
      assert error.message == "must contain @"

      assert_raise Zoi.ParseError, fn ->
        UserCreated.new!(%{user_id: "123", email: "not-an-email"})
      end
    end

    test "accepts non-map data defined by Zoi" do
      assert {:ok, text_signal} = TextMessage.new("hello")
      assert text_signal.data == "hello"

      value = {:binary, <<0, 1, 2>>}
      assert {:ok, opaque_signal} = OpaqueMessage.new(value)
      assert opaque_signal.data == value
    end

    test "keeps type and data fixed by the definition" do
      assert {:ok, signal} =
               UserCreated.new(
                 %{user_id: "123", email: "user@example.com"},
                 type: "other.type",
                 data: %{other: true}
               )

      assert signal.type == "user.created"
      assert signal.data.user_id == "123"
    end

    test "exposes the static definition" do
      assert UserCreated.type() == "user.created"
      assert UserCreated.default_source() == "/accounts"
      assert UserCreated.datacontenttype() == "application/json"
      assert UserCreated.dataschema() == "https://example.com/schemas/user-created"
      assert %Zoi.Types.Map{} = UserCreated.schema()
      assert Jido.Signal.defined?(UserCreated)
      refute Jido.Signal.defined?(Jido.Signal)
      refute Jido.Signal.defined?(String)
      refute Jido.Signal.defined?(:not_a_module)
      refute Jido.Signal.defined?("user.created")
    end

    test "keeps dataschema fixed by the definition for all option key forms" do
      for opts <- [
            [dataschema: "https://example.com/other"],
            %{dataschema: nil},
            %{"dataschema" => "https://example.com/other"}
          ] do
        assert {:ok, signal} = UserCreated.new(%{user_id: "123", email: "user@example.com"}, opts)
        assert signal.dataschema == UserCreated.dataschema()
        assert {:ok, signal} = TextMessage.new("hello", opts)
        assert signal.dataschema == nil
      end
    end

    test "does not identify an incomplete marker module as a Signal module" do
      refute Jido.Signal.defined?(MarkerOnly)

      assert {:error, %Jido.Signal.Error.InvalidInputError{}} =
               Jido.Signal.Router.path(MarkerOnly)
    end
  end

  describe "static Zoi schema checks" do
    test "accepts named MFA effects" do
      assert {:ok, data} =
               UserCreated.validate_data(%{user_id: "123", email: "user@example.com"})

      assert data.count == 1
    end

    test "rejects anonymous functions at compile time" do
      module = unique_module("AnonymousSchema")

      assert_raise CompileError, ~r/anonymous functions are not supported/, fn ->
        create_module(
          module,
          quote do
            use Jido.Signal,
              type: "anonymous.schema",
              default_source: "/test",
              schema:
                Zoi.object(%{
                  value: Zoi.string() |> Zoi.refine(fn _value, _opts -> :ok end)
                })
          end
        )
      end
    end

    test "rejects anonymous functions nested in named MFA arguments" do
      module = unique_module("AnonymousMFAArgument")

      assert_raise CompileError, ~r/anonymous functions are not supported/, fn ->
        create_module(
          module,
          quote do
            runtime_function = fn -> :runtime end

            use Jido.Signal,
              type: "anonymous.mfa.argument",
              default_source: "/test",
              schema:
                Zoi.string()
                |> Zoi.refine({Jido.Signal.DefinitionTest, :valid_email, [runtime_function]})
          end
        )
      end
    end

    test "rejects runtime process values nested in schema data" do
      module = unique_module("RuntimeSchemaValue")

      assert_raise CompileError, ~r/runtime process values are not supported/, fn ->
        create_module(
          module,
          quote do
            runtime_reference = make_ref()

            use Jido.Signal,
              type: "runtime.schema.value",
              default_source: "/test",
              schema:
                Zoi.string()
                |> Zoi.refine({Jido.Signal.DefinitionTest, :valid_email, [runtime_reference]})
          end
        )
      end
    end

    test "rejects improper lists nested in schema data" do
      module = unique_module("ImproperSchemaList")

      assert_raise CompileError, ~r/improper list tails are not supported/, fn ->
        create_module(
          module,
          quote do
            use Jido.Signal,
              type: "improper.schema.list",
              default_source: "/test",
              schema: Zoi.string(example: ["head" | :tail])
          end
        )
      end
    end

    test "rejects lazy schemas at compile time" do
      module = unique_module("LazySchema")

      assert_raise CompileError, ~r/lazy schemas are not supported/, fn ->
        create_module(
          module,
          quote do
            use Jido.Signal,
              type: "lazy.schema",
              default_source: "/test",
              schema: Zoi.lazy(fn -> Zoi.object(%{value: Zoi.string()}) end)
          end
        )
      end
    end

    test "rejects malformed Zoi effects at compile time" do
      module = unique_module("MalformedEffect")

      assert_raise CompileError, ~r/custom schema effects must use.*MFA/, fn ->
        create_module(
          module,
          quote do
            use Jido.Signal,
              type: "malformed.effect",
              default_source: "/test",
              schema:
                Zoi.object(%{
                  value: Zoi.string() |> Zoi.refine(:not_an_mfa)
                })
          end
        )
      end
    end

    test "validates envelope defaults at compile time" do
      for {suffix, opts} <- [
            {"EmptyType", [type: "", default_source: "/test"]},
            {"InvalidSource", [type: "invalid.source", default_source: "bad source"]},
            {"InvalidSchemaURI",
             [
               type: "invalid.schema.uri",
               default_source: "/test",
               dataschema: "/relative"
             ]}
          ] do
        module = unique_module(suffix)

        assert_raise CompileError, fn ->
          create_module(
            module,
            quote do
              use Jido.Signal, unquote(opts)
            end
          )
        end
      end
    end

    test "returns an error for invalid construction options" do
      assert {:error, error} =
               UserCreated.new(%{user_id: "123", email: "user@example.com"}, [:invalid])

      assert error =~ "options"
    end

    test "rejects non-Zoi schemas at compile time" do
      module = unique_module("InvalidSchema")

      assert_raise CompileError, ~r/must be a Zoi schema/, fn ->
        create_module(
          module,
          quote do
            use Jido.Signal,
              type: "invalid.schema",
              default_source: "/test",
              schema: :not_a_schema
          end
        )
      end
    end

    test "supports a static schema stored in a module-body variable" do
      module = unique_module("SchemaVariable")

      create_module(
        module,
        quote do
          data_schema = Zoi.list(Zoi.integer())

          use Jido.Signal,
            type: "schema.variable",
            default_source: "/test",
            schema: data_schema
        end
      )

      assert {:ok, signal} = module.new([1, 2, 3])
      assert signal.data == [1, 2, 3]
    end
  end

  def valid_email(email, _opts) do
    if String.contains?(email, "@"), do: :ok, else: {:error, "must contain @"}
  end
end
