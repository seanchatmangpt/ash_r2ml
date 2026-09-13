# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Adversarial.ReactorSagaTest do
  @moduledoc """
  Hostile Adversarial Reactor Saga Execution & Rollback Test Suite.

  Exercises:
  1. Multi-step Reactor Sagas with native `undo/3` and `compensate/4` hooks.
  2. Failure injection on intermediate steps (e.g., Step 3 in a 4-step pipeline).
  3. Reactor saga execution & rollback mechanics:
     - Completed steps trigger their `undo/3` callbacks upon saga failure.
     - Failed step triggers its `compensate/4` callback.
     - Unreached subsequent steps (Step 4) are never executed or undone.
  4. Branch selection and guard condition short-circuiting:
     - Guard false skips branch steps entirely and excludes them from rollback.
     - Guard true executes branch and includes it in saga rollback upon failure.
  5. Ash Action and Transaction boundaries: validation failures and changeset rollbacks.
  """
  use ExUnit.Case, async: false

  # --- Agent for Recording Execution Sequence ---
  defmodule SequenceRecorder do
    use Agent

    # `Agent.start_link/2` links the agent to whichever ExUnit test process
    # happens to create it first -- that process exits when its test finishes,
    # killing the linked agent and leaving a stale name registration a moment
    # before the EXIT propagates. A later test's `reset/0` can then race
    # `Agent.update/2` against that dying process. `Agent.start/2` (unlinked)
    # decouples the recorder's lifetime from any one test process; `reset/0`
    # additionally catches the exit from a stale pid and retries instead of
    # trusting `already_started`/`whereis` as atomic with the following call.
    # (Real, reproduced flake -- see test/fortune5/operations_and_sagas_test.exs's
    # identical fix for the same root cause.)
    def start_link(_opts \\ []) do
      Agent.start(fn -> [] end, name: __MODULE__)
    end

    def stop do
      if Process.whereis(__MODULE__), do: Agent.stop(__MODULE__)
    end

    def reset do
      case Agent.start(fn -> [] end, name: __MODULE__) do
        {:ok, _pid} ->
          :ok

        {:error, {:already_started, _pid}} ->
          try do
            Agent.update(__MODULE__, fn _ -> [] end)
          catch
            :exit, _ -> reset()
          end
      end
    end

    def record(event) do
      Agent.update(__MODULE__, fn events -> events ++ [event] end)
    end

    def get_events do
      Agent.get(__MODULE__, & &1)
    end
  end

  # --- Step Modules with Ordered Saga Compensation Hooks ---

  defmodule StepAlpha do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SequenceRecorder.record({:run, :step_alpha, arguments[:value]})
      {:ok, %{step: :step_alpha, val: arguments[:value], status: :done}}
    end

    def undo(result, arguments, _context, _options) do
      SequenceRecorder.record({:undo, :step_alpha, result.val, arguments[:value]})
      :ok
    end
  end

  defmodule StepBeta do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SequenceRecorder.record({:run, :step_beta, arguments[:value]})
      {:ok, %{step: :step_beta, val: arguments[:value], status: :done}}
    end

    def undo(result, arguments, _context, _options) do
      SequenceRecorder.record({:undo, :step_beta, result.val, arguments[:value]})
      :ok
    end
  end

  defmodule StepGammaFailing do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SequenceRecorder.record({:run, :step_gamma_failing, arguments[:value]})
      {:error, {:injected_failure, "Gamma step intentional abort", arguments[:value]}}
    end

    def compensate(reason, arguments, _context, _options) do
      SequenceRecorder.record({:compensate, :step_gamma_failing, reason, arguments[:value]})
      :ok
    end
  end

  defmodule StepDelta do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SequenceRecorder.record({:run, :step_delta, arguments[:value]})
      {:ok, %{step: :step_delta, val: arguments[:value], status: :done}}
    end

    def undo(_result, _arguments, _context, _options), do: :ok
  end

  defmodule StepBranch do
    use Reactor.Step

    def run(arguments, _context, _options) do
      SequenceRecorder.record({:run, :step_branch, arguments[:value]})
      {:ok, %{step: :step_branch, val: arguments[:value]}}
    end

    def undo(result, arguments, _context, _options) do
      SequenceRecorder.record({:undo, :step_branch, result.val, arguments[:value]})
      :ok
    end
  end

  # --- Reactor Definitions ---

  defmodule FourStepFailureSagaReactor do
    use Reactor

    input(:order_id)

    step :alpha, StepAlpha do
      argument :value, input(:order_id)
    end

    step :beta, StepBeta do
      argument :value, input(:order_id)
      wait_for :alpha
    end

    step :gamma, StepGammaFailing do
      argument :value, input(:order_id)
      wait_for :beta
    end

    step :delta, StepDelta do
      argument :value, input(:order_id)
      wait_for :gamma
    end
  end

  defmodule ConditionalBranchSagaReactor do
    use Reactor

    input(:order_id)
    input(:enable_branch)

    step :alpha, StepAlpha do
      argument :value, input(:order_id)
    end

    step :branch_step, StepBranch do
      argument :value, input(:order_id)
      argument :enable_branch, input(:enable_branch)

      guard fn args, _context ->
        if args[:enable_branch] == true do
          :cont
        else
          {:halt, {:ok, :branch_skipped}}
        end
      end

      wait_for :alpha
    end

    step :beta, StepBeta do
      argument :value, input(:order_id)
      wait_for :alpha
    end

    step :gamma, StepGammaFailing do
      argument :value, input(:order_id)
      wait_for :beta
      wait_for :branch_step
    end
  end

  # --- Ash Resource for Action & Transaction Boundary Semantics ---

  defmodule TransactionalAccount do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key :id
      attribute :balance, :decimal, allow_nil?: false, public?: true
      attribute :status, :atom, constraints: [one_of: [:active, :frozen]], default: :active, public?: true
    end

    actions do
      defaults [:read, :destroy]

      create :create do
        primary? true
        accept [:balance, :status]

        validate fn changeset, _context ->
          balance = Ash.Changeset.get_attribute(changeset, :balance)

          if balance && Decimal.negative?(balance) do
            {:error, "Account balance cannot be negative"}
          else
            :ok
          end
        end
      end

      update :withdraw do
        require_atomic? false
        accept [:balance]

        validate fn changeset, _context ->
          new_balance = Ash.Changeset.get_attribute(changeset, :balance)

          if new_balance && Decimal.negative?(new_balance) do
            {:error, "Overdraft is forbidden"}
          else
            :ok
          end
        end
      end
    end
  end

  defmodule AccountDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Adversarial.ReactorSagaTest.TransactionalAccount
    end
  end

  setup do
    SequenceRecorder.reset()

    # Clear ETS data store between tests
    try do
      :ets.delete_all_objects(TransactionalAccount)
    rescue
      _ -> :ok
    end

    :ok
  end

  describe "1. Reactor Saga Rollback and Hook Execution" do
    test "proves failure triggers compensate on failing step and undo on all completed steps" do
      inputs = %{order_id: "ORD_7890"}

      assert {:error, _error} = Reactor.run(FourStepFailureSagaReactor, inputs)

      events = SequenceRecorder.get_events()

      # 1. Verify forward execution reached step_gamma_failing and halted
      assert {:run, :step_alpha, "ORD_7890"} in events
      assert {:run, :step_beta, "ORD_7890"} in events
      assert {:run, :step_gamma_failing, "ORD_7890"} in events

      # 2. Verify StepDelta was NEVER run
      refute Enum.any?(events, fn
               {:run, :step_delta, _} -> true
               _ -> false
             end)

      # 3. Failing step executed compensate
      assert Enum.any?(events, &match?({:compensate, :step_gamma_failing, _, "ORD_7890"}, &1))

      # 4. Completed preceding steps executed undo
      assert Enum.any?(events, &match?({:undo, :step_beta, "ORD_7890", "ORD_7890"}, &1))
      assert Enum.any?(events, &match?({:undo, :step_alpha, "ORD_7890", "ORD_7890"}, &1))

      # 5. Subsequent step (Delta) was never undone
      refute Enum.any?(events, fn
               {:undo, :step_delta, _, _} -> true
               _ -> false
             end)
    end

    test "compensate receives the exact failure reason and arguments" do
      inputs = %{order_id: "ORD_COMP_1"}

      assert {:error, _error} = Reactor.run(FourStepFailureSagaReactor, inputs)

      events = SequenceRecorder.get_events()

      # Verify compensate was dispatched with exact failure reason
      compensate_gamma =
        Enum.find(events, fn
          {:compensate, :step_gamma_failing, {:injected_failure, msg, "ORD_COMP_1"}, "ORD_COMP_1"} ->
            msg == "Gamma step intentional abort"

          _ ->
            false
        end)

      assert compensate_gamma != nil
    end
  end

  describe "2. Guard Short-Circuiting and Conditional Branch Rollback" do
    test "when guard is false, branch step is skipped and not included in rollback" do
      inputs = %{order_id: "ORD_NO_BRANCH", enable_branch: false}

      assert {:error, _error} = Reactor.run(ConditionalBranchSagaReactor, inputs)

      events = SequenceRecorder.get_events()

      # Branch step was never run
      refute Enum.any?(events, &match?({:run, :step_branch, _}, &1))
      # Branch step was never undone
      refute Enum.any?(events, &match?({:undo, :step_branch, _, _}, &1))

      # Alpha and Beta were executed and undone
      assert {:run, :step_alpha, "ORD_NO_BRANCH"} in events
      assert {:run, :step_beta, "ORD_NO_BRANCH"} in events
      assert Enum.any?(events, &match?({:undo, :step_alpha, _, _}, &1))
      assert Enum.any?(events, &match?({:undo, :step_beta, _, _}, &1))
    end

    test "when guard is true, branch step is executed and undone upon failure" do
      inputs = %{order_id: "ORD_WITH_BRANCH", enable_branch: true}

      assert {:error, _error} = Reactor.run(ConditionalBranchSagaReactor, inputs)

      events = SequenceRecorder.get_events()

      assert {:run, :step_alpha, "ORD_WITH_BRANCH"} in events
      assert {:run, :step_branch, "ORD_WITH_BRANCH"} in events
      assert {:run, :step_beta, "ORD_WITH_BRANCH"} in events

      undo_steps =
        events
        |> Enum.filter(&match?({:undo, _, _, _}, &1))
        |> Enum.map(fn {:undo, step, _, _} -> step end)

      assert :step_alpha in undo_steps
      assert :step_beta in undo_steps
      assert :step_branch in undo_steps
    end
  end

  describe "3. Ash Action & Transaction Rollback Boundaries" do
    test "action validation failure aborts changeset and leaves store untouched" do
      invalid_changeset =
        TransactionalAccount
        |> Ash.Changeset.for_create(:create, %{balance: Decimal.new("-50.00"), status: :active}, domain: AccountDomain)

      assert {:error, %Ash.Error.Invalid{} = error} = Ash.create(invalid_changeset)
      assert Exception.message(error) =~ "Account balance cannot be negative"

      # Verify no record was created in the ETS data layer
      assert {:ok, accounts} = Ash.read(TransactionalAccount, domain: AccountDomain)
      assert accounts == []
    end

    test "update action validation prevents overdraft and preserves original state" do
      {:ok, account} =
        TransactionalAccount
        |> Ash.Changeset.for_create(:create, %{balance: Decimal.new("100.00"), status: :active}, domain: AccountDomain)
        |> Ash.create()

      update_changeset =
        account
        |> Ash.Changeset.for_update(:withdraw, %{balance: Decimal.new("-20.00")}, domain: AccountDomain)

      assert {:error, %Ash.Error.Invalid{} = error} = Ash.update(update_changeset)
      assert Exception.message(error) =~ "Overdraft is forbidden"

      # Verify original record balance is preserved
      {:ok, reloaded} = Ash.get(TransactionalAccount, account.id, domain: AccountDomain)
      assert Decimal.equal?(reloaded.balance, Decimal.new("100.00"))
    end
  end
end
