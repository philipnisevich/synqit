#!/usr/bin/env bash
# Put `synqit` on your PATH.
#
#   git clone https://github.com/philipnisevich/synqit.git
#   cd synqit && ./install.sh
#
# Installs a symlink rather than a copy, so `git pull` updates the command with
# no reinstall step. Pass a directory to override where it lands:
#   ./install.sh ~/.local/bin
set -euo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LAUNCHER="$REPO_ROOT/bin/synqit"

say()  { printf '  %s\n' "$1"; }
ok()   { printf '  [ok] %s\n' "$1"; }
die()  { printf '  [x] %s\n' "$1" >&2; exit 1; }

[ -f "$LAUNCHER" ] || die "bin/synqit not found - run this from inside the cloned repo."
chmod +x "$LAUNCHER"

# Prefer a directory already on PATH and writable without sudo. ~/.local/bin is
# the first choice because installing into /usr/local/bin usually needs root and
# leaves a root-owned symlink behind.
if [ $# -ge 1 ]; then
  TARGET_DIR="$1"
else
  TARGET_DIR=""
  for candidate in "$HOME/.local/bin" "/usr/local/bin" "$HOME/bin"; do
    if [ -d "$candidate" ] && [ -w "$candidate" ]; then
      TARGET_DIR="$candidate"
      break
    fi
  done
  if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$HOME/.local/bin"
    mkdir -p "$TARGET_DIR"
  fi
fi

[ -d "$TARGET_DIR" ] || die "$TARGET_DIR does not exist."
[ -w "$TARGET_DIR" ] || die "$TARGET_DIR is not writable. Pass a different directory: ./install.sh ~/.local/bin"

LINK="$TARGET_DIR/synqit"

# A stale symlink from an older clone is the most likely thing already sitting
# here, and silently leaving it would keep the wrong code on PATH.
if [ -e "$LINK" ] || [ -L "$LINK" ]; then
  EXISTING="$(readlink "$LINK" 2>/dev/null || echo "$LINK")"
  if [ "$EXISTING" != "$LAUNCHER" ]; then
    say "replacing existing synqit at $LINK"
    say "  was: $EXISTING"
  fi
  rm -f "$LINK"
fi

ln -s "$LAUNCHER" "$LINK"
ok "linked $LINK -> $LAUNCHER"

case ":$PATH:" in
  *":$TARGET_DIR:"*) ;;
  *)
    say ""
    say "$TARGET_DIR is not on your PATH. Add it:"
    say "  echo 'export PATH=\"$TARGET_DIR:\$PATH\"' >> ~/.zshrc && exec zsh"
    ;;
esac

# Point at whichever synqit actually wins on PATH - a leftover install earlier
# in PATH would otherwise shadow this one and the difference is invisible.
RESOLVED="$(command -v synqit 2>/dev/null || true)"
if [ -n "$RESOLVED" ] && [ "$RESOLVED" != "$LINK" ]; then
  say ""
  say "note: another synqit earlier on PATH will be used instead:"
  say "  $RESOLVED"
fi

say ""
say "Next:"
say "  export ANTHROPIC_API_KEY=sk-ant-..."
say "  cd <your repo> && synqit doctor"
