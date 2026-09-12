from pathlib import Path
import re
import subprocess

root = Path('.')
workflow = Path('.github/workflows/tmp-forbidden-vocabulary-audit.yml')
script = Path('.github/tmp_cleanup_graph_db.py')
audit = Path('.audit/forbidden-vocabulary.txt')
forbidden = re.compile(r'neo4j|ash[_-]?neo4j|ashneo4j|bolt(?:y)?|apoc|cypher', re.I)


def read(path):
    return Path(path).read_text(encoding='utf-8')


def write(path, text):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8')


# CI: supported Ash/RDF/R2RML/PostgreSQL/Ontop stack only.
write('.github/workflows/ci.yaml', '''# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

name: CI

on: [push, pull_request]

concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

jobs:
  types:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Elixir / Erlang
        uses: jdx/mise-action@v2
      - name: Cache exact-toolchain deps and build
        uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('.tool-versions') }}-${{ hashFiles('**/mix.lock') }}
      - run: mix deps.get
      - name: Compile with warnings as errors
        run: mix compile --force --warnings-as-errors
      - name: Dialyzer
        run: mix dialyzer

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Elixir / Erlang
        uses: jdx/mise-action@v2
      - name: Cache exact-toolchain deps and build
        uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('.tool-versions') }}-${{ hashFiles('**/mix.lock') }}
      - run: mix deps.get
      - name: Test supported runtime surface
        run: mix test --include slow

  obda:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: ash_r2rml
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U postgres -d ash_r2rml"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 30
    steps:
      - uses: actions/checkout@v4
      - name: Set up Elixir / Erlang
        uses: jdx/mise-action@v2
      - name: Cache exact-toolchain deps and build
        uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('.tool-versions') }}-${{ hashFiles('**/mix.lock') }}
      - run: mix deps.get
      - name: Compile candidate compiler
        run: mix compile --force --warnings-as-errors
      - name: Install PostgreSQL client
        run: sudo apt-get update && sudo apt-get install -y postgresql-client
      - name: Pull pinned official Ontop image
        run: docker pull ontop/ontop:5.5.0
      - name: Supply pinned PostgreSQL JDBC driver to Ontop
        env:
          PGJDBC_VERSION: "42.7.13"
          PGJDBC_SHA256: "6e0e4cc2d8cae902084f8a2b18728b073a6fd9d1f87c9d8bff8f298c18185b93"
        run: |
          set -euo pipefail
          jdbc_dir="${RUNNER_TEMP}/ontop-jdbc"
          jdbc_jar="${jdbc_dir}/postgresql-${PGJDBC_VERSION}.jar"
          mkdir -p "${jdbc_dir}"
          curl --fail --location --silent --show-error \
            "https://repo1.maven.org/maven2/org/postgresql/postgresql/${PGJDBC_VERSION}/postgresql-${PGJDBC_VERSION}.jar" \
            --output "${jdbc_jar}"
          echo "${PGJDBC_SHA256}  ${jdbc_jar}" | sha256sum --check --strict
      - name: Execute RDF/SHACL to PostgreSQL/R2RML and SPARQL/Ontop crown
        env:
          MIX_ENV: test
          ASH_R2RML_ONTOP_JDBC_DIR: ${{ runner.temp }}/ontop-jdbc
          ASH_R2RML_PGJDBC_SHA256: "6e0e4cc2d8cae902084f8a2b18728b073a6fd9d1f87c9d8bff8f298c18185b93"
        run: mix run test/integration/obda_crown.exs
      - name: Publish bounded semantic parity receipt
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: ash-r2ml-obda-parity
          path: tmp/ash_r2rml_obda/parity-receipt.json
          if-no-files-found: ignore
''')

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

lic = read('LICENSES/MIT.md')
lic = re.sub(r'Copyright \(c\) 2025 Matthew Graham Beanland and .*?\n',
             'Copyright (c) 2025 Matthew Graham Beanland and contributors\n', lic, count=1)
write('LICENSES/MIT.md', lic)

for obsolete in ['documentation/topics/migration_from_ash_neo4j.md', 'usage-rules/cypher-fragments.md']:
    Path(obsolete).unlink(missing_ok=True)

# Remove retired cross-database witness from the public receipt contract.
p = Path('lib/ash_r2rml.ex')
text = p.read_text()
text = text.replace('          neo4j_postgres_parity: :UNKNOWN,\n', '')
text = text.replace('          :neo4j_postgres_semantic_parity,\n', '')
p.write_text(text)

p = Path('lib/ash_r2rml/compiler.ex')
text = p.read_text()
text = text.replace('    :neo4j_postgres_parity,\n', '')
text = text.replace('          neo4j_postgres_parity: :UNKNOWN | :VERIFIED,\n', '')
text = text.replace('  @doc "Cutover requires both observed parity witnesses and an explicit authority receipt."',
                    '  @doc "Cutover requires an observed query-parity witness and an explicit authority receipt."')
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
text = text.replace('when kind in [:sparql_sql, :neo4j_postgres] and is_map(witness) do',
                    'when kind == :sparql_sql and is_map(witness) do')
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
p.write_text(text)

