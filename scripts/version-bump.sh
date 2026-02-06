#!/usr/bin/env bash
# -------------------------------------------------------------------------------------
# ------------------------------- version-bump.sh -------------------------------------
# -------------------------------------------------------------------------------------
#
# Bumps the MARKETING_VERSION in mobile/project.yml and creates a git tag.
#
# Usage:
#   ./scripts/version-bump.sh patch   # 1.0.0 → 1.0.1
#   ./scripts/version-bump.sh minor   # 1.0.0 → 1.1.0
#   ./scripts/version-bump.sh major   # 1.0.0 → 2.0.0
#   ./scripts/version-bump.sh 2.3.1   # Set explicit version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_YML="$PROJECT_ROOT/mobile/project.yml"

if [[ $# -lt 1 ]]; then
    echo "✗ Usage: $0 <patch|minor|major|X.Y.Z>"
    exit 1
fi

BUMP_TYPE="$1"

# Extract current version

CURRENT=$(grep 'MARKETING_VERSION:' "$PROJECT_YML" | head -1 | sed 's/.*: *"\(.*\)"/\1/')

if [[ -z "$CURRENT" ]]; then
    echo "✗ Could not find MARKETING_VERSION in $PROJECT_YML"
    exit 1
fi

echo "Current version: $CURRENT"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

# Compute new version

case "$BUMP_TYPE" in
    patch)
        NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
        ;;
    minor)
        NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
        ;;
    major)
        NEW_VERSION="$((MAJOR + 1)).0.0"
        ;;
    *)
        # Validate explicit version format

        if [[ ! "$BUMP_TYPE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "✗ Invalid version format: $BUMP_TYPE (expected X.Y.Z)"
            exit 1
        fi
        NEW_VERSION="$BUMP_TYPE"
        ;;
esac

echo "New version: $NEW_VERSION"

# Update project.yml

sed -i '' "s/MARKETING_VERSION: \"$CURRENT\"/MARKETING_VERSION: \"$NEW_VERSION\"/" "$PROJECT_YML"
echo "✓ Updated $PROJECT_YML"

# Stage and prompt for commit

echo ""
echo "Next steps:"
echo "  git add mobile/project.yml"
echo "  git commit -m \"Bump version to $NEW_VERSION\""
echo "  git tag v$NEW_VERSION"
echo "  git push origin main --tags"
