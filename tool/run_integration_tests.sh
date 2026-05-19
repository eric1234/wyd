#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

if [[ $# -eq 0 || "${1}" == -* ]]; then
  echo "Usage: ${0##*/} <flutter-device-id> [flutter test args...]" >&2
  exit 2
fi

device="${1}"
shift

shopt -s nullglob
test_files=(integration_test/*_test.dart)

if [[ ${#test_files[@]} -eq 0 ]]; then
  echo "No integration tests found under integration_test/*_test.dart" >&2
  exit 1
fi

for test_file in "${test_files[@]}"; do
  echo "==> Running ${test_file} on ${device}"
  flutter test "${test_file}" -d "${device}" "$@"
done