p = Path('lib/ash_r2rml/parity.ex')
text = p.read_text()
text = text.replace('          kind: :sparql_sql | :neo4j_postgres,', '          kind: :sparql_sql,')
text = text.replace('admitted SQL/SPARQL/Cypher queries', 'admitted SQL/SPARQL queries')
text = text.replace('@spec compare(:sparql_sql | :neo4j_postgres,', '@spec compare(:sparql_sql,')
text = text.replace('when kind in [:sparql_sql, :neo4j_postgres] and is_list(left_rows) and is_list(right_rows) do',
                    'when kind == :sparql_sql and is_list(left_rows) and is_list(right_rows) do')
text = re.sub(r'\n  defp default_left\(:neo4j_postgres\), do: :neo4j', '', text)
text = re.sub(r'\n  defp default_right\(:neo4j_postgres\), do: :postgres', '', text)
p.write_text(text)

# Unit contracts now require only query parity plus explicit authority.
p = Path('test/ash_r2rml_8020_coverage_test.exs')
text = re.sub(r'^\s*neo4j_postgres_parity: .*\n', '', p.read_text(), flags=re.M)
p.write_text(text)

p = Path('test/ontology_first_compiler_test.exs')
text = p.read_text()
text = re.sub(r'\n      \|> AshR2RML\.Compiler\.attach_parity_witness\(:neo4j_postgres, %\{\n        verified\?: true,\n        receipt_sha256: "neo4j-postgres-receipt"\n      \}\)', '', text)
text = re.sub(r'^\s*assert receipt\.neo4j_postgres_parity == :VERIFIED\n', '', text, flags=re.M)
text = text.replace('cutover requires external parity witnesses and separate authority',
                    'cutover requires external query parity and separate authority')
p.write_text(text)

p = Path('test/parity_and_ggen_test.exs')
text = p.read_text()
text = re.sub(r'\n    neo4j_postgres =\n      AshR2RML\.Parity\.compare\(:neo4j_postgres, :organization, \[%\{id: "1"\}\], \[%\{"id" => "1"\}\]\)\n', '\n', text)
text = re.sub(r'\n      \|> AshR2RML\.Compiler\.attach_parity_witness\(\n        :neo4j_postgres,\n        Map\.from_struct\(neo4j_postgres\)\n      \)', '', text)
p.write_text(text)

# OBDA crown keeps Ontop CLI, SPARQL protocol, local RDF, and PostgreSQL only.
p = Path('test/integration/obda_crown.exs')
text = p.read_text()
text = re.sub(r'^# - Neo4j remains the inherited control graph\n', '', text, flags=re.M)
text = re.sub(r'^  @neo4j_url .*\n', '', text, flags=re.M)
text = re.sub(r'\n  @neo4j_query """.*?\n  """\n', '\n', text, flags=re.S)
text = re.sub(r'\n    # Execution topology 4: inherited Neo4j control graph\..*?\n    technical_receipt =', '\n    technical_receipt =', text, flags=re.S)
text = re.sub(r'\n      \|> AshR2RML\.Compiler\.attach_parity_witness\(\n        :neo4j_postgres,\n        Map\.from_struct\(neo4j_postgres\)\n      \)', '', text)
text = re.sub(r'\n    unless technical_receipt\.neo4j_postgres_parity == :VERIFIED,\n      do: raise\("Neo4j/Postgres witness was not admitted"\)\n', '\n', text)
text = re.sub(r'^\s*neo4j_postgres: neo4j_postgres,\n', '', text, flags=re.M)
text = text.replace('IO.puts("ALIVE bounded corpus: Turtle/JSON-LD + SPARQL.ex/SPARQL.Client/Ontop + Postgres/Neo4j parity")',
                    'IO.puts("ALIVE bounded corpus: Turtle/JSON-LD + SPARQL.ex/SPARQL.Client/Ontop + PostgreSQL semantic parity")')
text = re.sub(r'\n  defp seed_neo4j! do.*?(?=\n  defp json_term)', '', text, flags=re.S)
p.write_text(text)

# Preserve attribution while removing inherited product identifiers from SPDX notices.
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
    p.write_text(''.join(line for line in text.splitlines(keepends=True) if not forbidden.search(line)), encoding='utf-8')

# Remove any remaining matching binary/generated artifact from the source tree.
cmd = ['git', 'grep', '-ail', '-E', r'neo4j|ash[_-]?neo4j|ashneo4j|bolt(y)?|apoc|cypher', '--', '.',
       ':(exclude).github/workflows/tmp-forbidden-vocabulary-audit.yml',
       ':(exclude).github/tmp_cleanup_graph_db.py',
       ':(exclude).audit/forbidden-vocabulary.txt']
proc = subprocess.run(cmd, text=True, capture_output=True)
for name in [x for x in proc.stdout.splitlines() if x.strip()]:
    p = Path(name)
    try:
        p.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        p.unlink(missing_ok=True)

# Exact residual manifest.
audit.parent.mkdir(parents=True, exist_ok=True)
proc = subprocess.run(cmd, text=True, capture_output=True)
names = sorted({x for x in proc.stdout.splitlines() if x.strip()})
files = subprocess.run(['git', 'ls-files'], text=True, capture_output=True).stdout.splitlines()
bad_names = sorted(x for x in files if forbidden.search(x) and x not in {str(workflow), str(script)})
audit.write_text('# Forbidden graph-database residue audit\n\n'
                 f'content_matches={len(names)}\n'
                 f'filename_matches={len(bad_names)}\n\n'
                 + '\n'.join(names + bad_names)
                 + ('\n' if names or bad_names else ''), encoding='utf-8')
