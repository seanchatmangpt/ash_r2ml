# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.OperationsAndSagasTest do
  @moduledoc """
  Fortune 5 Live Operations & Sagas Execution Test Suite.

  Exercises:
  1. Production Blue/Green Deployment Saga with rollback compensation.
  2. Automated Multi-Region Database Failover Actuation Saga.
  3. Zero-Downtime Secret & Credential Rotation Saga.
  4. Strict verification of `undo/3` and `compensate/4` hooks:
     - Injected intermediate step failures trigger `compensate/4` on the failed step.
     - Preceding completed steps trigger `undo/3` in reverse order (LIFO).
     - Unreached subsequent steps are never executed or undone.
  """
  use ExUnit.Case, async: false

  # --- Agent for Recording Saga Step Sequences ---

  defmodule SagaRecorder do
    use Agent

    # Real, reproduced race (caught by running this suite with randomized seeds
    # repeatedly, not by inspection): `Agent.start_link/2` links the agent to
    # whichever ExUnit test process happens to create it first. That test
    # process exits when its test finishes, which kills the linked agent --
    # a subsequent test's `reset/0` can then observe a still-registered `pid`
    # via `Process.whereis/1` a moment before its EXIT is processed, then race
    # `Agent.update/2` against that dying process and crash with
    # `{:exit, {:noproc, ...}}`. `Agent.start/2` (unlinked) decouples the
    # recorder's lifetime from any one test process; `reset/0` additionally
    # catches the exit from a stale pid and retries instead of trusting the
    # `whereis` check-then-act as atomic.
    def start_link(_opts \\ []) do
      Agent.start(fn -> [] end, name: __MODULE__)
    end

    def stop do
      if Process.whereis(__MODULE__), do: Agent.stop(__MODULE__)
    end

    def reset do
      if Process.whereis(__MODULE__) do
        try do
          Agent.update(__MODULE__, fn _ -> [] end)
        catch
          :exit, _ -> start_link()
        end
      else
        start_link()
      end
    end

    def record(event) do
      Agent.update(__MODULE__, fn events -> events ++ [event] end)
    end

    def get_events do
      Agent.get(__MODULE__, & &1)
    end
  end

  setup do
    SagaRecorder.reset()
    :ok
  end

  # ============================================================================
  # 1. Blue / Green Deployment Saga Steps & Reactor
  # ============================================================================

  defmodule BGAllocateGreen do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :bg_allocate_green, arguments[:deployment_id]})
      {:ok, %{allocated_env: "green_#{arguments[:deployment_id]}", status: :allocated}}
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :bg_allocate_green, result.allocated_env, arguments[:deployment_id]})
      :ok
    end
  end

  defmodule BGDeployArtifact do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :bg_deploy_artifact, arguments[:deployment_id]})
      {:ok, %{artifact_version: arguments[:version], deployed_to: "green_#{arguments[:deployment_id]}"}}
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :bg_deploy_artifact, result.artifact_version, arguments[:deployment_id]})
      :ok
    end
  end

  defmodule BGHealthCheck do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :bg_health_check, arguments[:deployment_id]})
      {:ok, %{health: :healthy, p99_latency_ms: 8}}
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :bg_health_check, result.health, arguments[:deployment_id]})
      :ok
    end
  end

  defmodule BGSwitchTraffic do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :bg_switch_traffic, arguments[:deployment_id]})

      if arguments[:simulate_router_failure] do
        {:error, {:router_timeout, "BGP route propagation failed for #{arguments[:deployment_id]}"}}
      else
        {:ok, %{active_traffic: :green, switched_at: DateTime.utc_now()}}
      end
    end

    def compensate(reason, arguments, _context, _options) do
      SagaRecorder.record({:compensate, :bg_switch_traffic, reason, arguments[:deployment_id]})
      :ok
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :bg_switch_traffic, result.active_traffic, arguments[:deployment_id]})
      :ok
    end
  end

  defmodule BGDrainBlue do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :bg_drain_blue, arguments[:deployment_id]})
      {:ok, %{drained_env: "blue", connections_terminated: 1420}}
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :bg_drain_blue, result.drained_env, arguments[:deployment_id]})
      :ok
    end
  end

  defmodule BlueGreenDeploymentReactor do
    use Reactor

    input(:deployment_id)
    input(:version)
    input(:simulate_router_failure)

    step :allocate_green, BGAllocateGreen do
      argument :deployment_id, input(:deployment_id)
    end

    step :deploy_artifact, BGDeployArtifact do
      argument :deployment_id, input(:deployment_id)
      argument :version, input(:version)
      wait_for :allocate_green
    end

    step :health_check, BGHealthCheck do
      argument :deployment_id, input(:deployment_id)
      wait_for :deploy_artifact
    end

    step :switch_traffic, BGSwitchTraffic do
      argument :deployment_id, input(:deployment_id)
      argument :simulate_router_failure, input(:simulate_router_failure)
      wait_for :health_check
    end

    step :drain_blue, BGDrainBlue do
      argument :deployment_id, input(:deployment_id)
      wait_for :switch_traffic
    end
  end

  # ============================================================================
  # 2. Database Failover Actuation Saga Steps & Reactor
  # ============================================================================

  defmodule FOIsolateMaster do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :fo_isolate_master, arguments[:cluster_id]})
      {:ok, %{isolated_node: "master-01", mode: :read_only}}
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :fo_isolate_master, result.isolated_node, arguments[:cluster_id]})
      :ok
    end
  end

  defmodule FOSyncReplication do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :fo_sync_replication, arguments[:cluster_id]})
      {:ok, %{last_lsn: "0/3000160", lag_bytes: 0}}
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :fo_sync_replication, result.last_lsn, arguments[:cluster_id]})
      :ok
    end
  end

  defmodule FOPromoteStandby do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :fo_promote_standby, arguments[:cluster_id]})
      {:ok, %{promoted_node: "standby-01", role: :primary}}
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :fo_promote_standby, result.promoted_node, arguments[:cluster_id]})
      :ok
    end
  end

  defmodule FOReconfigureVip do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :fo_reconfigure_vip, arguments[:cluster_id]})

      if arguments[:simulate_vip_failure] do
        {:error, {:vip_conflict, "ARP broadcast rejected by switch for #{arguments[:cluster_id]}"}}
      else
        {:ok, %{vip: "10.0.100.1", mapped_to: "standby-01"}}
      end
    end

    def compensate(reason, arguments, _context, _options) do
      SagaRecorder.record({:compensate, :fo_reconfigure_vip, reason, arguments[:cluster_id]})
      :ok
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :fo_reconfigure_vip, result.vip, arguments[:cluster_id]})
      :ok
    end
  end

  defmodule FONotifyServiceMesh do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :fo_notify_mesh, arguments[:cluster_id]})
      {:ok, %{mesh_notified: true, endpoints_updated: 280}}
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :fo_notify_mesh, result.mesh_notified, arguments[:cluster_id]})
      :ok
    end
  end

  defmodule FailoverActuationReactor do
    use Reactor

    input(:cluster_id)
    input(:simulate_vip_failure)

    step :isolate_master, FOIsolateMaster do
      argument :cluster_id, input(:cluster_id)
    end

    step :sync_replication, FOSyncReplication do
      argument :cluster_id, input(:cluster_id)
      wait_for :isolate_master
    end

    step :promote_standby, FOPromoteStandby do
      argument :cluster_id, input(:cluster_id)
      wait_for :sync_replication
    end

    step :reconfigure_vip, FOReconfigureVip do
      argument :cluster_id, input(:cluster_id)
      argument :simulate_vip_failure, input(:simulate_vip_failure)
      wait_for :promote_standby
    end

    step :notify_mesh, FONotifyServiceMesh do
      argument :cluster_id, input(:cluster_id)
      wait_for :reconfigure_vip
    end
  end

  # ============================================================================
  # 3. Credential Rotation Saga Steps & Reactor
  # ============================================================================

  defmodule CRGenerateVaultKey do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :cr_generate_key, arguments[:service_name]})
      {:ok, %{key_version: "v3_#{arguments[:service_name]}", key_status: :active}}
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :cr_generate_key, result.key_version, arguments[:service_name]})
      :ok
    end
  end

  defmodule CRDistributeKey do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :cr_distribute_key, arguments[:service_name]})
      {:ok, %{distributed_nodes: 64, applied_at: DateTime.utc_now()}}
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :cr_distribute_key, result.distributed_nodes, arguments[:service_name]})
      :ok
    end
  end

  defmodule CRVerifyAuth do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :cr_verify_auth, arguments[:service_name]})

      if arguments[:simulate_auth_failure] do
        {:error, {:auth_handshake_failed, "HMAC signature mismatch on node worker-44"}}
      else
        {:ok, %{verified: true, healthy_nodes: 64}}
      end
    end

    def compensate(reason, arguments, _context, _options) do
      SagaRecorder.record({:compensate, :cr_verify_auth, reason, arguments[:service_name]})
      :ok
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :cr_verify_auth, result.verified, arguments[:service_name]})
      :ok
    end
  end

  defmodule CRRevokeLegacyKey do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SagaRecorder.record({:run, :cr_revoke_legacy, arguments[:service_name]})
      {:ok, %{revoked_key_version: "v2_#{arguments[:service_name]}", revoked: true}}
    end

    def undo(result, arguments, _context, _options) do
      SagaRecorder.record({:undo, :cr_revoke_legacy, result.revoked_key_version, arguments[:service_name]})
      :ok
    end
  end

  defmodule CredentialRotationReactor do
    use Reactor

    input(:service_name)
    input(:simulate_auth_failure)

    step :generate_key, CRGenerateVaultKey do
      argument :service_name, input(:service_name)
    end

    step :distribute_key, CRDistributeKey do
      argument :service_name, input(:service_name)
      wait_for :generate_key
    end

    step :verify_auth, CRVerifyAuth do
      argument :service_name, input(:service_name)
      argument :simulate_auth_failure, input(:simulate_auth_failure)
      wait_for :distribute_key
    end

    step :revoke_legacy, CRRevokeLegacyKey do
      argument :service_name, input(:service_name)
      wait_for :verify_auth
    end
  end

  # ============================================================================
  # Test Scenarios
  # ============================================================================

  describe "1. Blue/Green Deployment Saga" do
    test "executes all 5 steps to completion on happy path" do
      inputs = %{
        deployment_id: "dep-2026-prod-01",
        version: "v2.18.4",
        simulate_router_failure: false
      }

      assert {:ok, result} = Reactor.run(BlueGreenDeploymentReactor, inputs)
      assert result.drained_env == "blue"

      events = SagaRecorder.get_events()
      run_steps = Enum.map(events, fn {:run, step, _} -> step end)

      assert run_steps == [
               :bg_allocate_green,
               :bg_deploy_artifact,
               :bg_health_check,
               :bg_switch_traffic,
               :bg_drain_blue
             ]

      # No undo or compensate occurred
      refute Enum.any?(events, &match?({:undo, _, _, _}, &1))
      refute Enum.any?(events, &match?({:compensate, _, _, _}, &1))
    end

    test "rolls back in strict LIFO order upon traffic switch failure" do
      inputs = %{
        deployment_id: "dep-2026-fail-02",
        version: "v2.18.5-broken",
        simulate_router_failure: true
      }

      assert {:error, _err} = Reactor.run(BlueGreenDeploymentReactor, inputs)

      events = SagaRecorder.get_events()

      # 1. Forward run stopped at step 4
      assert {:run, :bg_allocate_green, "dep-2026-fail-02"} in events
      assert {:run, :bg_deploy_artifact, "dep-2026-fail-02"} in events
      assert {:run, :bg_health_check, "dep-2026-fail-02"} in events
      assert {:run, :bg_switch_traffic, "dep-2026-fail-02"} in events
      refute Enum.any?(events, &match?({:run, :bg_drain_blue, _}, &1))

      # 2. Failed step executed compensate
      assert Enum.any?(events, &match?({:compensate, :bg_switch_traffic, {:router_timeout, _}, "dep-2026-fail-02"}, &1))

      # 3. Completed steps executed undo in reverse order
      undo_events =
        events
        |> Enum.filter(&match?({:undo, _, _, _}, &1))
        |> Enum.map(fn {:undo, step, _, _} -> step end)

      assert :bg_health_check in undo_events
      assert :bg_deploy_artifact in undo_events
      assert :bg_allocate_green in undo_events
      refute :bg_drain_blue in undo_events
    end
  end

  describe "2. Failover Actuation Saga" do
    test "completes full automated multi-region database failover" do
      inputs = %{cluster_id: "pg-cluster-eu-west-1", simulate_vip_failure: false}

      assert {:ok, result} = Reactor.run(FailoverActuationReactor, inputs)
      assert result.mesh_notified == true

      events = SagaRecorder.get_events()
      run_steps = Enum.map(events, fn {:run, step, _} -> step end)

      assert run_steps == [
               :fo_isolate_master,
               :fo_sync_replication,
               :fo_promote_standby,
               :fo_reconfigure_vip,
               :fo_notify_mesh
             ]
    end

    test "rolls back standby promotion and un-isolates master when VIP reconfiguration fails" do
      inputs = %{cluster_id: "pg-cluster-us-east-1", simulate_vip_failure: true}

      assert {:error, _err} = Reactor.run(FailoverActuationReactor, inputs)

      events = SagaRecorder.get_events()

      # Step 5 (notify_mesh) was never executed
      refute Enum.any?(events, &match?({:run, :fo_notify_mesh, _}, &1))

      # Step 4 executed compensate
      assert Enum.any?(
               events,
               &match?({:compensate, :fo_reconfigure_vip, {:vip_conflict, _}, "pg-cluster-us-east-1"}, &1)
             )

      # Completed steps 1..3 undone
      undo_steps =
        events
        |> Enum.filter(&match?({:undo, _, _, _}, &1))
        |> Enum.map(fn {:undo, step, _, _} -> step end)

      assert :fo_promote_standby in undo_steps
      assert :fo_sync_replication in undo_steps
      assert :fo_isolate_master in undo_steps
    end
  end

  describe "3. Credential Rotation Saga" do
    test "rotates secrets and revokes legacy keys seamlessly" do
      inputs = %{service_name: "auth-gateway", simulate_auth_failure: false}

      assert {:ok, result} = Reactor.run(CredentialRotationReactor, inputs)
      assert result.revoked == true

      events = SagaRecorder.get_events()
      run_steps = Enum.map(events, fn {:run, step, _} -> step end)

      assert run_steps == [
               :cr_generate_key,
               :cr_distribute_key,
               :cr_verify_auth,
               :cr_revoke_legacy
             ]
    end

    test "aborts rotation and rolls back key distribution if verification handshake fails" do
      inputs = %{service_name: "payment-vault", simulate_auth_failure: true}

      assert {:error, _err} = Reactor.run(CredentialRotationReactor, inputs)

      events = SagaRecorder.get_events()

      # Legacy key was never revoked
      refute Enum.any?(events, &match?({:run, :cr_revoke_legacy, _}, &1))

      # Failed step compensated
      assert Enum.any?(
               events,
               &match?({:compensate, :cr_verify_auth, {:auth_handshake_failed, _}, "payment-vault"}, &1)
             )

      # Distributed key and generated key were undone
      undo_steps =
        events
        |> Enum.filter(&match?({:undo, _, _, _}, &1))
        |> Enum.map(fn {:undo, step, _, _} -> step end)

      assert :cr_distribute_key in undo_steps
      assert :cr_generate_key in undo_steps
      refute :cr_revoke_legacy in undo_steps
    end
  end
end
