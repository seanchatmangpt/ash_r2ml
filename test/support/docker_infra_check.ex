# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Test.DockerInfraCheck do
  @moduledoc """
  Real, minimal preflight check for the live Docker/Ontop adversarial test
  infrastructure (the `xaas-db-1` PostgreSQL container on the `xaas_default`
  Docker network).

  The adversarial suites under `test/adversarial*` are Chicago-style tests
  that exercise a real running Ontop + PostgreSQL stack — they intentionally
  do not mock those boundaries. When that infra is not running locally,
  `System.cmd("docker", ["exec", "xaas-db-1", ...])` fails hard with a raw
  `exit_status 125` ("No such container") deep inside the test body, which
  reads as a test *failure* even though the real cause is a missing
  environment prerequisite, not a code defect.

  Call `container_running?/0` from a `setup_all` and return
  `{:skip, reason}` when it is `false`, so ExUnit reports these tests as
  **skipped** with a human-readable reason instead of failed.

  See `docs/adversarial-test-setup.md` for how to bring the infra up.
  """

  @container "xaas-db-1"
  @network "xaas_default"

  @skip_reason "Ontop/Docker infrastructure not running - see docs/adversarial-test-setup.md"

  @doc """
  Returns `true` only if the `xaas-db-1` container exists AND is actually
  running (a real `docker inspect` call, not a cached assumption).
  """
  def container_running? do
    case System.cmd("docker", ["inspect", "-f", "{{.State.Running}}", @container],
           stderr_to_stdout: true
         ) do
      {"true\n", 0} -> true
      _ -> false
    end
  rescue
    ErlangError -> false
  end

  @doc """
  Returns `true` only if the `xaas_default` Docker network exists.
  """
  def network_exists? do
    case System.cmd("docker", ["network", "inspect", @network], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    ErlangError -> false
  end

  @doc """
  Full preflight: infra is usable only if both the container is running and
  its network exists. Returns `:ok` or `{:skip, reason}` — plug the result
  directly into a `setup_all` block:

      setup_all do
        case AshR2RML.Test.DockerInfraCheck.ensure_infra() do
          :ok -> do_real_setup()
          skip -> skip
        end
      end
  """
  def ensure_infra do
    if container_running?() and network_exists?() do
      :ok
    else
      {:skip, @skip_reason}
    end
  end

  @doc """
  Convenience for `@moduletag skip: ...` / `@tag skip: ...`: returns `false`
  (do not skip) when the infra is present, or the human-readable skip reason
  string when it is absent. ExUnit tag values are evaluated when the test
  `.exs` file is required, which happens fresh on every `mix test` run (test
  files are not persistently `.beam`-cached the way `lib/` and
  `test/support/` are), so this reflects the real, current Docker state each
  time the suite runs — not a stale compile-time snapshot.
  """
  def skip_reason do
    case ensure_infra() do
      :ok -> false
      {:skip, reason} -> reason
    end
  end
end
