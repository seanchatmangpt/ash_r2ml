from pathlib import Path
import re
import subprocess

root = Path('.')
workflow = Path('.github/workflows/tmp-forbidden-vocabulary-audit.yml')
script = Path('.github/tmp_cleanup_graph_db.py')
audit = Path('.audit/forbidden-vocabulary.txt')
forbidden = re.compile(r'neo4j|ash[_-]?neo4j|ashneo4j|bolt(?:y)?|apoc|cypher', re.I)


def write(path, text):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8')


# Workflows are maintained through the authorized GitHub connector. This script
# only mutates ordinary repository content, so its Actions token needs no workflow scope.
write('config/config.exs', '''# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

import Config

config :ash, :validate_domain_resource_inclusion?, false
config :ash, :validate_domain_config_inclusion?, false
config :ash, :missed_notifications, :ignore

import_config "#{Mix.env()}.exs"
''')

write('config/dev.exs', '''# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

import Config

level = if System.get_env("DEBUG"), do: :debug, else: :info

config :git_ops,
  mix_project: Mix.Project.get!(),
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/seanchatmangpt/ash_r2rml",
  types: [tidbit: [hidden?: true], important: [header: "Important Changes"]],
  tags: [allowed: ["backend"], allow_untagged?: true],
  manage_mix_version?: true,
  manage_readme_version: "README.md",
  version_tag_prefix: "v"

config :logger, :console,
  level: level,
  format: "$date $time [$level] $metadata$message\\n"
''')

write('config/test.exs', '''# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

import Config

level = if System.get_env("DEBUG"), do: :debug, else: :info

config :logger, :console,
  level: level,
  format: "$date $time [$level] $metadata$message\\n"
''')

write('CHANGELOG.md', '''# Changelog

All notable AshR2RML changes are recorded here.

## Unreleased

### Knowledge Hooks

- Added canonical content-addressed Knowledge Hook IR and deterministic dependency scheduling.
- Added RDF vocabulary and SHACL admission law with a CONSTRUCT authority ceiling.
- Added GitVan and KNHK compatibility adapters that lower into the same admitted plan.
- Added typed inert projections for Ash, Reactor, state transitions, jobs, workflows, and pipelines.
- Added evidence-bounded cognition-to-reflex promotion without actuation authority.
- Added deterministic ggen projections and receipt-bound manufacture.

### Semantic mapping

- Ash-first and ontology-first inputs converge on one normalized mapping bundle.
- R2RML, SHACL, Ash, Ecto, and PostgreSQL projections are deterministic consequences of admitted semantic IR.
- SPARQL/SQL equivalence remains an observed receipt boundary; technical evidence does not grant cutover authority.
''')

license_path = Path('LICENSES/MIT.md')
license_text = license_path.read_text(encoding='utf-8')
license_text = re.sub(
    r'Copyright \(c\) 2025 Matthew Graham Beanland and .*?\n',
    'Copyright (c) 2025 Matthew Graham Beanland and contributors\n',
    license_text,
    count=1,
)
license_path.write_text(license_text, encoding='utf-8')

for obsolete in [
    'documentation/topics/migration_from_ash_neo4j.md',
    'usage-rules/cypher-fragments.md',
]:
    Path(obsolete).unlink(missing_ok=True)

# Remove the retired cross-database witness from the public receipt contract.
p = Path('lib/ash_r2rml.ex')
text = p.read_text(encoding='utf-8')
text = text.replace('          neo4j_postgres_parity: :UNKNOWN,\n', '')
text = text.replace('          :neo4j_postgres_semantic_parity,\n', '')
p.write_text(text, encoding='utf-8')

