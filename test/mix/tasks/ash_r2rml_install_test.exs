# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshR2rml.InstallTest do
  @moduledoc """
  Chicago-style: runs the real Igniter task (`Mix.Tasks.AshR2rml.Install.igniter/1`) against
  a real `Igniter.Test.test_project/1` in-memory project and asserts on the real resulting
  source patch / notice content -- no mocked Igniter collaborator.
  """
  use ExUnit.Case, async: true

  import Igniter.Test

  test "without --target, wires up the formatter and leaves a manual-instructions notice" do
    igniter =
      test_project()
      |> Igniter.compose_task("ash_r2rml.install", [])

    assert Enum.any?(igniter.notices, &(&1 =~ "AshR2RML installed successfully!"))
    assert Enum.any?(igniter.notices, &(&1 =~ "--target MyApp.SomeResource"))
  end

  test "with --target, patches the target module with the extension and a starter r2rml block" do
    igniter =
      test_project(
        files: %{
          "lib/my_app/post.ex" => """
          defmodule MyApp.Post do
            use Ash.Resource,
              domain: MyApp.Domain,
              data_layer: AshPostgres.DataLayer
          end
          """
        }
      )
      |> Igniter.compose_task("ash_r2rml.install", ["--target", "MyApp.Post"])

    source = Rewrite.source!(igniter.rewrite, "lib/my_app/post.ex")
    content = Rewrite.Source.get(source, :content)

    assert content =~ "AshR2RML.Resource"
    assert content =~ "r2rml do"
  end

  test "with --target, re-running against an already-patched module does not duplicate the r2rml block" do
    igniter =
      test_project(
        files: %{
          "lib/my_app/post.ex" => """
          defmodule MyApp.Post do
            use Ash.Resource,
              domain: MyApp.Domain,
              data_layer: AshPostgres.DataLayer,
              extensions: [AshR2RML.Resource]

            r2rml do
            end
          end
          """
        }
      )
      |> Igniter.compose_task("ash_r2rml.install", ["--target", "MyApp.Post"])

    source = Rewrite.source!(igniter.rewrite, "lib/my_app/post.ex")
    content = Rewrite.Source.get(source, :content)

    assert length(String.split(content, "r2rml do")) == 2
  end
end
