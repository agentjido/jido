# Jido Agent Development Guide

## Commands
- **Test all**: `mix test`
- **Test single file**: `mix test test/path/to/test_file.exs`
- **Test with coverage**: `mix coveralls`
- **Build/compile**: `mix compile`
- **Quality check**: `mix quality` (format, dialyzer, credo)
- **Format code**: `mix format`
- **Type check**: `mix dialyzer`
- **Lint**: `mix credo`

## Code Style
- Pure Elixir library, not Phoenix/Nerves
- Use `snake_case` for functions/variables, `PascalCase` for modules
- Add `@moduledoc` and `@doc` to all public functions
- Use `@spec` for type specifications
- Pattern match with function heads instead of conditionals
- Return tagged tuples: `{:ok, result}` or `{:error, reason}`
- Use `with` statements for complex operations
- Prefix test modules with namespace: `JidoTest.ModuleName`
- Use `use Action` for action modules with name, description, schema
- Follow .cursorrules for detailed standards and examples