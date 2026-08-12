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
# KUBECONFIG RESOLUTION
# ============================================================================
resolve_kubeconfig() {
    local flag_value="${1:-}"
    local resolved=""
    local env_value="${KUBECONFIG:-}"

    if [[ -n "$flag_value" ]]; then
        resolved="$flag_value"
    elif [[ -n "$env_value" ]]; then
        resolved="$env_value"
    elif [[ -f "$HOME/.kube/config" ]]; then
        resolved="$HOME/.kube/config"
    else
        log_error "No kubeconfig found. Provide --kubeconfig, set KUBECONFIG, or place config at ~/.kube/config"
        exit 1
    fi

    if [[ ! -f "$resolved" ]]; then
        log_error "Kubeconfig file not found: $resolved"
        exit 1
    fi

    export KUBECONFIG="$resolved"
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
# CERTIFICATE EXPIRY THRESHOLDS
# ============================================================================
export CERT_EXPIRY_WARNING_DAYS=30
export CERT_EXPIRY_CRITICAL_DAYS=7

# ============================================================================
# STATUS DETERMINATION
# ============================================================================
# Determine ML-KEM compliance status based on endpoint counts
# Args: reachable_endpoints mlkem_endpoints
# Returns: PASS|PARTIAL|NONE|FAIL
determine_status() {
    local reachable="$1"
    local mlkem="$2"

    if [[ "$reachable" -eq 0 ]]; then
        echo "NONE"
    elif [[ "$mlkem" -eq "$reachable" ]]; then
        echo "PASS"
    elif [[ "$mlkem" -gt 0 ]]; then
        echo "PARTIAL"
    else
        echo "FAIL"
    fi
}

# ============================================================================
# RETRY LOGIC
# ============================================================================
# Retry a command with exponential backoff
# Args: command...
# Env: RETRY_MAX_ATTEMPTS (default: 3), RETRY_INITIAL_BACKOFF (default: 2)
# Returns: command output on success, returns non-zero exit code on failure
retry_with_backoff() {
    local max_retries="${RETRY_MAX_ATTEMPTS:-3}"
    local backoff="${RETRY_INITIAL_BACKOFF:-2}"
    local attempt=1
    local exit_code
    local output
    local stderr_file
    stderr_file=$(mktemp)

    while [[ $attempt -le $max_retries ]]; do
        output=$("$@" 2>"$stderr_file")
        exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            rm -f "$stderr_file"
            echo "$output"
            return 0
        fi

        if [[ $attempt -lt $max_retries ]]; then
            log_debug "Command failed (attempt $attempt/$max_retries), retrying in ${backoff}s: $*"
            sleep "$backoff"
            backoff=$((backoff * 2))
            attempt=$((attempt + 1))
        else
            log_error "Command failed after $max_retries attempts: $*"
            if [[ -s "$stderr_file" ]]; then
                log_debug "Last error: $(cat "$stderr_file")"
            fi
            rm -f "$stderr_file"
            return $exit_code
        fi
    done
}

# ============================================================================
# CLEANUP
# ============================================================================
# Delete TLSComplianceReport CRs for a given namespace
# Args: namespace
cleanup_reports() {
    local namespace="$1"

    log_debug "Cleaning up TLSComplianceReport CRs for namespace '$namespace'"

    local report_names
    report_names=$(retry_with_backoff oc get tlscompliancereports -o json | \
        jq -r --arg ns "$namespace" '.items[] | select(.spec.sourceNamespace == $ns) | .metadata.name' 2>/dev/null || true)

    if [[ -z "$report_names" ]]; then
        log_debug "No TLSComplianceReport CRs found for namespace '$namespace'"
        return
    fi

    local count
    count=$(echo "$report_names" | wc -l | tr -d ' ')

    echo "$report_names" | xargs -r oc delete tlscompliancereport 2>/dev/null || true
    log_success "Deleted $count TLSComplianceReport CRs from $namespace"
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
