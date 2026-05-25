#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Nuvio macOS Uninstall Helper
# ─────────────────────────────────────────────────────────────────────────────
#  Completely removes Nuvio and all its associated data from the system.
#
#  This script removes:
#    - Nuvio.app from /Applications (or custom install path)
#    - All user data from ~/Library/Application Support/Nuvio
#    - All caches from ~/Library/Caches/
#    - The media extension container
#    - HTTP storages
#    - Supabase session from Java preferences
#    - Keychain entries created by Nuvio
#
#  Usage:
#    ./scripts/uninstall-nuvio-macos.sh [--app-path /path/to/Nuvio.app]
#
#  Options:
#    --app-path <path>  Path to the Nuvio app bundle (default: /Applications/Nuvio.app)
#    --dry-run          Show what would be removed without actually deleting
#    -h, --help         Show this help
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

APP_PATH="/Applications/Nuvio.app"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: ./scripts/uninstall-nuvio-macos.sh [options]

Completely removes Nuvio and all its associated data from the system.

Options:
  --app-path <path>  Path to the Nuvio app bundle (default: /Applications/Nuvio.app)
  --dry-run          Show what would be removed without actually deleting
  -h, --help         Show this help

Examples:
  ./scripts/uninstall-nuvio-macos.sh
  ./scripts/uninstall-nuvio-macos.sh --app-path /Applications/Nuvio.app --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path) APP_PATH="${2:-}"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

info()  { echo -e "  \033[1m→\033[0m $*"; }
ok()    { echo -e "  \033[32m✓\033[0m $*"; }
skip()  { echo -e "  \033[33m–\033[0m $*"; }
fail()  { echo -e "  \033[31m✗\033[0m $*"; }

remove_if_exists() {
  local path="$1"
  local label="${2:-$(basename "$path")}"
  if [ -e "$path" ]; then
    if $DRY_RUN; then
      skip "Would remove: $path"
    else
      rm -rf "$path" && ok "$label removed" || fail "Failed to remove $label"
    fi
  else
    skip "$label not found, skipping"
  fi
}

echo ""
echo -e "  \033[1m══════════════════════════════════════════════════\033[0m"
echo -e "  \033[1m  Nuvio macOS Uninstall Helper\033[0m"
if $DRY_RUN; then
  echo -e "  \033[33m  DRY RUN — no files will be deleted\033[0m"
fi
echo -e "  \033[1m══════════════════════════════════════════════════\033[0m"
echo ""

# ── Remove app bundle ─────────────────────────────────────────────────────────
info "Removing app bundle..."
remove_if_exists "$APP_PATH" "Nuvio.app ($APP_PATH)"

# ── Remove user data ──────────────────────────────────────────────────────────
info "Removing application support data..."
remove_if_exists "$HOME/Library/Application Support/Nuvio" "Application Support/Nuvio"

info "Removing caches..."
remove_if_exists "$HOME/Library/Caches/com.nuvio.app" "Caches/com.nuvio.app"
remove_if_exists "$HOME/Library/Caches/Nuvio" "Caches/Nuvio"

info "Removing media extension..."
remove_if_exists "$HOME/Library/Containers/com.nuvio.media" "Containers/com.nuvio.media"
remove_if_exists "$HOME/Library/Application Scripts/com.nuvio.media" "Application Scripts/com.nuvio.media"

info "Removing HTTP storages..."
remove_if_exists "$HOME/Library/HTTPStorages/com.nuvio.app" "HTTPStorages/com.nuvio.app"

info "Removing saved state..."
remove_if_exists "$HOME/Library/Saved Application State/com.nuvio.app.savedState" "Saved Application State (main app)"
remove_if_exists "$HOME/Library/Saved Application State/com.nuvio.media.savedState" "Saved Application State (media extension)"

# ── Remove Supabase session from Java preferences ─────────────────────────────
info "Clearing Supabase session from Java preferences..."
if $DRY_RUN; then
  skip "Would remove supabase session from Java preferences"
else
  defaults delete com.apple.java.util.prefs 2>/dev/null && \
    ok "Java preferences cleared" || \
    skip "No Java preferences to clear"
fi

# ── Remove Keychain entries ───────────────────────────────────────────────────
info "Removing Nuvio entries from macOS Keychain..."
REMOVED_COUNT=0
if $DRY_RUN; then
  skip "Would remove Keychain entries with service 'com.nuvio.app'"
else
  while IFS= read -r line; do
    if [[ "$line" =~ \"acct\"\ *=\ *\"(.+)\" ]]; then
      account="${BASH_REMATCH[1]}"
      security delete-generic-password -a "$account" -s "com.nuvio.app" 2>/dev/null && \
        ((REMOVED_COUNT++)) || true
    fi
  done < <(security dump-keychain 2>/dev/null | grep -B1 "com.nuvio.app" || true)
  if [ "$REMOVED_COUNT" -gt 0 ]; then
    ok "$REMOVED_COUNT Keychain entries removed"
  else
    skip "No Nuvio Keychain entries found"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if $DRY_RUN; then
  echo -e "  \033[33m══════════════════════════════════════════════════\033[0m"
  echo -e "  \033[33m  Dry run complete — no files were deleted.\033[0m"
  echo -e "  \033[33m  Run without --dry-run to perform the uninstall.\033[0m"
  echo -e "  \033[33m══════════════════════════════════════════════════\033[0m"
else
  echo -e "  \033[32m══════════════════════════════════════════════════\033[0m"
  echo -e "  \033[32m  Nuvio has been completely removed from your system.\033[0m"
  echo -e "  \033[32m  No personal data remains.\033[0m"
  echo -e "  \033[32m══════════════════════════════════════════════════\033[0m"
fi
echo ""
