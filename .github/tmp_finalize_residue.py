from pathlib import Path
import re
import subprocess

root = Path('.')
audit = Path('.audit/forbidden-vocabulary.txt')
excluded = {
    '.github/workflows/tmp-forbidden-vocabulary-audit.yml',
    '.github/tmp_cleanup_graph_db.py',
    '.github/tmp_finalize_residue.py',
    '.audit/forbidden-vocabulary.txt',
}
forbidden = re.compile(r'neo4j|ash[_-]?neo4j|ashneo4j|bolt(?:y)?|apoc|cypher', re.I)

# Remove the one residual inline blocker that survived the structural pass.
p = Path('lib/ash_r2rml.ex')
text = p.read_text(encoding='utf-8')
text = text.replace(', :neo4j_postgres_semantic_parity', '')
p.write_text(text, encoding='utf-8')

pattern = r'neo4j|ash[_-]?neo4j|ashneo4j|bolt(y)?|apoc|cypher'
cmd = ['git', 'grep', '-ail', '-E', pattern, '--', '.']
proc = subprocess.run(cmd, text=True, capture_output=True)
content_matches = sorted(
    x for x in proc.stdout.splitlines()
    if x.strip() and x not in excluded
)

# Measure filenames from the actual working tree, not the pre-commit git index.
filename_matches = sorted(
    str(p) for p in root.rglob('*')
    if p.is_file()
    and '.git' not in p.parts
    and str(p) not in excluded
    and forbidden.search(str(p))
)

audit.parent.mkdir(parents=True, exist_ok=True)
audit.write_text(
    '# Forbidden graph-database residue audit\n\n'
    f'content_matches={len(content_matches)}\n'
    f'filename_matches={len(filename_matches)}\n\n'
    + '\n'.join(content_matches + filename_matches)
    + ('\n' if content_matches or filename_matches else ''),
    encoding='utf-8',
)

if content_matches or filename_matches:
    raise SystemExit(
        'forbidden residue remains:\n' + '\n'.join(content_matches + filename_matches)
    )
