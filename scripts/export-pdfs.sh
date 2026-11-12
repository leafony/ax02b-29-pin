#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

kicad_cli="${KICAD_CLI:-kicad-cli}"
kicad_version="$("$kicad_cli" version)"
case "$kicad_version" in
  10.*) ;;
  *) printf 'KiCad 10 is required (found %s).\n' "$kicad_version" >&2; exit 1 ;;
esac

# Stage both PDFs so a failed export does not replace the previous output.
mkdir -p output
staging_dir="$(mktemp -d "$repo_dir/output/.pdf.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
project="kicad/ax02-29-pin/ax02-29-pin"
layers="F.Cu,In1.Cu,In2.Cu,B.Cu,F.Silkscreen,B.Silkscreen"

"$kicad_cli" sch export pdf \
  --black-and-white --no-background-color \
  --output "$staging_dir/schematic.pdf" \
  "$project.kicad_sch"

# Plot the single board, with each layer viewed from the front (no mirroring).
"$kicad_cli" pcb export pdf \
  --mode-multipage --layers "$layers" --common-layers Edge.Cuts \
  --black-and-white --include-border-title --scale 4 --check-zones \
  --output "$staging_dir/layout.pdf" \
  "$project.kicad_pcb"

python3 - "$staging_dir" "$kicad_version" "$layers" <<'PY'
import datetime
import html
import json
from pathlib import Path
import subprocess
import sys

output = Path(sys.argv[1])
for filename in ("schematic.pdf", "layout.pdf"):
    data = (output / filename).read_bytes()
    if not data.startswith(b"%PDF-") or b"%%EOF" not in data[-1024:]:
        raise SystemExit(f"Invalid or incomplete PDF: {filename}")

commit = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], text=True).strip())
generated_at = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
metadata = {
    "repository": "leafony/ax02b-29-pin",
    "commit": commit,
    "working_tree_dirty": dirty,
    "generated_at": generated_at,
    "kicad_version": sys.argv[2],
    "schematic": "kicad/ax02-29-pin/ax02-29-pin.kicad_sch",
    "board": "kicad/ax02-29-pin/ax02-29-pin.kicad_pcb",
    "layers": sys.argv[3].split(","),
    "common_layers": ["Edge.Cuts"],
    "layout_scale": 4,
    "zone_fill": "checked and refilled if needed; source file unchanged",
}
(output / "build-info.json").write_text(
    json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
commit_url = f"https://github.com/leafony/ax02b-29-pin/commit/{commit}"
dirty_note = "（ローカルの未コミット変更を含む）" if dirty else ""
(output / "index.html").write_text(f"""<!doctype html>
<html lang="ja">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AX02B 29-pin Leaf — 設計PDF</title>
<style>
body {{ max-width: 48rem; margin: 3rem auto; padding: 0 1rem; font-family: sans-serif; line-height: 1.8; }}
a {{ color: #075dab; }}
code {{ overflow-wrap: anywhere; }}
</style>
<h1>AX02B 29-pin Leaf</h1>
<p>以下の生成元コミットに対応する回路図と基板レイアウトです。</p>
<ul>
<li><a href="schematic.pdf">回路図（PDF）</a></li>
<li><a href="layout.pdf">基板レイアウト（PDF・6ページ）</a></li>
</ul>
<p>レイアウトは単体基板の4層の銅箔と表裏のシルクです。各ページに基板外形を重ね、
すべて表面から透視した向きで表示します。閲覧用に4倍に拡大しているため原寸図ではありません。
ページ順は F.Cu、In1.Cu、In2.Cu、B.Cu、F.Silkscreen、B.Silkscreen です。</p>
<p>生成元: <a href="{commit_url}"><code>{commit}</code></a>{dirty_note}<br>
KiCad: {html.escape(sys.argv[2])}<br>生成日時（UTC）: {generated_at}</p>
<p><a href="build-info.json">生成情報（JSON）</a> ·
<a href="https://github.com/leafony/ax02b-29-pin">設計リポジトリ</a></p>
</html>
""", encoding="utf-8")
PY

mkdir -p output/pdf
cp "$staging_dir/"* output/pdf/
printf 'Generated PDFs and build information in output/pdf/\n'
