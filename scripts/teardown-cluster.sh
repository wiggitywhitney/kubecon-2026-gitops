#!/usr/bin/env bash
# ABOUTME: Deletes Kind or GKE clusters created by setup-cluster.sh.
# ABOUTME: Pattern-matches cluster names with the kubecon-gitops prefix.

set -euo pipefail

# vals exec strips PATH and HOME — restore them if missing.
if [[ -z "${HOME:-}" ]]; then
    export HOME=~
fi
if ! command -v gcloud &>/dev/null && [[ -d /opt/homebrew/bin ]]; then
    export PATH="/opt/homebrew/bin:/opt/homebrew/share/google-cloud-sdk/bin:${PATH}"
fi

# =============================================================================
# Configuration
# =============================================================================

CLUSTER_NAME_PREFIX="kubecon-gitops"
GCP_PROJECT="demoo-ooclock"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}==>${NC} $1"
}

log_success() {
    echo -e "${GREEN}[ok]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[warn]${NC} $1"
}

log_error() {
    echo -e "${RED}[error]${NC} $1"
}

# =============================================================================
# Find Clusters
# =============================================================================

find_kind_clusters() {
    if ! command -v kind &>/dev/null; then
        return
    fi

    kind get clusters 2>/dev/null | grep "^${CLUSTER_NAME_PREFIX}" || true
}

find_gke_clusters() {
    if ! command -v gcloud &>/dev/null; then
        return
    fi

    gcloud container clusters list \
        --project "${GCP_PROJECT}" \
        --filter="name~^${CLUSTER_NAME_PREFIX}" \
        --format="value(name,location)" 2>/dev/null || true
}

# =============================================================================
# Delete Clusters
# =============================================================================

delete_kind_cluster() {
    local name=$1
    log_info "Deleting Kind cluster '${name}'..."
    if kind delete cluster --name "${name}"; then
        log_success "Kind cluster '${name}' deleted"
    else
        log_error "Failed to delete Kind cluster '${name}'"
    fi
}

delete_gke_cluster() {
    local name=$1
    local location=$2
    log_info "Deleting GKE cluster '${name}' in ${location} (this may take a few minutes)..."

    # Detect if location is a zone (has 3 parts like us-central1-b) or region (2 parts)
    local location_flag="--region"
    if [[ "${location}" =~ ^[a-z]+-[a-z]+[0-9]+-[a-z]$ ]]; then
        location_flag="--zone"
    fi

    if gcloud container clusters delete "${name}" \
        --project "${GCP_PROJECT}" \
        ${location_flag} "${location}" \
        --quiet; then
        log_success "GKE cluster '${name}' deleted"
    else
        log_error "Failed to delete GKE cluster '${name}'"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    log_info "KubeCon GitOps Cluster Teardown"
    log_info "================================"
    echo ""

    local kind_clusters=()
    local gke_cluster_names=()
    local gke_cluster_locations=()

    while IFS= read -r cluster; do
        [[ -n "${cluster}" ]] && kind_clusters+=("${cluster}")
    done < <(find_kind_clusters)

    while IFS=$'\t' read -r name location; do
        if [[ -n "${name}" ]]; then
            gke_cluster_names+=("${name}")
            gke_cluster_locations+=("${location}")
        fi
    done < <(find_gke_clusters)

    if [[ ${#kind_clusters[@]} -eq 0 ]] && [[ ${#gke_cluster_names[@]} -eq 0 ]]; then
        log_warning "No clusters found matching prefix '${CLUSTER_NAME_PREFIX}'"
        exit 0
    fi

    log_info "Found clusters:"
    if [[ ${#kind_clusters[@]} -gt 0 ]]; then
        for cluster in "${kind_clusters[@]}"; do
            echo "  - Kind: ${cluster}"
        done
    fi
    if [[ ${#gke_cluster_names[@]} -gt 0 ]]; then
        for i in "${!gke_cluster_names[@]}"; do
            echo "  - GKE:  ${gke_cluster_names[$i]} (${gke_cluster_locations[$i]}, project: ${GCP_PROJECT})"
        done
    fi
    echo ""

    if [[ ${#kind_clusters[@]} -gt 0 ]]; then
        for cluster in "${kind_clusters[@]}"; do
            delete_kind_cluster "${cluster}"
        done
    fi

    if [[ ${#gke_cluster_names[@]} -gt 0 ]]; then
        for i in "${!gke_cluster_names[@]}"; do
            delete_gke_cluster "${gke_cluster_names[$i]}" "${gke_cluster_locations[$i]}"
        done
    fi

    echo ""
    log_success "Teardown complete!"
}

main "$@"
