# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHook.Ash.ObservationReceipt do
  @moduledoc "Evidence-bounded observation of a native Ash primitive."

  @enforce_keys [:receipt_sha256, :source, :subject, :replay]
  defstruct [
    :receipt_sha256,
    :source,
    :subject,
    :replay,
    version: 1,
    observed?: true,
    status: :PARTIAL_ALIVE,
    standing: :observed_ash_primitive,
    authority: :UNAUTHORIZED,
    consequence: :none,
    executed: [],
    verified: [:observation_receipt_identity],
    blocked: [:actuation_authority]
  ]

  @type source :: :ash_notification | :ash_action
  @type t :: %__MODULE__{
          receipt_sha256: String.t(),
          source: source(),
          subject: map(),
          replay: map(),
          version: 1,
          observed?: true,
          status: :PARTIAL_ALIVE,
          standing: :observed_ash_primitive,
          authority: :UNAUTHORIZED,
          consequence: :none,
          executed: list(),
          verified: list(),
          blocked: list()
        }
end

defmodule AshR2RML.KnowledgeHook.Ash do
  @moduledoc """
  Pure adapter from native Ash evidence into knowledge-hook trigger receipts.

  The adapter observes already-produced Ash values. It never installs a notifier,
  callback, changeset hook, timer, telemetry handler, or action runner. A standalone
  `Ash.Changeset` is deliberately insufficient evidence because it represents
  candidate state, not an observed completed action.

  Two evidence rails are kept distinct:

    * `Ash.Notifier.Notification` is the state-change rail. The notification's
      changeset is projected into changed attributes, relationship changes, and
      explicit before/after deltas.
    * `Ash.Tracer.Simple.Span` is the action-observation rail. Action spans prove
      only that an Ash action span was observed; they do not prove a committed
      state change.

  Matching produces an explicit content-addressed trigger receipt which is then
  passed to `AshR2RML.KnowledgeHooks`. The resulting intents remain inert data with
  no DO authority.
  """

  alias AshR2RML.KnowledgeHook.{Definition, Plan, Predicate}
  alias AshR2RML.KnowledgeHook.Ash.ObservationReceipt
  alias AshR2RML.{Compiler, Refusal}

  @action_span_types [:action, :bulk_create, :bulk_update, :bulk_destroy, :bulk_batch]
  @notification_keys ~w(source resource action action_type changed changed_relationships transition)
  @action_keys ~w(source span_type name)

  @doc "Observe a native Ash primitive without registering any runtime callback."
  @spec observe(term()) :: {:ok, ObservationReceipt.t()} | {:error, Refusal.t()}
  def observe(%Ash.Notifier.Notification{} = notification), do: observe_notification(notification)

  def observe(%Ash.Tracer.Simple.Span{type: type} = span) when type in @action_span_types do
    subject = %{
      source: :ash_action,
      span_type: type,
      span_id: stable_scalar(span.id),
      parent_span_id: stable_scalar(span.parent_id),
      name: span.name,
      start: stable_scalar(span.start)
    }

    {:ok, build_receipt(:ash_action, subject)}
  end

  def observe(%Ash.Tracer.Simple.Span{} = span) do
    {:error,
     refusal(
       :ash_trace_span,
       "knowledge hooks admit action-level Ash spans only",
       %{span_type: span.type, supported: @action_span_types}
     )}
  end

  def observe(%Ash.Changeset{} = changeset) do
    {:error,
     refusal(
       changeset.resource || :ash_changeset,
       "standalone Ash changesets are candidate state, not observed completed state changes; require an Ash notification",
       %{action_type: changeset.action_type, phase: changeset.phase}
     )}
  end

  def observe(other) do
    {:error,
     refusal(
       :ash_observation,
       "unsupported or unobserved Ash trigger evidence",
       %{got: inspect_type(other), supported: ["Ash.Notifier.Notification", "Ash.Tracer.Simple.Span"]}
     )}
  end

  @doc "Observe one or more Ash primitives and evaluate the plan without actuation."
  @spec evaluate(Plan.t(), term() | [term()], keyword()) ::
          {:ok, %{observations: [ObservationReceipt.t()], evaluations: list()}}
          | {:error, Refusal.t()}
  def evaluate(%Plan{} = plan, evidence, opts \\ []) when is_list(opts) do
    with {:ok, observations} <- observe_many(List.wrap(evidence)),
         {:ok, ash_trigger_receipts} <- trigger_receipts(plan, observations) do
      existing = Keyword.get(opts, :trigger_receipts, %{})
      opts = Keyword.put(opts, :trigger_receipts, Map.merge(existing, ash_trigger_receipts))

      case AshR2RML.KnowledgeHooks.evaluate(plan, opts) do
        {:ok, evaluations} -> {:ok, %{observations: observations, evaluations: evaluations}}
        {:error, %Refusal{} = refusal} -> {:error, refusal}
      end
    end
  end

  @doc "Manufacture explicit Ash trigger receipts for the hooks supported by the observed evidence set."
  @spec trigger_receipts(Plan.t(), [ObservationReceipt.t()]) :: {:ok, map()} | {:error, Refusal.t()}
  def trigger_receipts(%Plan{} = plan, observations) when is_list(observations) do
    Enum.reduce_while(plan.hooks, {:ok, %{}}, fn hook, {:ok, acc} ->
      case ash_pattern(hook) do
        :not_ash ->
          {:cont, {:ok, acc}}

        {:error, %Refusal{} = refusal} ->
          {:halt, {:error, refusal}}

        {:ok, source, pattern} ->
          relevant = Enum.filter(observations, &(&1.source == source))

          if relevant == [] do
            # Do not manufacture evidence for an unobserved source. The core evaluator
            # will fail closed if no other explicit trigger receipt exists.
            {:cont, {:ok, acc}}
          else
            case match_receipts(relevant, pattern, hook.id) do
              {:ok, matched?} ->
                trigger = explicit_trigger_receipt(hook, pattern, relevant, matched?)
                {:cont, {:ok, Map.put(acc, hook.id, trigger)}}

              {:error, %Refusal{} = refusal} ->
                {:halt, {:error, refusal}}
            end
          end
      end
    end)
  end

  @doc "Deterministic inert projection of Ash-native matchers for ggen manufacture."
  @spec projection(Plan.t()) :: {:ok, map()} | {:error, Refusal.t()}
  def projection(%Plan{} = plan) do
    Enum.reduce_while(plan.hooks, {:ok, []}, fn hook, {:ok, acc} ->
      case ash_pattern(hook) do
        :not_ash ->
          {:cont, {:ok, acc}}

        {:error, %Refusal{} = refusal} ->
          {:halt, {:error, refusal}}

        {:ok, source, pattern} ->
          primitive =
            case source do
              :ash_notification -> "Ash.Notifier.Notification"
              :ash_action -> "Ash.Tracer.Simple.Span"
            end

          matcher = %{
            hook_id: hook.id,
            primitive: primitive,
            source: source,
            selector: canonical_pattern(pattern),
            observation_authority_ceiling: :OBSERVE,
            consequence_authority_ceiling: :CONSTRUCT,
            authority: :UNAUTHORIZED,
            callbacks: :REFUSED,
            timers: :REFUSED,
            actuation: :REFUSED
          }

          {:cont, {:ok, [matcher | acc]}}
      end
    end)
    |> case do
      {:ok, matchers} ->
        matchers = Enum.sort_by(matchers, & &1.hook_id)

        projection = %{
          version: 1,
          plan_sha256: plan.plan_sha256,
          standing: :construct_only,
          authority: :UNAUTHORIZED,
          authority_ceiling: :CONSTRUCT,
          observation_primitives: Enum.reverse(matchers),
          blocked: [:callbacks, :timers, :unobserved_external_triggers, :actuation_authority]
        }

        {:ok, Map.put(projection, :projection_sha256, Compiler.sha256(projection))}

      error ->
        error
    end
  end

  defp observe_many(evidence) do
    Enum.reduce_while(evidence, {:ok, []}, fn item, {:ok, acc} ->
      case observe(item) do
        {:ok, receipt} -> {:cont, {:ok, [receipt | acc]}}
        {:error, %Refusal{} = refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, receipts} -> {:ok, Enum.reverse(receipts)}
      error -> error
    end
  end

  defp observe_notification(%Ash.Notifier.Notification{resource: nil} = notification) do
    {:error,
     refusal(
       :ash_notification,
       "resource-less Ash notifications do not establish the resource transaction boundary required for state-change hooks",
       %{action: action_name(notification.action)}
     )}
  end

  defp observe_notification(%Ash.Notifier.Notification{changeset: %Ash.Changeset{} = changeset} = notification) do
    resource = notification.resource || changeset.resource
    action = notification.action || changeset.action
    action_type = action_type(action, changeset)
    changed_attributes = changed_attribute_names(changeset)
    changed_relationships = changed_relationship_names(changeset)

    with {:ok, delta} <- attribute_delta(changeset, notification.data, action_type, changed_attributes),
         {:ok, primary_key} <- primary_key(resource, notification.data) do
      subject = %{
        source: :ash_notification,
        resource: module_name(resource),
        domain: module_name(notification.domain || changeset.domain),
        action: action_name(action),
        action_type: action_type,
        primary_key: primary_key,
        changed_attributes: changed_attributes,
        changed_relationships: changed_relationships,
        attribute_delta: delta
      }

      {:ok, build_receipt(:ash_notification, subject)}
    end
  end

  defp observe_notification(%Ash.Notifier.Notification{} = notification) do
    {:error,
     refusal(
       notification.resource || :ash_notification,
       "Ash state-change observation requires the notification's native changeset",
       %{action: action_name(notification.action)}
     )}
  end

  defp ash_pattern(%Definition{predicate: %Predicate{type: :external_trigger}} = hook) do
    pattern = hook.trigger_pattern

    cond do
      hook.trigger_type == :interval and ash_source(pattern) != nil ->
        {:error,
         refusal(
           hook.id,
           "Ash knowledge-hook observations do not create or schedule timers",
           %{trigger_type: hook.trigger_type}
         )}

      source = ash_source(pattern) ->
        with :ok <- validate_pattern(hook.id, source, pattern) do
          {:ok, source, pattern}
        end

      true ->
        :not_ash
    end
  end

  defp ash_pattern(_hook), do: :not_ash

  defp ash_source(pattern) when is_map(pattern) do
    case get(pattern, :source) do
      value when value in [:ash_notification, "ash_notification"] -> :ash_notification
      value when value in [:ash_action, "ash_action"] -> :ash_action
      _ -> nil
    end
  end

  defp ash_source(_), do: nil

  defp validate_pattern(hook_id, source, pattern) do
    allowed = if source == :ash_notification, do: @notification_keys, else: @action_keys

    unsupported =
      pattern
      |> Map.keys()
      |> Enum.map(&key_string/1)
      |> Enum.reject(&(&1 in allowed))
      |> Enum.sort()

    if unsupported == [] do
      validate_transition(hook_id, source, get(pattern, :transition))
    else
      {:error,
       refusal(
         hook_id,
         "unsupported Ash knowledge-hook trigger predicate",
         %{source: source, unsupported: unsupported, supported: allowed}
       )}
    end
  end

  defp validate_transition(_hook_id, _source, nil), do: :ok

  defp validate_transition(hook_id, :ash_notification, transition) when is_map(transition) do
    unsupported =
      transition
      |> Map.keys()
      |> Enum.map(&key_string/1)
      |> Enum.reject(&(&1 in ~w(attribute from to)))
      |> Enum.sort()

    cond do
      unsupported != [] ->
        {:error,
         refusal(hook_id, "unsupported Ash state-transition predicate", %{
           unsupported: unsupported,
           supported: ~w(attribute from to)
         })}

      is_nil(get(transition, :attribute)) ->
        {:error, refusal(hook_id, "Ash state-transition predicate requires an explicit attribute")}

      true ->
        :ok
    end
  end

  defp validate_transition(hook_id, _source, transition) do
    {:error,
     refusal(hook_id, "Ash state-transition predicate must be a map", %{got: inspect_type(transition)})}
  end

  defp match_receipts(receipts, pattern, hook_id) do
    Enum.reduce_while(receipts, {:ok, false, nil}, fn receipt, {:ok, false, first_error} ->
      case matches?(receipt, pattern, hook_id) do
        {:ok, true} -> {:halt, {:ok, true}}
        {:ok, false} -> {:cont, {:ok, false, first_error}}
        {:error, %Refusal{} = refusal} -> {:cont, {:ok, false, first_error || refusal}}
      end
    end)
    |> case do
      {:ok, true} -> {:ok, true}
      {:ok, false, nil} -> {:ok, false}
      {:ok, false, %Refusal{} = refusal} -> {:error, refusal}
    end
  end

  defp matches?(%ObservationReceipt{source: :ash_notification, subject: subject}, pattern, hook_id) do
    with true <- field_match?(subject.resource, get(pattern, :resource), &normalize_resource/1),
         true <- field_match?(subject.action, get(pattern, :action), &normalize_name/1),
         true <- field_match?(subject.action_type, get(pattern, :action_type), &normalize_atomish/1),
         true <- subset_match?(subject.changed_attributes, get(pattern, :changed)),
         true <- subset_match?(subject.changed_relationships, get(pattern, :changed_relationships)),
         {:ok, transition?} <- transition_match(subject.attribute_delta, get(pattern, :transition), hook_id) do
      {:ok, transition?}
    else
      false -> {:ok, false}
      {:error, %Refusal{} = refusal} -> {:error, refusal}
    end
  end

  defp matches?(%ObservationReceipt{source: :ash_action, subject: subject}, pattern, _hook_id) do
    {:ok,
     field_match?(subject.span_type, get(pattern, :span_type), &normalize_atomish/1) and
       field_match?(subject.name, get(pattern, :name), &normalize_name/1)}
  end

  defp transition_match(_delta, nil, _hook_id), do: {:ok, true}

  defp transition_match(delta, transition, hook_id) do
    attribute = transition |> get(:attribute) |> normalize_name()

    case Map.fetch(delta, attribute) do
      :error ->
        {:ok, false}

      {:ok, %{from: from, to: to}} ->
        expected_from = get(transition, :from, :__any__)
        expected_to = get(transition, :to, :__any__)

        cond do
          (expected_from != :__any__ and from == :UNKNOWN) or
              (expected_to != :__any__ and to == :UNKNOWN) ->
            {:error,
             refusal(
               hook_id,
               "Ash transition cannot be evaluated because the required state value was not observed",
               %{attribute: attribute, delta: %{from: from, to: to}}
             )}

          expected_from != :__any__ and from != expected_from ->
            {:ok, false}

          expected_to != :__any__ and to != expected_to ->
            {:ok, false}

          true ->
            {:ok, true}
        end
    end
  end

  defp explicit_trigger_receipt(hook, pattern, observations, matched?) do
    observation_receipts = observations |> Enum.map(& &1.receipt_sha256) |> Enum.sort()

    core = %{
      version: 1,
      hook_id: hook.id,
      plan_trigger: canonical_pattern(pattern),
      observation_receipts: observation_receipts,
      matched?: matched?,
      authority: :UNAUTHORIZED,
      consequence: if(matched?, do: :intent_selection_eligible, else: :none)
    }

    %{
      observed?: true,
      matched?: matched?,
      receipt_sha256: Compiler.sha256(core),
      source: :ash_native_observation,
      observation_receipts: observation_receipts,
      standing: :observed_trigger_match_only,
      authority: :UNAUTHORIZED,
      consequence: core.consequence,
      blocked: [:actuation_authority]
    }
  end

  defp build_receipt(source, subject) do
    replay = %{
      adapter: __MODULE__,
      source: source,
      subject_sha256: Compiler.sha256(subject)
    }

    core = %{
      version: 1,
      source: source,
      subject: subject,
      replay: replay,
      observed?: true,
      authority: :UNAUTHORIZED,
      consequence: :none
    }

    %ObservationReceipt{
      receipt_sha256: Compiler.sha256(core),
      source: source,
      subject: subject,
      replay: replay,
      executed: [:native_ash_value_observation],
      verified: [:observation_receipt_identity]
    }
  end

  defp changed_attribute_names(changeset) do
    (Map.keys(changeset.attributes || %{}) ++
       Map.keys(changeset.attribute_changes || %{}) ++ atomic_keys(changeset.atomics))
    |> Enum.map(&normalize_name/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp changed_relationship_names(changeset) do
    changeset.relationships
    |> Kernel.||(%{})
    |> Map.keys()
    |> Enum.map(&normalize_name/1)
    |> Enum.sort()
  end

  defp atomic_keys(atomics) when is_list(atomics) do
    Enum.flat_map(atomics, fn
      {key, _value} -> [key]
      _ -> []
    end)
  end

  defp atomic_keys(atomics) when is_map(atomics), do: Map.keys(atomics)
  defp atomic_keys(_), do: []

  defp attribute_delta(changeset, after_record, action_type, attributes) do
    Enum.reduce_while(attributes, {:ok, %{}}, fn attribute, {:ok, acc} ->
      atom = existing_atom_key(changeset, attribute)

      from =
        case action_type do
          :create -> :ABSENT
          _ -> record_value(changeset.data, atom)
        end

      to =
        case action_type do
          :destroy -> :ABSENT
          _ -> record_value(after_record, atom)
        end

      with {:ok, from} <- stable_value(from),
           {:ok, to} <- stable_value(to) do
        {:cont, {:ok, Map.put(acc, attribute, %{from: from, to: to})}}
      else
        {:error, reason} ->
          {:halt,
           {:error,
            refusal(changeset.resource || :ash_notification, "Ash state delta contains a non-replayable value", %{
              attribute: attribute,
              reason: reason
            })}}
      end
    end)
  end

  defp existing_atom_key(changeset, string_key) do
    keys =
      Map.keys(changeset.attributes || %{}) ++
        Map.keys(changeset.attribute_changes || %{}) ++ atomic_keys(changeset.atomics)

    Enum.find(keys, string_key, &(normalize_name(&1) == string_key))
  end

  defp record_value(%Ash.Changeset.OriginalDataNotAvailable{}, _attribute), do: :UNKNOWN
  defp record_value(record, attribute) when is_map(record), do: Map.get(record, attribute, :UNKNOWN)
  defp record_value(_, _attribute), do: :UNKNOWN

  defp primary_key(nil, _data), do: {:ok, %{}}
  defp primary_key(_resource, data) when not is_map(data), do: {:ok, %{}}

  defp primary_key(resource, data) do
    keys =
      resource
      |> Ash.Resource.Info.primary_key()
      |> Enum.map(fn
        %{name: name} -> name
        name -> name
      end)

    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, acc} ->
      case stable_value(Map.get(data, key, :UNKNOWN)) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, normalize_name(key), value)}}
        {:error, reason} -> {:halt, {:error, refusal(resource, "Ash primary key is not replayable", %{key: key, reason: reason})}}
      end
    end)
  rescue
    _ -> {:ok, %{}}
  end

  defp action_type(action, changeset) do
    cond do
      is_map(action) and Map.get(action, :type) -> Map.get(action, :type)
      changeset.action_type -> changeset.action_type
      true -> :UNKNOWN
    end
  end

  defp action_name(nil), do: nil
  defp action_name(action) when is_map(action), do: Map.get(action, :name) |> normalize_name()
  defp action_name(action), do: normalize_name(action)

  defp module_name(nil), do: nil
  defp module_name(module) when is_atom(module), do: inspect(module)
  defp module_name(other), do: to_string(other)

  defp field_match?(_actual, nil, _normalizer), do: true
  defp field_match?(actual, expected, normalizer), do: normalizer.(actual) == normalizer.(expected)

  defp subset_match?(_actual, nil), do: true

  defp subset_match?(actual, expected) do
    expected
    |> List.wrap()
    |> Enum.map(&normalize_name/1)
    |> Enum.all?(&(&1 in actual))
  end

  defp normalize_resource(nil), do: nil
  defp normalize_resource(value) when is_atom(value), do: inspect(value)
  defp normalize_resource(value), do: to_string(value)

  defp normalize_name(nil), do: nil
  defp normalize_name(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_name(value) when is_binary(value), do: value
  defp normalize_name(value), do: to_string(value)

  defp normalize_atomish(nil), do: nil
  defp normalize_atomish(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_atomish(value) when is_binary(value), do: value
  defp normalize_atomish(value), do: to_string(value)

  defp stable_scalar(nil), do: nil
  defp stable_scalar(value) when is_binary(value) or is_number(value) or is_atom(value), do: value
  defp stable_scalar(value), do: inspect(value)

  defp stable_value(value) when is_function(value) or is_pid(value) or is_port(value) or is_reference(value),
    do: {:error, :ambient_runtime_value}

  defp stable_value(%DateTime{} = value), do: {:ok, DateTime.to_iso8601(value)}
  defp stable_value(%NaiveDateTime{} = value), do: {:ok, NaiveDateTime.to_iso8601(value)}
  defp stable_value(%Date{} = value), do: {:ok, Date.to_iso8601(value)}
  defp stable_value(%Time{} = value), do: {:ok, Time.to_iso8601(value)}

  defp stable_value(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> stable_value()
  end

  defp stable_value(map) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {:ok, key} <- stable_value(key),
           {:ok, value} <- stable_value(value) do
        {:cont, {:ok, Map.put(acc, key, value)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp stable_value(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case stable_value(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp stable_value(tuple) when is_tuple(tuple) do
    with {:ok, values} <- tuple |> Tuple.to_list() |> stable_value() do
      {:ok, {:tuple, values}}
    end
  end

  defp stable_value(value), do: {:ok, value}

  defp canonical_pattern(pattern) when is_map(pattern) do
    pattern
    |> Enum.map(fn {key, value} -> {key_string(key), canonical_pattern(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp canonical_pattern(list) when is_list(list), do: Enum.map(list, &canonical_pattern/1)

  defp canonical_pattern(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&canonical_pattern/1)

  defp canonical_pattern(value), do: value

  defp get(map, key, default \\ nil) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp key_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_string(key) when is_binary(key), do: key
  defp key_string(key), do: inspect(key)

  defp refusal(subject, detail, evidence \\ %{}) do
    Refusal.new(:REFUSED_UNPROVEN_EQUIVALENCE, subject, detail, evidence)
  end

  defp inspect_type(%{__struct__: module}), do: inspect(module)
  defp inspect_type(value), do: value |> :erlang.term_to_binary() |> byte_size() |> then(&"term/#{&1}b")
end
