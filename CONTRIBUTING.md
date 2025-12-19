# Contributing to Jido

Welcome to the Jido contributor's guide! We're excited that you're interested in contributing to Jido, our framework for building autonomous, distributed agent systems in Elixir. This guide will help you understand our development process and standards.

## Getting Started

### Development Environment

1. **Elixir Version Requirements**
   - Jido requires Elixir ~> 1.17
   - We recommend using asdf or similar version manager

2. **Initial Setup**
   ```bash
   # Clone the repository
   git clone https://github.com/agentjido/jido.git
   cd jido

   # Install dependencies
   mix deps.get

   # Run tests to verify your setup
   mix test
   ```

3. **Quality Checks**
   ```bash
   # Run the full quality check suite
   mix quality

   # Or individual checks
   mix format                    # Format code
   mix compile --warnings-as-errors  # Check compilation
   mix dialyzer                  # Type checking
   mix credo --all              # Static analysis
   ```

## Code Organization

### Project Structure
```
.
├── lib/
│   ├── jido/
│   │   ├── actions/     # Core action implementations
│   │   ├── agents/      # Agent behaviors and implementations
│   │   ├── sensors/     # Sensor system components
│   │   ├── workflows/   # Workflow execution engines
│   │   └── utils/       # Utility functions
│   └── jido.ex          # Main entry point
├── test/
│   ├── jido/
│   │   └── ...         # Tests mirroring lib structure
│   ├── support/        # Test helpers and shared fixtures
│   └── test_helper.exs
├── guides/            # Documentation guides
└── mix.exs
```

### Core Components
- **Actions**: Discrete, composable units of work
- **Workflows**: Sequences of actions that accomplish larger goals
- **Agents**: Stateful entities that can plan and execute workflows
- **Sensors**: Real-time monitoring and data gathering components

## Development Guidelines

### Code Style

1. **Formatting**
   - Run `mix format` before committing
   - Follow standard Elixir style guide
   - Use `snake_case` for functions and variables
   - Use `PascalCase` for module names

2. **Documentation**
   - Add `@moduledoc` to every module
   - Document all public functions with `@doc`
   - Include examples when helpful
   - Keep guides up-to-date in the `guides/` directory
   - Use doctests for simple examples

3. **Type Specifications**
   ```elixir
   @type validation_error :: :invalid_name | :invalid_status
   
   @spec process(String.t()) :: {:ok, term()} | {:error, validation_error()}
   def process(input) do
     # Implementation
   end
   ```

### Testing

1. **Test Organization**
   ```elixir
   defmodule Jido.Test.Actions.FormatUserTest do
     use ExUnit.Case, async: true
     
     describe "run/2" do
       test "formats user data correctly" do
         # Test implementation
       end
       
       test "handles invalid input" do
         # Error case testing
       end
     end
   end
   ```

2. **Coverage Requirements**
   - Maintain high test coverage
   - Test both success and error paths
   - Include property-based tests for complex logic
   - Test async behavior where applicable

3. **Running Tests**
   ```bash
   # Run full test suite
   mix test

   # Run with coverage
   mix test --cover

   # Run specific test file
   mix test test/jido/actions/format_user_test.exs
   ```

### Error Handling

1. **Use With Patterns**
   ```elixir
   def complex_operation(input) do
     with {:ok, validated} <- validate(input),
          {:ok, processed} <- process(validated) do
       {:ok, processed}
     end
   end
   ```

2. **Return Values**
   - Use tagged tuples: `{:ok, result}` or `{:error, reason}`
   - Create specific error types for different failures
   - Never intentionally raise Exceptions, the Jido framework intentionally minimizes the use of exceptions.
   - Avoid silent failures
   - Document error conditions

### Performance Considerations

1. **Optimization**
   - Profile before optimizing
   - Document performance characteristics
   - Consider resource usage in distributed environments
   - Implement appropriate timeouts

2. **Resource Management**
   - Clean up resources properly
   - Handle large data sets efficiently
   - Consider memory usage in long-running processes

## Git Hooks and Conventional Commits

We use [`git_hooks`](https://hex.pm/packages/git_hooks) to enforce commit message conventions:

```bash
mix git_hooks.install
```

This installs a `commit-msg` hook that validates your commit messages follow the [Conventional Commits](https://www.conventionalcommits.org/) specification.

### Commit Message Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only changes |
| `style` | Changes that don't affect code meaning |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or correcting tests |
| `chore` | Changes to build process or auxiliary tools |
| `ci` | CI configuration changes |

### Examples

```bash
# Feature
git commit -m "feat(agents): add distributed execution support"

# Bug fix
git commit -m "fix(workflows): resolve race condition in parallel execution"

# Breaking change
git commit -m "feat(api)!: change action return type"
```

The hook will reject non-conforming commits, ensuring a clean changelog can be generated automatically.

## Pull Request Process

1. **Before Submitting**
   - Run the full quality check suite: `mix quality`
   - Ensure all tests pass
   - Update documentation if needed
   - Add tests for new functionality

2. **PR Guidelines**
   - Create a feature branch from `main`
   - Use descriptive commit messages following conventional commits
   - Reference any related issues
   - Keep changes focused and atomic

3. **Review Process**
   - PRs require at least one review
   - Address all review comments
   - Maintain a clean commit history
   - Update your branch if needed

## Release Process

1. **Version Numbers**
   - Follow semantic versioning
   - Update version in `mix.exs`
   - Update CHANGELOG.md

2. **Documentation**
   - Update guides if needed
   - Check all docstrings
   - Verify README is current

## Additional Resources

- [Hex Documentation](https://hexdocs.pm/jido)
- [GitHub Issues](https://github.com/agentjido/jido/issues)
- [GitHub Discussions](https://github.com/agentjido/jido/discussions)

## Questions or Problems?

If you have questions about contributing:
- Open a GitHub Discussion
- Check existing issues
- Review the guides directory

Thank you for contributing to Jido!