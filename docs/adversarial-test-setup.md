# Adversarial Test Infrastructure Setup

The suites under `test/adversarial/` and `test/adversarial_closure_test.exs`
are Chicago-style tests that exercise a real, running Ontop OBDA + PostgreSQL
stack. They deliberately do not mock the database or the Ontop engine.

## Prerequisite

A running PostgreSQL container named `xaas-db-1` attached to the Docker
network `xaas_default`.

Bring it up with the `xaas` project's own compose file (or an equivalent
standalone container attached to that network), for example:

```bash
docker network create xaas_default 2>/dev/null || true
docker run -d --name xaas-db-1 --network xaas_default \
  -e POSTGRES_PASSWORD=postgres \
  postgres:15
```

## Behavior when infra is absent

`test/support/docker_infra_check.ex` (`AshR2RML.Test.DockerInfraCheck`) runs a
real `docker inspect` preflight in each affected suite's `setup_all`/`setup`.
When `xaas-db-1` is not running, or the `xaas_default` network does not exist,
the affected tests are reported by ExUnit as **skipped**, with the reason:

```
Ontop/Docker infrastructure not running - see docs/adversarial-test-setup.md
```

This is a real ExUnit skip (`{:skip, reason}` from `setup_all`/`setup`), not a
failure and not a silently removed test — it still runs for real, against the
real Ontop/PostgreSQL stack, whenever that infra is up.
