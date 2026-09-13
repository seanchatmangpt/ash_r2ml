# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Federation.Environment do
  @moduledoc """
  An admitted, named compilation environment.

  This is NOT a deployment target, a network endpoint, or a tenant record in
  any running system. It is the minimal identity a determinism claim needs:
  a name, the compiler identity that will run the profile, and the ontology
  identity the profile is admitted against. Two environments are the "same"
  for federation purposes iff `compiler_version` and
  `admitted_ontology_sha256` are both equal.
  """

  @enforce_keys [:name, :compiler_version, :admitted_ontology_sha256]
  defstruct [:name, :compiler_version, :admitted_ontology_sha256]

  @type t :: %__MODULE__{
          name: String.t(),
          compiler_version: String.t(),
          admitted_ontology_sha256: String.t()
        }
end

defmodule AshR2RML.Federation.FederationReceipt do
  @moduledoc """
  Real, mechanically checkable record of whether the SAME semantic profile,
  compiled independently once per admitted environment, produced
  byte-identical generated artifacts.

  This receipt proves artifact-identity determinism across independently
  configured environments that share compiler+ontology identity. It proves
  nothing about network federation, multi-tenant deployment, or any live
  customer environment -- those are out of scope for this module. See
  `AshR2RML.Federation` moduledoc and the "Federation" section of
  `AGENTS.md`/`README.md` for the exact claim boundary.
  """

  @enforce_keys [:profile_hash, :environments, :artifact_sha256_by_environment, :all_identical?]
  defstruct [
    :profile_hash,
    :environments,
    :artifact_sha256_by_environment,
    :all_identical?,
    diverging_environments: [],
    refusals: []
  ]

  @type t :: %__MODULE__{
          profile_hash: String.t() | nil,
          environments: [String.t()],
          artifact_sha256_by_environment: %{optional(String.t()) => String.t()},
          all_identical?: boolean(),
          diverging_environments: [String.t()],
          refusals: [AshR2RML.Refusal.t()]
        }
end

