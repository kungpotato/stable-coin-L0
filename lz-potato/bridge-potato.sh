#!/usr/bin/env bash
# Topic 13 entry point, kept for the runbook: ./bridge-potato.sh <from> <to> <amount> [recipient]
exec "$(dirname "$0")/bridge.sh" POTATO "$@"
