# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.MixProject do
  @moduledoc false
  use Mix.Project

  @version "26.9.12"
  @name "AshR2RML"
  @description "W3C R2RML and RDF semantic mapping compiler for Ash Framework"
  @github_url "https://github.com/seanchatmangpt/ash_r2rml"

  def project do
    [
      app: :ash_r2rml,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: &docs/0,
      dialyzer: [plt_add_apps: [:jason, :mix], ignore_warnings: ".dialyzer_ignore.exs"],
      test_coverage: [
        tool: ExCoveralls,
        summary: [
          threshold: 70
        ]
      ],
      consolidate_protocols: Mix.env() == :prod,
      aliases: aliases(),
      name: @name,
      source_url: @github_url,
      homepage_url: "https://github.com/seanchatmangpt/ash_r2rml",
      description: @description
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.github": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def docs do
    [
      homepage_url: @github_url,
      source_url: @github_url,
      source_ref: "v#{@version}",
      main: "readme",
      extras: [
        {"README.md", title: "Home"},
        {"LICENSES/MIT.md", title: "License"},
        {"ash_r2rml.livemd", title: "AshR2RML Livebook"},
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Tutorials: ~r'documentation/tutorials',
        "How To": ~r'documentation/how_to',
        Topics: ~r'documentation/topics',
        "About AshR2RML": [
          "CHANGELOG.md"
        ]
      ],
      groups_for_modules: [
        AshR2RML: [
          AshR2RML,
          AshR2RML.Resource,
          AshR2RML.Compiler,
          AshR2RML.Mapping,
          AshR2RML.Ggen,
          AshR2RML.Ingestion,
          AshR2RML.OBDA,
          AshR2RML.Policy,
          AshR2RML.Provenance
        ],
        "GraphQL projection": [
          AshR2RML.Graphql,
          AshR2RML.Graphql.Info,
          AshR2RML.Graphql.Schema
        ],
        Reactor: ~r/AshR2RML\.Reactor/,
        Telemetry: ~r/AshR2RML\.Telemetry/,
        Internals: ~r/.*/
      ]
    ]
  end

  defp package do
    [
      maintainers: [
        "AshR2RML contributors"
      ],
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG* ash_r2rml.livemd priv),
      links: %{
        "GitHub" => @github_url,
        "Changelog" => "#{@github_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash, "~> 3.0 and >= 3.28.0"},
      {:ash_postgres, "~> 2.0", only: [:test]},
      {:ash_graphql, "~> 1.10", optional: true},
      {:absinthe, "~> 1.7", optional: true},
      {:ash_json_api, "~> 1.7", only: [:test]},
      {:ash_csv, "~> 0.9.8", only: [:test]},
      {:ash_cubdb, "~> 0.6.2", only: [:test]},
      {:spark, ">= 2.7.0"},
      {:rdf, "~> 3.0"},
      {:sparql, "~> 0.3.12"},
      {:sparql_client, "~> 0.5.1"},
      {:json_ld, "~> 1.0.1"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:igniter, ">= 0.6.29 and < 1.0.0-0", [env: :prod, hex: "igniter", repo: "hexpm", optional: true]},
      {:reactor, ">= 0.9.0", optional: true},
      {:ash_state_machine, "~> 0.2.12", only: [:dev, :test]},
      {:simple_sat, ">= 0.0.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.37", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.12", only: [:dev, :test]},
      {:git_ops, "~> 2.7", only: [:dev], runtime: false},
      {:credo, ">= 1.7.16", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 1.4.3", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18.0", only: [:dev, :test]},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.3", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      sobelow: "sobelow --skip",
      credo: "credo --strict",
      "spark.formatter": "spark.formatter --extensions AshR2RML.Resource",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshR2RML.Resource"
    ]
  end
end
