#!/bin/bash
set -euo pipefail

# ============================================================================
# COLORS (only if terminal supports it)
# ============================================================================
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# ============================================================================
# LOGGING
# ============================================================================
LOG_LEVEL="${LOG_LEVEL:-3}"

case "$(echo "${LOG_LEVEL}" | tr '[:upper:]' '[:lower:]')" in
    quiet|q)   LOG_LEVEL=0 ;;
    error|e)   LOG_LEVEL=1 ;;
    warn|w)    LOG_LEVEL=2 ;;
    info|i)    LOG_LEVEL=3 ;;
    debug|d)   LOG_LEVEL=4 ;;
    [0-4])     ;;
    *)         LOG_LEVEL=3 ;;
esac

log_error()   { if [[ $LOG_LEVEL -ge 1 ]]; then echo -e "${RED}[ERROR]${NC} $*" >&2; fi; }
log_warn()    { if [[ $LOG_LEVEL -ge 2 ]]; then echo -e "${YELLOW}[WARN]${NC} $*"; fi; }
log_info()    { if [[ $LOG_LEVEL -ge 3 ]]; then echo -e "${BLUE}[INFO]${NC} $*"; fi; }
log_success() { if [[ $LOG_LEVEL -ge 3 ]]; then echo -e "${GREEN}[OK]${NC} $*"; fi; }
log_debug()   { if [[ $LOG_LEVEL -ge 4 ]]; then echo -e "${CYAN}[DEBUG]${NC} $*"; fi; }

# ============================================================================
# ARGUMENT PARSING HELPERS
# ============================================================================
require_arg() {
    if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        log_error "Option '$1' requires a value"
        exit 1
    fi
}

# ============================================================================
# DEPENDENCY CHECKS
# ============================================================================
require_cmd() {
    local missing=0
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "'$cmd' is required but not installed"
            missing=1
        fi
    done
    if [[ $missing -eq 1 ]]; then exit 1; fi
    return 0
}

require_cluster() {
    if ! oc whoami &>/dev/null 2>&1; then
        log_error "Not connected to cluster. Check your --kubeconfig path."
        exit 1
    fi
}

# ============================================================================
# TIMING
# ============================================================================
start_timer() {
    export _START_TIME
    _START_TIME=$(date +%s)
}

print_duration() {
    if [[ -n "${_START_TIME:-}" ]]; then
        local duration=$(($(date +%s) - _START_TIME))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        if [[ $minutes -gt 0 ]]; then
            log_info "Duration: ${minutes}m ${seconds}s"
        else
            log_info "Duration: ${seconds}s"
        fi
    fi
}

# ============================================================================
# SUMMARY
# ============================================================================
print_summary() {
    local title="$1"
    shift
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  ${title}${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    while [[ $# -ge 2 ]]; do
        printf "  %-25s %s\n" "$1:" "$2"
        shift 2
    done
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}
