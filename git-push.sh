#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

# Get current branch name
branch=$(git rev-parse --abbrev-ref HEAD)

echo "---------------------------------------------"
echo "🚀 Git Auto Commit & Push"
echo "---------------------------------------------"
echo "Current branch: $branch"
echo ""

# Prompt for commit message
read -p "Enter commit message: " commit_msg

# Check if empty
if [ -z "$commit_msg" ]; then
  echo "❌ Error: Commit message cannot be empty."
  exit 1
fi

# Stage all changes
git add .

# Commit with message
git commit -m "$commit_msg"

# Pull latest changes to avoid conflicts
git pull origin "$branch" --rebase

# Push to same branch
git push origin "$branch"

echo ""
echo "✅ Successfully pushed to $branch"