defmodule AshR2RML.Federation do
  @moduledoc """
  Deterministic artifact identity and config admission across multiple named
  environments/tenants.

  ## What this proves

  `compile_for_environments/2` compiles the SAME admitted semantic profile
  independently, once per admitted `AshR2RML.Federation.Environment`, and
  hashes the resulting generated artifact set per environment. When all
  admitted environments share the same `compiler_version` and
  `admitted_ontology_sha256`, this module asserts and mechanically verifies
  that the generated artifact identity (a sha256 over the Ash source, Ecto
  migration, storage DDL, R2RML mapping, and SHACL shapes the compiler
  produced) is byte-identical across every one of them -- same input, same
  compiler identity, same artifact identity, checked by hash equality, not
  asserted by narrative.

  ## What this does NOT prove

  This module never opens a network connection, never deploys anything, and
  never talks to a real customer environment. There is no multi-tenant
  runtime here, no federation protocol, no cross-cluster consensus, and no
  Fortune 500 infrastructure of any kind. "Environment" here means exactly
  one thing: a named identity tuple (`name`, `compiler_version`,
  `admitted_ontology_sha256`) that `compile_for_environments/2` compiles the
  profile against, in-process, sequentially, in this BEAM node. It is the
  determinism substrate a federation claim would need, not the claim itself.
  """

  alias AshR2RML.{Compiler, Federation.Environment, Federation.FederationReceipt, Refusal}

  @doc """
  Admit a config map into a typed `Environment`, or refuse it.

  Required identity fields: `name` (non-empty string), `compiler_version`
  (non-empty string), `admitted_ontology_sha256` (non-empty string, expected
  to be a hex sha256 digest but not format-checked beyond non-emptiness --
  callers own their own hashing).
  """
  @spec admit_environment(map()) :: {:ok, Environment.t()} | {:error, Refusal.t()}
  def admit_environment(%{} = config) do
    name = fetch(config, :name)
    compiler_version = fetch(config, :compiler_version)
    ontology_sha256 = fetch(config, :admitted_ontology_sha256)

    cond do
      not is_binary(name) or name == "" ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
           config,
           "federation environment requires a non-empty :name",
           %{config: config}
         )}

      not is_binary(compiler_version) or compiler_version == "" ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
           config,
           "federation environment requires a non-empty :compiler_version",
           %{config: config}
         )}

      not is_binary(ontology_sha256) or ontology_sha256 == "" ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
           config,
           "federation environment requires a non-empty :admitted_ontology_sha256",
           %{config: config}
         )}

      true ->
        {:ok,
         %Environment{
           name: name,
           compiler_version: compiler_version,
           admitted_ontology_sha256: ontology_sha256
         }}
    end
  end

  def admit_environment(config) do
    {:error,
     Refusal.new(
       :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
       config,
       "federation environment config must be a map",
       %{config: config}
     )}
  end

  @doc """
  Compile the SAME semantic profile independently for each admitted
  environment and return a `FederationReceipt` proving (or disproving)
  artifact-identity determinism across them.

  Compilation happens once per environment, sequentially, in this process --
  there is no shared cache between environments, so identical output is
  evidence of real determinism in the compiler, not evidence of memoization.

  Environments whose `admitted_ontology_sha256` differs from the first
  environment's are still compiled (so real divergence is observed and
  named), but are expected, and reported, to diverge in `all_identical?` and
  `diverging_environments` -- this module does not silently exclude them.
  """
  @spec compile_for_environments(map(), [Environment.t()], keyword()) :: FederationReceipt.t()
  def compile_for_environments(profile, environments, opts \\ [])

  def compile_for_environments(_profile, [], _opts) do
    %FederationReceipt{
      profile_hash: nil,
      environments: [],
      artifact_sha256_by_environment: %{},
      all_identical?: false,
      diverging_environments: [],
      refusals: [
        Refusal.new(
          :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
          :environments,
          "compile_for_environments/2 requires at least one admitted environment",
          %{}
        )
      ]
    }
  end

  def compile_for_environments(profile, environments, opts) when is_list(environments) do
    profile_hash = Map.get(profile, :profile_hash, Map.get(profile, "profile_hash"))
    profile_ontology_hash = Map.get(profile, :ontology_hash, Map.get(profile, "ontology_hash"))

    {artifact_by_name, refusals} =
      Enum.reduce(environments, {%{}, []}, fn %Environment{} = env, {acc, refusals} ->
        cond do
          is_binary(profile_ontology_hash) and env.admitted_ontology_sha256 != profile_ontology_hash ->
            {acc,
             refusals ++
               [
                 Refusal.new(
                   :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
                   env.name,
                   "environment #{env.name} admitted ontology #{inspect(env.admitted_ontology_sha256)} " <>
                     "does not match profile ontology #{inspect(profile_ontology_hash)}",
                   %{environment: env, profile_ontology_hash: profile_ontology_hash}
                 )
               ]}

          true ->
            case Compiler.compile(profile, opts) do
              {:ok, %AshR2RML.Compilation{receipt: receipt}} ->
                {Map.put(acc, env.name, artifact_identity(receipt)), refusals}

              {:error, %AshR2RML.Compilation{refusals: env_refusals}} ->
                {acc,
                 refusals ++
                   [
                     Refusal.new(
                       :REFUSED_INVALID_FEDERATION_ENVIRONMENT,
                       env.name,
                       "compilation refused for environment #{env.name}",
                       %{environment: env, refusals: env_refusals}
                     )
                   ]}
            end
        end
      end)

    distinct_shas = artifact_by_name |> Map.values() |> Enum.uniq()

    all_identical? =
      refusals == [] and length(distinct_shas) == 1 and map_size(artifact_by_name) == length(environments)

    refused_names =
      Enum.map(refusals, fn %Refusal{subject: subject} -> subject end)
      |> Enum.filter(&is_binary/1)

    diverging_by_hash =
      case distinct_shas do
        [_single] ->
          []

        [] ->
          []

        _multiple ->
          majority_sha =
            artifact_by_name
            |> Map.values()
            |> Enum.frequencies()
            |> Enum.max_by(fn {_sha, count} -> count end)
            |> elem(0)

          artifact_by_name
          |> Enum.filter(fn {_name, sha} -> sha != majority_sha end)
          |> Enum.map(&elem(&1, 0))
      end

    diverging = Enum.uniq(refused_names ++ diverging_by_hash)

    %FederationReceipt{
      profile_hash: profile_hash,
      environments: Enum.map(environments, & &1.name),
      artifact_sha256_by_environment: artifact_by_name,
      all_identical?: all_identical?,
      diverging_environments: diverging,
      refusals: refusals
    }
  end

  defp artifact_identity(%AshR2RML.CompilationReceipt{} = receipt) do
    Compiler.sha256({
      receipt.ir_sha256,
      receipt.mapping_sha256,
      receipt.ash_sha256,
      receipt.ecto_sha256,
      receipt.postgres_sha256,
      receipt.r2rml_sha256,
      receipt.shacl_sha256
    })
  end

  defp fetch(map, key) when is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
