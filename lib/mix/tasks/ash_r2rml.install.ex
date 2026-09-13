# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshR2rml.Install do
    use Igniter.Mix.Task

    @shortdoc "Installs AshR2RML into an Ash project using Igniter"
    @moduledoc """
    Automated Igniter installer task for AshR2RML.

    Adds `AshR2RML.Resource` extensions, configures `.formatter.exs`, and sets up
    `r2rml` Spark DSL formatting. Pass `--target` to also patch a specific resource
    module automatically instead of getting manual instructions.

    ## Usage

        mix igniter.install ash_r2rml
        mix ash_r2rml.install
        mix ash_r2rml.install --target MyApp.SomeResource
    """

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ash_r2rml,
        example: "mix ash_r2rml.install --target MyApp.SomeResource",
        positional: [],
        schema: [target: :string],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      base =
        igniter
        |> Igniter.Project.Formatter.import_dep(:ash_r2rml)
        |> Igniter.Project.Formatter.add_formatter_plugin(AshR2RML.Formatter)

      case igniter.args.options[:target] do
        nil ->
          # No --target given (e.g. plain `mix igniter.install ash_r2rml`) -- formatter
          # is still wired up automatically; the resource patch needs a target module,
          # so fall back to a real, disclosed manual-instructions notice rather than
          # guessing which module to patch.
          Igniter.add_notice(base, """
          AshR2RML installed successfully!

          Add `extensions: [AshR2RML.Resource]` to your Ash.Resource modules:

              use Ash.Resource,
                domain: MyApp.Domain,
                data_layer: AshPostgres.DataLayer,
                extensions: [AshR2RML.Resource]

              r2rml do
                class "https://schema.org/Person"
                subject do
                  template "https://example.org/people/{id}"
                end
              end

          Or re-run with `--target MyApp.SomeResource` to patch a specific module
          automatically.
          """)

        target ->
          target_module = Igniter.Project.Module.parse(target)

          base
          |> Spark.Igniter.add_extension(target_module, Ash.Resource, :extensions, AshR2RML.Resource)
          |> add_starter_dsl_block(target_module)
      end
    end

    # Adds a minimal, real starter `r2rml do ... end` block right after the target
    # module's `use Ash.Resource, ...` call, so it compiles immediately after install
    # rather than needing hand-authored DSL content.
    #
    # Idempotent: uses `Igniter.Code.Pattern.move_to/2` (ExAST) to search the
    # module body for an existing `r2rml do ... end` block first, so
    # re-running `mix ash_r2rml.install --target` against an already-patched
    # module does not insert a second, duplicate block.
    defp add_starter_dsl_block(igniter, target_module) do
      Igniter.Project.Module.find_and_update_module!(igniter, target_module, fn zipper ->
        if match?({:ok, _}, Igniter.Code.Pattern.move_to(zipper, "r2rml do ... end")) do
          {:ok, zipper}
        else
          case Igniter.Code.Module.move_to_use(zipper, Ash.Resource) do
            {:ok, use_zipper} ->
              {:ok,
               Igniter.Code.Common.add_code(
                 use_zipper,
                 """
                 r2rml do
                 end
                 """,
                 placement: :after
               )}

            :error ->
              {:ok, zipper}
          end
        end
      end)
    end
  end
else
  defmodule Mix.Tasks.AshR2rml.Install do
    use Mix.Task

    @shortdoc "Installs AshR2RML (manual instructions)"

    @impl Mix.Task
    def run(_args) do
      Mix.shell().info("""
      AshR2RML manual installation steps:

      1. Add `:ash_r2rml` to your `mix.exs` dependencies:
         {:ash_r2rml, "~> 0.1.0"}

      2. Add `import_deps: [:ash_r2rml]` and `plugins: [AshR2RML.Formatter]` to your `.formatter.exs`.

      3. Add `extensions: [AshR2RML.Resource]` to your `Ash.Resource` modules.
      """)
    end
  end
end
