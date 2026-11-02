defmodule Jido.Signal.Router.DSLTest do
  use JidoSignalTest.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Router
  alias Jido.Signal.Router.Route
  alias JidoSignalTest.Fixtures.Signals.UserCreated

  defmodule UserRouter do
    use Jido.Signal.Router

    route(UserCreated, :created)
    route("user.*", :user_event)
    route("audit.**", :audit, -50)

    route("user.enrich", {__MODULE__, :has_email?, []}, :enrich, 90)

    def has_email?(signal), do: Map.has_key?(signal.data, :email)
  end

  defmodule EmptyRouter do
    use Jido.Signal.Router
  end

  defmodule AttributeRouter do
    use Jido.Signal.Router

    @path "attribute.route"
    @priority 25
    @expected %{status: :ready}

    route(@path, {__MODULE__, :matches_data?, [@expected]}, :attribute, @priority)

    def matches_data?(signal, expected), do: signal.data == expected
  end

  describe "use Jido.Signal.Router" do
    test "compiles routes in declaration order" do
      assert [
               %Route{path: "user.created", target: :created, priority: 0},
               %Route{path: "user.*", target: :user_event, priority: 0},
               %Route{path: "audit.**", target: :audit, priority: -50},
               %Route{path: "user.enrich", target: :enrich, priority: 90}
             ] = UserRouter.routes()

      assert %_{} = UserRouter.router()
      refute Router.empty?(UserRouter.router())
    end

    test "routes Signals through the compiled Router" do
      assert {:ok, signal} = UserCreated.new(%{user_id: "123"})
      assert {:ok, [:created, :user_event]} = UserRouter.route(signal)
      assert {:ok, [:created, :user_event]} = Router.route(UserRouter.router(), signal)
    end

    test "applies MFA match predicates compiled into the module" do
      assert %Route{match: {UserRouter, :has_email?, []}} =
               Enum.find(UserRouter.routes(), &(&1.path == "user.enrich"))

      signal = Signal.new!("user.enrich", %{email: "user@example.com"}, source: "/test")
      assert {:ok, [:enrich, :user_event]} = UserRouter.route(signal)

      unmatched = Signal.new!("user.enrich", %{name: "Ada"}, source: "/test")
      assert {:ok, [:user_event]} = UserRouter.route(unmatched)
    end

    test "evaluates module attributes in route declarations" do
      assert [
               %Route{
                 path: "attribute.route",
                 match: {AttributeRouter, :matches_data?, [%{status: :ready}]},
                 target: :attribute,
                 priority: 25
               }
             ] = AttributeRouter.routes()

      matching = Signal.new!("attribute.route", %{status: :ready}, source: "/test")
      other = Signal.new!("attribute.route", %{status: :waiting}, source: "/test")

      assert {:ok, [:attribute]} = AttributeRouter.route(matching)
      assert {:error, %Jido.Signal.Error.RoutingError{}} = AttributeRouter.route(other)
    end

    test "allows an empty Router module" do
      assert UserRouter.routes() != []
      assert EmptyRouter.routes() == []
      assert Router.empty?(EmptyRouter.router())
    end

    test "rejects invalid paths at compile time" do
      module = unique_module("InvalidPath")

      assert_raise CompileError, ~r/Path cannot contain consecutive dots/, fn ->
        create_module(
          module,
          quote do
            use Jido.Signal.Router
            route("invalid..path", :target)
          end
        )
      end
    end

    test "reports the route declaration line for invalid paths" do
      module = unique_module("InvalidPathLine")

      error =
        assert_raise CompileError, fn ->
          Code.compile_string("""
          defmodule #{inspect(module)} do
            use Jido.Signal.Router

            route("valid.path", :valid)
            route("invalid..path", :invalid)
          end
          """)
        end

      assert error.line == 5
      assert Exception.message(error) =~ "Path cannot contain consecutive dots"
    end

    test "rejects a newline at the end of a compiled path segment" do
      module = unique_module("NewlinePath")

      assert_raise CompileError, ~r/Path contains invalid characters/, fn ->
        create_module(
          module,
          quote do
            use Jido.Signal.Router
            route("a\n.b", :target)
          end
        )
      end
    end

    test "rejects non-static targets at their declaration line" do
      module = unique_module("AnonymousTarget")

      error =
        assert_raise CompileError, fn ->
          Code.compile_string("""
          defmodule #{inspect(module)} do
            use Jido.Signal.Router

            route("user.created", fn -> :created end)
          end
          """)
        end

      assert error.line == 4
      assert Exception.message(error) =~ "compiled route values must be static module data"
    end

    test "rejects runtime process targets at their declaration line" do
      module = unique_module("ProcessTarget")

      error =
        assert_raise CompileError, fn ->
          Code.compile_string("""
          defmodule #{inspect(module)} do
            use Jido.Signal.Router

            route("user.created", self())
          end
          """)
        end

      assert error.line == 4
      assert Exception.message(error) =~ "compiled route values must be static module data"
    end

    test "keeps escapable static target forms" do
      module = unique_module("StaticTargets")

      Code.compile_string("""
      defmodule #{inspect(module)} do
        use Jido.Signal.Router

        route("remote.capture", &Map.get/2)
        route("improper.list", [:head | :tail])
      end
      """)

      assert [
               %Route{target: remote_capture},
               %Route{target: [:head | :tail]}
             ] = module.routes()

      assert is_function(remote_capture, 2)
      signal = Signal.new!("improper.list", %{}, source: "/test")
      assert {:ok, [[:head | :tail]]} = module.route(signal)
      assert inspect(module.router()) =~ "→ [:head | :tail]"
    end

    test "rejects a loaded non-Signal module path at compile time" do
      module = unique_module("NotASignal")

      assert_raise CompileError, ~r/Expected a route path string or a Jido.Signal module/, fn ->
        create_module(
          module,
          quote do
            use Jido.Signal.Router
            route(String, :target)
          end
        )
      end
    end

    test "rejects anonymous match functions at compile time" do
      module = unique_module("AnonymousMatch")

      assert_raise CompileError, ~r/\{Module, :function, args\} MFA/, fn ->
        create_module(
          module,
          quote do
            use Jido.Signal.Router
            route("user.enrich", fn signal -> signal.data.email end, :enrich)
          end
        )
      end
    end

    test "rejects function captures as match predicates at compile time" do
      module = unique_module("CaptureMatch")

      assert_raise CompileError, ~r/\{Module, :function, args\} MFA/, fn ->
        create_module(
          module,
          quote do
            use Jido.Signal.Router
            route("user.enrich", &Map.get/2, :enrich)
          end
        )
      end
    end

    test "rejects use options" do
      module = unique_module("Options")

      assert_raise ArgumentError, ~r/does not accept options/, fn ->
        create_module(
          module,
          quote do
            use Jido.Signal.Router, routes: []
          end
        )
      end
    end
  end
end
