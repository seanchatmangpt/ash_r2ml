# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Introspection.Manifest do
  @moduledoc """
  Thin, real wrapper around `Ash.Info.manifest/1` (Ash >= 3.25) for tooling
  and ggen-pack generation that needs a resource/field/relationship lookup
  keyed by module, rather than re-deriving that shape via ad hoc
  `Ash.Resource.Info.*` calls.

  `AshR2RML.Compiler`'s mapping-IR pipeline (`AshR2RML.Introspection`,
  `AshR2RML.Alignment`, etc.) is untouched by this module -- it keeps its
  existing direct `Ash.Resource.Info` introspection, which is per-resource
  and does not need a whole-application manifest. This module exists for
  the separate, additive use case of application-wide tooling (docs
  generation, ggen pack scaffolding, debugging) that wants a single
  resource-lookup map across every domain/resource reachable from an
  `:ash_domains` application config, or from an explicit action-entrypoint
  list when no `:ash_domains` config is present (e.g. a library's own test
  app, or a one-off script).

  Refuses with a typed `AshR2RML.Refusal` (`:REFUSED_MANIFEST_GENERATION`)
  rather than propagating `Ash.Info.Manifest.generate/1`'s raw `{:error,
  term()}` shape, consistent with the rest of AshR2RML's refusal vocabulary.
  """

  alias AshR2RML.Refusal

  @type resource_lookup :: Ash.Info.Manifest.resource_lookup()

  @doc """
  Generates a manifest for `otp_app` (or the given `:action_entrypoints`,
  which bypass the `:ash_domains` application-config lookup entirely) and
  returns it wrapped in `{:ok, %Ash.Info.Manifest{}}`.

  ## Options

    * `:otp_app` - required. The OTP app to scan for Ash domains/resources.
    * `:action_entrypoints` - optional `[{resource_module, action_name}]`
      list. When given, only those actions (and the resources/types they
      reach) are included, regardless of `:ash_domains` config.
  """
  @spec generate(keyword()) :: {:ok, Ash.Info.Manifest.t()} | {:error, Refusal.t()}
  def generate(opts) do
    case Keyword.fetch(opts, :otp_app) do
      :error ->
        {:error,
         Refusal.new(
           :REFUSED_MANIFEST_GENERATION,
           nil,
           "Ash.Info.manifest/1 requires an :otp_app option",
           %{opts: opts}
         )}

      {:ok, otp_app} ->
        case Ash.Info.manifest(opts) do
          {:ok, manifest} ->
            {:ok, manifest}

          {:error, reason} ->
            {:error,
             Refusal.new(
               :REFUSED_MANIFEST_GENERATION,
               otp_app,
               "Ash.Info.manifest/1 failed to generate a manifest",
               %{reason: reason, opts: opts}
             )}
        end
    end
  end

  @doc """
  Generates a manifest and returns its `resource_lookup/1` map directly
  (module => `%Ash.Info.Manifest.Resource{}`).
  """
  @spec resource_lookup(keyword()) :: {:ok, resource_lookup()} | {:error, Refusal.t()}
  def resource_lookup(opts) do
    with {:ok, manifest} <- generate(opts) do
      {:ok, Ash.Info.Manifest.resource_lookup(manifest)}
    end
  end

  @doc """
  Looks up a single resource's manifest entry by module, given an
  already-built `resource_lookup/0` map.

  Returns `nil` when the resource is not reachable from the manifest that
  produced `lookup` (e.g. it belongs to a different `:ash_domains` config,
  or was excluded by an `:action_entrypoints` filter).
  """
  @spec fetch_resource(resource_lookup(), module()) :: Ash.Info.Manifest.Resource.t() | nil
  def fetch_resource(lookup, resource_module) when is_map(lookup) do
    Ash.Info.Manifest.get_resource(lookup, resource_module)
  end
end
