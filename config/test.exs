# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

import Config

level = if System.get_env("DEBUG"), do: :debug, else: :info

config :logger, :console,
  level: level,
  format: "$date $time [$level] $metadata$message\n"