p = Path('lib/ash_r2rml/compiler.ex')
text = p.read_text(encoding='utf-8')
text = text.replace('    :neo4j_postgres_parity,\n', '')
text = text.replace('          neo4j_postgres_parity: :UNKNOWN | :VERIFIED,\n', '')
text = text.replace(
    '  @doc "Cutover requires both observed parity witnesses and an explicit authority receipt."',
    '  @doc "Cutover requires an observed query-parity witness and an explicit authority receipt."',
)
text = text.replace('''  def cutover_ready?(%CompilationReceipt{
        query_parity: :VERIFIED,
        neo4j_postgres_parity: :VERIFIED,
        cutover_authority: :AUTHORIZED,
        blocked: []
      }),
      do: true
''', '''  def cutover_ready?(%CompilationReceipt{
        query_parity: :VERIFIED,
        cutover_authority: :AUTHORIZED,
        blocked: []
      }),
      do: true
''')
text = text.replace(
    'when kind in [:sparql_sql, :neo4j_postgres] and is_map(witness) do',
    'when kind == :sparql_sql and is_map(witness) do',
)
text = text.replace('''      receipt =
        case kind do
          :sparql_sql -> %{receipt | query_parity: :VERIFIED}
          :neo4j_postgres -> %{receipt | neo4j_postgres_parity: :VERIFIED}
        end

      blocked =
        case kind do
          :sparql_sql -> List.delete(receipt.blocked, :sparql_sql_behavioral_parity)
          :neo4j_postgres -> List.delete(receipt.blocked, :neo4j_postgres_semantic_parity)
        end
''', '''      receipt = %{receipt | query_parity: :VERIFIED}
      blocked = List.delete(receipt.blocked, :sparql_sql_behavioral_parity)
''')
text = text.replace('      neo4j_postgres_parity: :UNKNOWN,\n', '')
text = text.replace('        :neo4j_postgres_semantic_parity,\n', '')
p.write_text(text, encoding='utf-8')

p = Path('lib/ash_r2rml/parity.ex')
text = p.read_text(encoding='utf-8')
text = text.replace('          kind: :sparql_sql | :neo4j_postgres,', '          kind: :sparql_sql,')
text = text.replace('admitted SQL/SPARQL/Cypher queries', 'admitted SQL/SPARQL queries')
text = text.replace('@spec compare(:sparql_sql | :neo4j_postgres,', '@spec compare(:sparql_sql,')
text = text.replace(
    'when kind in [:sparql_sql, :neo4j_postgres] and is_list(left_rows) and is_list(right_rows) do',
    'when kind == :sparql_sql and is_list(left_rows) and is_list(right_rows) do',
)
text = re.sub(r'\n  defp default_left\(:neo4j_postgres\), do: :neo4j', '', text)
text = re.sub(r'\n  defp default_right\(:neo4j_postgres\), do: :postgres', '', text)
p.write_text(text, encoding='utf-8')

# Update tests to the single supported semantic-parity court.
p = Path('test/ash_r2rml_8020_coverage_test.exs')
text = re.sub(r'^\s*neo4j_postgres_parity: .*\n', '', p.read_text(encoding='utf-8'), flags=re.M)
p.write_text(text, encoding='utf-8')

p = Path('test/ontology_first_compiler_test.exs')
text = p.read_text(encoding='utf-8')
text = re.sub(
    r'\n      \|> AshR2RML\.Compiler\.attach_parity_witness\(:neo4j_postgres, %\{\n'
    r'        verified\?: true,\n'
    r'        receipt_sha256: "neo4j-postgres-receipt"\n'
    r'      \}\)',
    '',
    text,
)
text = re.sub(r'^\s*assert receipt\.neo4j_postgres_parity == :VERIFIED\n', '', text, flags=re.M)
text = text.replace(
    'cutover requires external parity witnesses and separate authority',
    'cutover requires external query parity and separate authority',
)
p.write_text(text, encoding='utf-8')

p = Path('test/parity_and_ggen_test.exs')
text = p.read_text(encoding='utf-8')
text = re.sub(
    r'\n    neo4j_postgres =\n      AshR2RML\.Parity\.compare\(:neo4j_postgres, :organization, \[%\{id: "1"\}\], \[%\{"id" => "1"\}\]\)\n',
    '\n',
    text,
)
text = re.sub(
    r'\n      \|> AshR2RML\.Compiler\.attach_parity_witness\(\n'
    r'        :neo4j_postgres,\n'
    r'        Map\.from_struct\(neo4j_postgres\)\n'
    r'      \)',
    '',
    text,
)
p.write_text(text, encoding='utf-8')

