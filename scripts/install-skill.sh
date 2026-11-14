#!/usr/bin/env bash
# Link the kit's Claude Code skill into ~/.claude/skills so it is available in every project.
# A link, not a copy: `git pull` here updates the skill too.
set -euo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)/skills/shipping-raylib-games"
dst="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/shipping-raylib-games"
mkdir -p "$(dirname "$dst")"
if [[ -e "$dst" && ! -L "$dst" ]]; then
    echo "error: $dst exists and is not a link; move it away first" >&2
    exit 1
fi
ln -sfn "$src" "$dst"
echo "Installed: $dst -> $src"
