# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

import Config

level = if System.get_env("DEBUG"), do: :debug, else: :info

config :git_ops,
  mix_project: Mix.Project.get!(),
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/seanchatmangpt/ash_r2rml",
  types: [tidbit: [hidden?: true], important: [header: "Important Changes"]],
  tags: [allowed: ["backend"], allow_untagged?: true],
  manage_mix_version?: true,
  manage_readme_version: "README.md",
  version_tag_prefix: "v"

config :logger, :console,
  level: level,
  format: "$date $time [$level] $metadata$message\n"
