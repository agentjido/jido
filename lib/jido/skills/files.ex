defmodule Jido.Skills.Files do
  @moduledoc """
  A skill that provides file system operations for agents.

  This skill includes comprehensive file and directory manipulation actions:
  - Reading and writing files
  - Creating and deleting directories
  - Copying and moving files
  - Listing directory contents
  - File system utilities

  These actions enable agents to interact with the file system for data
  persistence, file processing, and general file management tasks.
  """

  use Jido.Skill,
    name: "files",
    description: "Provides file system operations and utilities for agents",
    category: "IO",
    tags: ["files", "filesystem", "io", "storage"],
    vsn: "1.0.0",
    opts_key: :files,
    opts_schema: [],
    signal_patterns: [
      "jido.files.**"
    ],
    actions: [
      Jido.Tools.Files.ReadFile,
      Jido.Tools.Files.WriteFile,
      Jido.Tools.Files.CopyFile,
      Jido.Tools.Files.MoveFile,
      Jido.Tools.Files.DeleteFile,
      Jido.Tools.Files.MakeDirectory,
      Jido.Tools.Files.ListDirectory
    ]

  alias Jido.Instruction

  @impl true
  @spec router(keyword()) :: [Jido.Signal.Router.Route.t()]
  def router(_opts) do
    [
      %Jido.Signal.Router.Route{
        path: "jido.files.read",
        target: %Instruction{action: Jido.Tools.Files.ReadFile},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.files.write",
        target: %Instruction{action: Jido.Tools.Files.WriteFile},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.files.copy",
        target: %Instruction{action: Jido.Tools.Files.CopyFile},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.files.move",
        target: %Instruction{action: Jido.Tools.Files.MoveFile},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.files.delete",
        target: %Instruction{action: Jido.Tools.Files.DeleteFile},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.files.mkdir",
        target: %Instruction{action: Jido.Tools.Files.MakeDirectory},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.files.list",
        target: %Instruction{action: Jido.Tools.Files.ListDirectory},
        priority: 0
      }
    ]
  end

  @impl true
  @spec handle_signal(Jido.Signal.t(), Jido.Skill.t()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def handle_signal(%Jido.Signal{} = signal, _skill) do
    {:ok, signal}
  end

  @impl true
  @spec transform_result(Jido.Signal.t(), term(), Jido.Skill.t()) ::
          {:ok, term()} | {:error, any()}
  def transform_result(_signal, result, _skill) do
    {:ok, result}
  end
end
