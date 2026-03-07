#!/bin/bash
# Tailscale ACL Documentation Generator
# Auto-generates documentation from policy.hujson

set -euo pipefail

show_help() {
    cat << HELP
Usage: $(basename "$0") [OPTIONS]

Generate documentation from Tailscale ACL policy.hujson

Options:
  -p, --policy FILE     Path to policy.hujson (default: ../policy.hujson)
  -o, --output DIR      Output directory (default: ../docs)
  --pr-comment          Generate PR comment diff (.pr-comment.md)
  --compare REF         Git ref to compare (default: HEAD~1)
  -h, --help            Show this help message
  -v, --verbose         Enable verbose output

Examples:
  $(basename "$0")                          # Basic usage
  $(basename "$0") --pr-comment             # With PR comment
  $(basename "$0") -p custom/acl.json       # Custom policy file
HELP
}

# Default values
POLICY_FILE="../policy.hujson"
OUTPUT_DIR="../docs"
PR_COMMENT=false
COMPARE_REF="HEAD~1"
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--policy)
            POLICY_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --pr-comment)
            PR_COMMENT=true
            shift
            ;;
        --compare)
            COMPARE_REF="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

log_info() {
    echo "ℹ️  $*"
}

log_error() {
    echo "❌ $*" >&2
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "🔍 $*"
    fi
}
