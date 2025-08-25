# CHANGELOG

<!-- %% CHANGELOG_ENTRIES %% -->

## Unreleased - 2025-08-25

### Added
- **Automatic Action Registration**: Skills can now declare required actions in their configuration using the `actions` field, which are automatically registered when the skill is mounted
- **Module Path Refactoring**: Moved action modules from `Jido.Actions.*` to `Jido.Tools.*` namespace for better alignment with `jido_action` library
- **Default Skills**: Agent server now uses default skills (`Jido.Skills.Basic` and `Jido.Skills.StateManager`) instead of hardcoded actions

### Breaking Changes
- **Action module paths**: All action modules moved from `Jido.Actions.*` to `Jido.Tools.*` to align with the `jido_action` library

### Changed
- **Skill configuration**: Skills can now declare required actions using the `actions` field for automatic registration
- **Agent options**: Both `actions:` and `skills:` options are supported, with skills providing the preferred declarative approach

### Fixed
- Task update action now only updates provided fields instead of overwriting with nil values
- State manager update action now uses `:update` operation instead of `:set` for proper semantic behavior
- Improved error handling for action registration failures

## 1.1.0-rc.1 - 2025-02-18

- Address open Credo Errors
- Add documentation
- Clean up README in prep for 1.1 release

## 1.1.0-rc - 2025-02-08

- Stateful Agents
