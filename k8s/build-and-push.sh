#!/usr/bin/env bash
# Backward-compatible wrapper. Prefer: ./scripts/build-and-push-gcr.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/build-and-push-gcr.sh" "$@"
