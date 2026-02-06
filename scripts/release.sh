#!/usr/bin/env bash
# -------------------------------------------------------------------------------------
# ---------------------------------- release.sh ---------------------------------------
# -------------------------------------------------------------------------------------
#
# Automates the full release flow:
#   1. Bumps version
#   2. Commits and tags
#   3. Pushes to remote (triggers TestFlight deploy via GitHub Actions)
#
# Usage:
#   ./scripts/release.sh patch           # Bump patch + deploy
#   ./scripts/release.sh minor           # Bump minor + deploy
#   ./scripts/release.sh 2.1.0           # Set version + deploy
#   ./scripts/release.sh 2.1.0 --dry-run # Preview without pushing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

DRY_RUN=false
BUMP_TYPE=""

# Parse arguments

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            BUMP_TYPE="$arg"
            ;;
    esac
done

if [[ -z "$BUMP_TYPE" ]]; then
    echo "✗ Usage: $0 <patch|minor|major|X.Y.Z> [--dry-run]"
    exit 1
fi

# Ensure clean working tree

cd "$PROJECT_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "✗ Working tree is not clean. Commit or stash changes first."
    exit 1
fi

# Ensure we're on main

BRANCH=$(git branch --show-current)
if [[ "$BRANCH" != "main" ]]; then
    echo "✗ Releases must be cut from 'main' (currently on '$BRANCH')"
    exit 1
fi

# Pull latest

echo "Pulling latest from origin/main..."
git pull origin main --rebase

# Bump version

"$SCRIPT_DIR/version-bump.sh" "$BUMP_TYPE"

# Extract new version for tag

NEW_VERSION=$(grep 'MARKETING_VERSION:' mobile/project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')
TAG="v$NEW_VERSION"

echo ""
echo "Version: $NEW_VERSION"
echo "Tag:     $TAG"
echo ""

if $DRY_RUN; then
    echo "[DRY RUN] Would commit, tag, and push."
    echo ""

    # Revert the version change

    git checkout mobile/project.yml
    echo "✓ Reverted project.yml (dry run)"
    exit 0
fi

# Commit, tag, push

git add mobile/project.yml
git commit -m "Release $NEW_VERSION"
git tag -a "$TAG" -m "Release $NEW_VERSION"
git push origin main --tags

echo ""
echo "✓ Release $NEW_VERSION pushed. GitHub Actions will deploy to TestFlight."
echo "  Monitor: https://github.com/<owner>/daisy/actions"
