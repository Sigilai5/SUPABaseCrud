#!/bin/bash

# Exit if any command fails
set -e

# Check if commit message is provided
if [ -z "$1" ]; then
  echo "❌ Error: Commit message required"
  echo "Usage: ./git-push.sh \"Your commit message\""
  exit 1
fi

# Stage all changes
git add .

# Commit with provided message
git commit -m "$1"

# Push to the current branch
git push origin $(git rev-parse --abbrev-ref HEAD)

echo "✅ Changes pushed successfully!"
