#!/bin/zsh
# Test the addon the way a player gets it: the packaged zip, and none of the maintainer's recorded data.
#   tools/player_test.sh on [zip]   close the game first. Replaces the dev symlink with the unzipped zip (default: newest in dist/)
#                                    and moves the saved variables aside (they hold your recorded positions and options)
#   tools/player_test.sh off        restores the dev symlink and your saved variables
#   tools/player_test.sh status
set -e
GAME="/Applications/World of Warcraft/_classic_beta_"
ADDONS="$GAME/Interface/AddOns"
NAME=DungeonCrawlerForever
REPO="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$ADDONS/.player-test-active"
sv_files() { ls "$GAME"/WTF/Account/*/SavedVariables/$NAME.lua "$GAME"/WTF/Account/*/SavedVariables/$NAME.lua.bak 2>/dev/null || true; }

case "${1:-status}" in
  on)
    if pgrep -f "World of Warcraft Beta" >/dev/null; then echo "Close the game first."; exit 1; fi
    [ -e "$STAMP" ] && { echo "Player test is already on (run: tools/player_test.sh off)"; exit 1; }
    ZIP="${2:-$(ls -t "$REPO"/dist/$NAME-*.zip | head -1)}"
    [ -f "$ZIP" ] || { echo "No zip found. Run: python3 tools/package.py"; exit 1; }
    [ -L "$ADDONS/$NAME" ] || { echo "$ADDONS/$NAME is not the dev symlink, not touching it"; exit 1; }
    rm "$ADDONS/$NAME"
    unzip -q "$ZIP" -d "$ADDONS"
    for f in $(sv_files); do mv "$f" "$f.dev-backup"; done
    echo "$ZIP" > "$STAMP"
    echo "Player test ON with $(basename "$ZIP"). Saved variables moved aside. Start the game."
    ;;
  off)
    if pgrep -f "World of Warcraft Beta" >/dev/null; then echo "Close the game first."; exit 1; fi
    [ -e "$STAMP" ] || { echo "Player test is not on."; exit 1; }
    rm -rf "$ADDONS/$NAME"
    for f in "$GAME"/WTF/Account/*/SavedVariables/$NAME.lua*; do
      case "$f" in *.dev-backup) ;; *) rm -f "$f";; esac   # the files the test session wrote
    done
    for f in "$GAME"/WTF/Account/*/SavedVariables/*.dev-backup; do mv "$f" "${f%.dev-backup}"; done
    ln -sfn "$REPO/addon/$NAME" "$ADDONS/$NAME"
    rm "$STAMP"
    echo "Player test OFF: dev symlink and your saved variables are back."
    ;;
  *)
    [ -e "$STAMP" ] && echo "Player test is ON ($(cat "$STAMP"))" || echo "Player test is off (dev symlink in use)"
    ;;
esac
