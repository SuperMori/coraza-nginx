#!/usr/bin/env bash
# Create an automation issue or update the open issue with the same title.
set -euo pipefail

title="${1:?usage: upsert-automation-issue.sh TITLE BODY_FILE}"
body_file="${2:?missing body file}"

if [ ! -s "$body_file" ]; then
  echo "::error::issue body file is empty: ${body_file}" >&2
  exit 1
fi

issue_number="$(
  gh issue list --state open --limit 100 --json number,title |
    jq -r --arg title "$title" '.[] | select(.title == $title) | .number' |
    head -n 1
)"

if [ -n "$issue_number" ]; then
  gh issue edit "$issue_number" --body-file "$body_file"
else
  gh issue create --title "$title" --body-file "$body_file"
fi
