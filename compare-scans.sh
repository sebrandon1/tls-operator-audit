#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/compare.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <before> <after> [OPTIONS]

Compare ML-KEM support between two scan runs. Surfaces endpoints that gained
or lost ML-KEM, plus endpoints added or removed between runs.

<before> and <after> may be:
  - a timestamp (YYYYMMDD-HHMMSS) under --results-dir
  - a directory containing operator result trees
  - a path to a report.json file

Options:
  --results-dir <dir>     Results root for timestamp lookup (default: results)
  --output-format <fmt>   table (default), json, csv, or markdown
  --verbose               Enable debug output
  --quiet                 Suppress all output except errors
  -h, --help              Show this help

Exit status:
  0  no ML-KEM regressions (lost == 0)
  1  one or more endpoints lost ML-KEM support
EOF
}

BEFORE=""
AFTER=""
RESULTS_DIR="$SCRIPT_DIR/results"
OUTPUT_FORMAT="table"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --results-dir)    require_arg "$1" "${2:-}"; RESULTS_DIR="$2"; shift 2 ;;
        --output-format)  require_arg "$1" "${2:-}"; OUTPUT_FORMAT="$2"; shift 2 ;;
        --verbose)        export LOG_LEVEL=4; shift ;;
        --quiet)          export LOG_LEVEL=0; shift ;;
        -h|--help)        usage; exit 0 ;;
        --*)              log_error "Unknown option: $1"; usage; exit 1 ;;
        *)
            if [[ -z "$BEFORE" ]]; then
                BEFORE="$1"
            elif [[ -z "$AFTER" ]]; then
                AFTER="$1"
            else
                log_error "Unexpected argument: $1"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$BEFORE" || -z "$AFTER" ]]; then
    log_error "Both <before> and <after> scan runs are required"
    usage
    exit 1
fi

case "$OUTPUT_FORMAT" in
    table|json|csv|markdown) ;;
    *)
        log_error "Invalid --output-format '${OUTPUT_FORMAT}' (expected table, json, csv, or markdown)"
        exit 1
        ;;
esac

require_cmd jq

if [[ "$OUTPUT_FORMAT" != "table" && "${LOG_LEVEL:-3}" -lt 4 ]]; then
    export LOG_LEVEL=0
fi

log_info "Loading before run: $BEFORE"
before_json=$(load_run "$BEFORE" "$RESULTS_DIR")
log_info "Loading after run: $AFTER"
after_json=$(load_run "$AFTER" "$RESULTS_DIR")

diff_json=$(compare_runs "$before_json" "$after_json")
emit_compare_output "$OUTPUT_FORMAT" "$diff_json"

lost=$(compare_lost_count "$diff_json")
if [[ "$lost" -gt 0 ]]; then
    exit 1
fi
exit 0
