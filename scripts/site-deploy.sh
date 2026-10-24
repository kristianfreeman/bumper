#!/usr/bin/env bash
# Publishes website/ to Cloudflare Pages (project "playbumper", served at
# playbumper.com once the domain is attached in the Cloudflare dashboard).
#
#   scripts/site-deploy.sh            the live site (branch main)
#   scripts/site-deploy.sh preview    a preview URL, not the live site
#
# Signs in through `wrangler login` (your Cloudflare account) the first time.
# What's new is rebuilt from CHANGELOG.md first.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/site-changelog.py
branch="main"; [[ "${1:-}" == "preview" ]] && branch="preview"
npx --yes wrangler@4 pages deploy website --project-name=playbumper --branch="$branch" --commit-dirty=true
