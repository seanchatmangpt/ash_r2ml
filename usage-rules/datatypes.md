# Datatypes

AshR2RML maps Ash values to RDF terms through an explicit datatype registry.

## Built-in scalar correspondence

Representative defaults:

| Ash type | RDF datatype |
|---|---|
| `:string` | `xsd:string` |
| `:integer` | `xsd:integer` |
| `:boolean` | `xsd:boolean` |
| `:decimal` | `xsd:decimal` |
| `:date` | `xsd:date` |
| UTC datetime | `xsd:dateTime` |
| `:uuid` | `xsd:string` unless explicitly mapped otherwise |
| `:duration` (`Ash.Type.Duration`, Ash >= 3.23) | `xsd:duration` |

The exact registry is executable code and tests, not this table alone.

## No lossy fallback

Never implement:

```text
unknown Ash type → xsd:string
```

If the library cannot prove a lawful lexical form and datatype IRI, compilation must return an unsupported/typed refusal.

## Custom types

Custom Ash types may register a mapping that defines:

- RDF datatype IRI;
- lexical serialization;
- optional lexical parsing for verification;
- term type constraints.

The mapping must be deterministic and must not depend on process-local inspection or presentation-only `inspect/1` output.

## Decimal and numeric precision

Preserve exact decimal semantics. Do not silently convert exact decimal values to binary floating point merely to simplify RDF serialization.

## Date/time values

Use canonical lexical forms and preserve timezone semantics. A value stored as UTC must not acquire a local timezone in RDF output.

## Enums and atoms

Application enums/atoms require an explicit semantic choice: literal lexical value, controlled-vocabulary IRI, or custom datatype. Do not infer one from the Elixir representation alone.

## Collections and embedded structures

Do not serialize lists/maps/embedded resources into opaque JSON literals by default and call the ontology preserved. They need an explicit mapping strategy: RDF collection, related resources, JSON datatype, or unsupported.

## Verification

Datatype tests must check both the declared datatype IRI and the lexical representation used by the OBDA/R2RML path.
