# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Introspection.ManifestTest do
  @moduledoc """
  Chicago-style: exercises the real `Ash.Info.manifest/1` (Ash >= 3.25) against
  the real `AshR2RML.GrandExample` test-support resources/domain -- no mocked
  Ash collaborator. Sets/restores the real `:ash_domains` application env
  around each test since `Ash.Info.manifest/1` reads it directly.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.GrandExample.{Domain, Organization}
  alias AshR2RML.Introspection.Manifest

  setup do
    previous = Application.get_env(:ash_r2rml, :ash_domains)
    Application.put_env(:ash_r2rml, :ash_domains, [Domain])

    on_exit(fn ->
      if previous do
        Application.put_env(:ash_r2rml, :ash_domains, previous)
      else
        Application.delete_env(:ash_r2rml, :ash_domains)
      end
    end)

    :ok
  end

  test "generate/1 returns a real manifest reachable from the GrandExample domain" do
    assert {:ok, manifest} = Manifest.generate(otp_app: :ash_r2rml)
    assert %Ash.Info.Manifest{} = manifest
    assert Enum.any?(manifest.resources, &(&1.module == Organization))
  end

  test "resource_lookup/1 keys real resource entries by module" do
    assert {:ok, lookup} = Manifest.resource_lookup(otp_app: :ash_r2rml)
    assert %Ash.Info.Manifest.Resource{module: Organization} = Manifest.fetch_resource(lookup, Organization)
  end

  test "fetch_resource/2 returns nil for a module not reachable from the manifest" do
    assert {:ok, lookup} = Manifest.resource_lookup(otp_app: :ash_r2rml)
    assert Manifest.fetch_resource(lookup, NotAResource) == nil
  end

  test "generate/1 refuses with a typed Refusal when :otp_app is missing" do
    assert {:error, %AshR2RML.Refusal{code: :REFUSED_MANIFEST_GENERATION}} = Manifest.generate([])
  end
end