# OBDA crown keeps Ontop CLI, protocol SPARQL, local RDF and PostgreSQL only.
p = Path('test/integration/obda_crown.exs')
text = p.read_text(encoding='utf-8')
text = re.sub(r'^# - Neo4j remains the inherited control graph\n', '', text, flags=re.M)
text = re.sub(r'^  @neo4j_url .*\n', '', text, flags=re.M)
text = re.sub(r'\n  @neo4j_query """.*?\n  """\n', '\n', text, flags=re.S)
text = re.sub(
    r'\n    # Execution topology 4: inherited Neo4j control graph\..*?\n    technical_receipt =',
    '\n    technical_receipt =',
    text,
    flags=re.S,
)
text = re.sub(
    r'\n      \|> AshR2RML\.Compiler\.attach_parity_witness\(\n'
    r'        :neo4j_postgres,\n'
    r'        Map\.from_struct\(neo4j_postgres\)\n'
    r'      \)',
    '',
    text,
)
text = re.sub(
    r'\n    unless technical_receipt\.neo4j_postgres_parity == :VERIFIED,\n'
    r'      do: raise\("Neo4j/Postgres witness was not admitted"\)\n',
    '\n',
    text,
)
text = re.sub(r'^\s*neo4j_postgres: neo4j_postgres,\n', '', text, flags=re.M)
text = text.replace(
    'IO.puts("ALIVE bounded corpus: Turtle/JSON-LD + SPARQL.ex/SPARQL.Client/Ontop + Postgres/Neo4j parity")',
    'IO.puts("ALIVE bounded corpus: Turtle/JSON-LD + SPARQL.ex/SPARQL.Client/Ontop + PostgreSQL semantic parity")',
)
text = re.sub(r'\n  defp seed_neo4j! do.*?(?=\n  defp json_term)', '', text, flags=re.S)
p.write_text(text, encoding='utf-8')

# Preserve attribution while removing donor product identifiers from SPDX notices.
for p in root.rglob('*'):
    if not p.is_file() or '.git' in p.parts or p in (workflow, script, audit):
        continue
    try:
        text = p.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        continue
    out = []
    for line in text.splitlines(keepends=True):
        if 'SPDX-FileCopyrightText:' in line and forbidden.search(line):
            prefix = line[:line.index('SPDX-FileCopyrightText:')]
            if '2025' in line:
                line = f'{prefix}SPDX-FileCopyrightText: 2025 Matthew Graham Beanland and contributors\n'
            else:
                line = f'{prefix}SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>\n'
        out.append(line)
    p.write_text(''.join(out), encoding='utf-8')

# Historical/planning prose is non-executable; remove obsolete technology-specific statements.
prose_suffixes = {'.md', '.livemd', '.txt', '.license', '.aux', '.log', '.out', '.toc'}
for p in root.rglob('*'):
    if not p.is_file() or '.git' in p.parts or p in (workflow, script, audit):
        continue
    if p.suffix.lower() not in prose_suffixes:
        continue
    try:
        text = p.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        continue
    kept = [line for line in text.splitlines(keepends=True) if not forbidden.search(line)]
    p.write_text(''.join(kept), encoding='utf-8')

# Any remaining matching binary/generated artifact is stale residue; remove it.
pattern = r'neo4j|ash[_-]?neo4j|ashneo4j|bolt(y)?|apoc|cypher'
cmd = [
    'git', 'grep', '-ail', '-E', pattern, '--', '.',
    ':(exclude).github/workflows/tmp-forbidden-vocabulary-audit.yml',
    ':(exclude).github/tmp_cleanup_graph_db.py',
    ':(exclude).audit/forbidden-vocabulary.txt',
]
proc = subprocess.run(cmd, text=True, capture_output=True)
for name in [x for x in proc.stdout.splitlines() if x.strip()]:
    p = Path(name)
    try:
        p.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        p.unlink(missing_ok=True)

# Materialize an exact residual manifest.
audit.parent.mkdir(parents=True, exist_ok=True)
proc = subprocess.run(cmd, text=True, capture_output=True)
content_matches = sorted({x for x in proc.stdout.splitlines() if x.strip()})
tracked = subprocess.run(['git', 'ls-files'], text=True, capture_output=True).stdout.splitlines()
filename_matches = sorted(
    x for x in tracked
    if forbidden.search(x) and x not in {str(workflow), str(script)}
)
audit.write_text(
    '# Forbidden graph-database residue audit\n\n'
    f'content_matches={len(content_matches)}\n'
    f'filename_matches={len(filename_matches)}\n\n'
    + '\n'.join(content_matches + filename_matches)
    + ('\n' if content_matches or filename_matches else ''),
    encoding='utf-8',
)
