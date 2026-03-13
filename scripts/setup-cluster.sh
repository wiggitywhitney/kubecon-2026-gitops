#!/usr/bin/env bash
# ABOUTME: Provisions a Kind or GKE cluster with the full KubeCon demo stack.
# ABOUTME: Installs OTel Operator, Prometheus Operator, Knative Serving, Contour, Flagger, and applies app manifests.

set -euo pipefail

# vals exec strips PATH and HOME — restore them if missing.
# This allows: vals exec -f .vals.yaml -- scripts/setup-cluster.sh gcp
if [[ -z "${HOME:-}" ]]; then
    export HOME=~
fi
if ! command -v helm &>/dev/null && [[ -d /opt/homebrew/bin ]]; then
    export PATH="/opt/homebrew/bin:/opt/homebrew/share/google-cloud-sdk/bin:${PATH}"
fi

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME_PREFIX="kubecon-gitops"
CLUSTER_NAME="${CLUSTER_NAME_PREFIX}-$(date +%Y%m%d-%H%M%S)"

# Component versions
KNATIVE_VERSION="v1.21.1"
OTEL_OPERATOR_VERSION="0.106.0"
KUBE_PROMETHEUS_STACK_VERSION="82.10.1"

# GCP configuration
GCP_PROJECT="demoo-ooclock"
GCP_ZONE="us-central1-b"
GCP_MACHINE_TYPE="n2-standard-4"
GCP_NUM_NODES="1"

# Namespaces
APPS_NAMESPACE="apps"
OBSERVABILITY_NAMESPACE="observability"

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

wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}

    log_info "Waiting for pods: namespace=${namespace} label=${label} (timeout: ${timeout}s)..."

    local elapsed=0
    local interval=5
    while [[ $elapsed -lt $timeout ]]; do
        if kubectl get pods -n "${namespace}" -l "${label}" --no-headers 2>/dev/null | grep -q .; then
            break
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    if [[ $elapsed -ge $timeout ]]; then
        log_error "No pods with label '${label}' appeared in namespace '${namespace}' within ${timeout}s"
        return 1
    fi

    local remaining=$((timeout - elapsed))
    if kubectl wait --for=condition=ready pod \
        -l "${label}" \
        -n "${namespace}" \
        --timeout="${remaining}s" &>/dev/null; then
        log_success "Pods ready: namespace=${namespace} label=${label}"
        return 0
    else
        log_error "Pods did not become ready: namespace=${namespace} label=${label}"
        return 1
    fi
}

wait_for_deployment() {
    local namespace=$1
    local name=$2
    local timeout=${3:-180}

    log_info "Waiting for deployment ${name} in ${namespace} (timeout: ${timeout}s)..."
    if kubectl wait --for=condition=available "deployment/${name}" \
        -n "${namespace}" --timeout="${timeout}s" &>/dev/null; then
        log_success "Deployment ready: ${namespace}/${name}"
    else
        log_error "Deployment not ready: ${namespace}/${name}"
        kubectl get pods -n "${namespace}" 2>/dev/null || true
        return 1
    fi
}

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_common_prerequisites() {
    local missing_tools=()

    if ! command -v kubectl &>/dev/null; then
        missing_tools+=("kubectl")
    fi

    if ! command -v helm &>/dev/null; then
        missing_tools+=("helm")
    fi

    # kustomize is optional — kubectl kustomize is used as fallback

    if [[ ${#missing_tools[@]} -ne 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
}

check_kind_prerequisites() {
    check_common_prerequisites

    if ! command -v kind &>/dev/null; then
        log_error "Missing required tool: kind"
        exit 1
    fi

    if ! docker ps &>/dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi

    log_success "Kind prerequisites satisfied"
}

check_gcp_prerequisites() {
    check_common_prerequisites

    local missing_tools=()

    if ! command -v gcloud &>/dev/null; then
        missing_tools+=("gcloud")
    fi

    if ! command -v gke-gcloud-auth-plugin &>/dev/null; then
        if command -v gcloud &>/dev/null; then
            local gcloud_sdk_bin
            gcloud_sdk_bin="$(gcloud info --format='value(installation.sdk_root)' 2>/dev/null)/bin"
            if [[ -d "${gcloud_sdk_bin}" ]] && [[ -x "${gcloud_sdk_bin}/gke-gcloud-auth-plugin" ]]; then
                export PATH="${gcloud_sdk_bin}:${PATH}"
            else
                missing_tools+=("gke-gcloud-auth-plugin")
            fi
        else
            missing_tools+=("gke-gcloud-auth-plugin")
        fi
    fi

    if [[ ${#missing_tools[@]} -ne 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    # Verify gcloud auth
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi

    # Verify project access
    if ! gcloud projects describe "${GCP_PROJECT}" &>/dev/null; then
        log_error "Cannot access GCP project: ${GCP_PROJECT}"
        exit 1
    fi

    log_success "GCP prerequisites satisfied"
}

# =============================================================================
# Phase 1: Create Cluster
# =============================================================================

create_kind_cluster() {
    log_info "Creating Kind cluster '${CLUSTER_NAME}'..."

    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_warning "Cluster '${CLUSTER_NAME}' already exists"
        exit 1
    fi

    kind create cluster --name "${CLUSTER_NAME}" --wait 60s
    log_success "Kind cluster '${CLUSTER_NAME}' created"

    kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null 2>&1
}

create_gke_cluster() {
    log_info "Creating GKE cluster '${CLUSTER_NAME}' (this may take 5-10 minutes)..."

    if gcloud container clusters describe "${CLUSTER_NAME}" \
        --zone "${GCP_ZONE}" --project "${GCP_PROJECT}" &>/dev/null; then
        log_warning "Cluster '${CLUSTER_NAME}' already exists"
        exit 1
    fi

    gcloud container clusters create "${CLUSTER_NAME}" \
        --project "${GCP_PROJECT}" \
        --zone "${GCP_ZONE}" \
        --machine-type "${GCP_MACHINE_TYPE}" \
        --num-nodes "${GCP_NUM_NODES}" \
        --quiet

    log_success "GKE cluster '${CLUSTER_NAME}' created"

    gcloud container clusters get-credentials "${CLUSTER_NAME}" \
        --zone "${GCP_ZONE}" \
        --project "${GCP_PROJECT}"

    log_success "kubectl configured for GKE cluster"

    # Wait for nodes
    log_info "Waiting for GKE nodes to become ready..."
    kubectl wait --for=condition=ready node --all --timeout=180s
    log_success "All GKE nodes are ready"
}

# =============================================================================
# Phase 2: Install cert-manager (OTel Operator dependency)
# =============================================================================

install_cert_manager() {
    log_info "Installing cert-manager..."

    if helm list -n cert-manager 2>/dev/null | grep -q cert-manager; then
        log_success "cert-manager already installed"
        return
    fi

    helm repo add jetstack https://charts.jetstack.io --force-update
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set crds.enabled=true \
        --wait --timeout 120s

    log_success "cert-manager installed"
}

# =============================================================================
# Phase 3: Install OTel Operator
# =============================================================================

install_otel_operator() {
    log_info "Installing OTel Operator v${OTEL_OPERATOR_VERSION}..."

    if helm list -n opentelemetry-operator-system 2>/dev/null | grep -q opentelemetry-operator; then
        log_success "OTel Operator already installed"
        return
    fi

    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts --force-update
    helm install opentelemetry-operator open-telemetry/opentelemetry-operator \
        --namespace opentelemetry-operator-system \
        --create-namespace \
        --version "${OTEL_OPERATOR_VERSION}" \
        --set "manager.collectorImage.repository=otel/opentelemetry-collector-contrib" \
        --wait --timeout 180s

    wait_for_deployment "opentelemetry-operator-system" "opentelemetry-operator" 120
    log_success "OTel Operator installed"
}

# =============================================================================
# Phase 4: Install Knative Serving + Contour
# =============================================================================

install_knative_serving() {
    log_info "Installing Knative Serving ${KNATIVE_VERSION}..."

    local base_url="https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}"

    # CRDs
    log_info "Installing Knative Serving CRDs..."
    kubectl apply -f "${base_url}/serving-crds.yaml"

    # Core components
    log_info "Installing Knative Serving core..."
    kubectl apply -f "${base_url}/serving-core.yaml"

    wait_for_deployment "knative-serving" "controller" 180
    log_success "Knative Serving core installed"
}

install_contour() {
    log_info "Installing Contour (Knative networking layer)..."

    local base_url="https://github.com/knative-extensions/net-contour/releases/download/knative-${KNATIVE_VERSION}"

    # Contour itself
    kubectl apply -f "${base_url}/contour.yaml"

    # Knative Contour integration
    kubectl apply -f "${base_url}/net-contour.yaml"

    # Set Contour as the default ingress class
    kubectl patch configmap/config-network \
        --namespace knative-serving \
        --type merge \
        --patch '{"data":{"ingress-class":"contour.ingress.networking.knative.dev"}}'

    wait_for_deployment "contour-external" "contour" 180
    wait_for_pods "contour-external" "app=envoy" 180
    log_success "Contour installed and configured as Knative ingress"

    # Configure magic DNS (sslip.io) for local development
    log_info "Configuring default domain (sslip.io)..."
    kubectl apply -f "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-default-domain.yaml"
    log_success "Default domain configured"
}

# =============================================================================
# Phase 5: Install Prometheus Operator
# =============================================================================

install_prometheus_operator() {
    log_info "Installing Prometheus Operator (kube-prometheus-stack v${KUBE_PROMETHEUS_STACK_VERSION})..."

    kubectl create namespace "${OBSERVABILITY_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    if helm list -n "${OBSERVABILITY_NAMESPACE}" 2>/dev/null | grep -q prometheus; then
        log_success "Prometheus Operator already installed"
        return
    fi

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
    helm install prometheus prometheus-community/kube-prometheus-stack \
        --namespace "${OBSERVABILITY_NAMESPACE}" \
        --version "${KUBE_PROMETHEUS_STACK_VERSION}" \
        --set fullnameOverride=prometheus \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --wait --timeout 300s

    wait_for_pods "${OBSERVABILITY_NAMESPACE}" "app.kubernetes.io/name=prometheus" 180
    log_success "Prometheus Operator installed in ${OBSERVABILITY_NAMESPACE}"
}

# =============================================================================
# Phase 6: Install Flagger
# =============================================================================

install_flagger() {
    log_info "Installing Flagger..."

    if helm list -n flagger-system 2>/dev/null | grep -q flagger; then
        log_success "Flagger already installed"
        return
    fi

    helm repo add flagger https://flagger.app --force-update
    helm install flagger flagger/flagger \
        --namespace flagger-system \
        --create-namespace \
        --set meshProvider=contour \
        --wait --timeout 180s

    wait_for_deployment "flagger-system" "flagger" 120
    log_success "Flagger installed"
}

# =============================================================================
# Phase 7: Create namespace and apply app manifests
# =============================================================================

setup_app_namespace() {
    log_info "Setting up ${APPS_NAMESPACE} namespace..."

    if kubectl get namespace "${APPS_NAMESPACE}" >/dev/null 2>&1; then
        log_success "Namespace '${APPS_NAMESPACE}' already exists"
    else
        kubectl create namespace "${APPS_NAMESPACE}"
        log_success "Namespace '${APPS_NAMESPACE}' created"
    fi

    # Create supply-chain ServiceAccount (used by Knative Services)
    if kubectl get serviceaccount supply-chain -n "${APPS_NAMESPACE}" >/dev/null 2>&1; then
        log_success "ServiceAccount 'supply-chain' already exists"
    else
        kubectl create serviceaccount supply-chain -n "${APPS_NAMESPACE}"
        log_success "ServiceAccount 'supply-chain' created"
    fi
}

apply_manifests() {
    # Apply observability CRs directly (not via kustomize — the kustomization includes
    # FluxCD HelmRelease manifests that require FluxCD CRDs, which aren't on test clusters).
    log_info "Applying OTel Collector and ServiceMonitor..."
    kubectl apply -f "${REPO_ROOT}/infrastructure/observability/opentelemetry-collector.yml"
    log_success "OTel Collector CR and ServiceMonitor applied"

    log_info "Applying Datadog secret placeholder..."
    kubectl apply -f "${REPO_ROOT}/infrastructure/observability/datadog-secret.yml"
    log_success "Datadog secret placeholder applied"

    log_info "Applying app manifests from apps/platform/story-app-1/..."

    # Apply kustomize manifests (includes placeholder secrets)
    if command -v kustomize &>/dev/null; then
        kustomize build "${REPO_ROOT}/apps/platform/story-app-1/" | kubectl apply -n "${APPS_NAMESPACE}" -f -
    else
        kubectl kustomize "${REPO_ROOT}/apps/platform/story-app-1/" | kubectl apply -n "${APPS_NAMESPACE}" -f -
    fi
    log_success "App manifests applied"

    # Overwrite placeholder secrets with real values (injected via vals exec)
    local missing_secrets=()

    if [[ -n "${DD_API_KEY:-}" ]]; then
        log_info "Creating Datadog API key Secret..."
        kubectl create secret generic datadog-secret \
            --namespace "${OBSERVABILITY_NAMESPACE}" \
            --from-literal=api-key="${DD_API_KEY}" \
            --dry-run=client -o yaml | kubectl apply -f -
        log_success "Datadog API key Secret created in ${OBSERVABILITY_NAMESPACE}"
    else
        missing_secrets+=("DD_API_KEY")
    fi

    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        log_info "Creating Anthropic API key Secret..."
        kubectl create secret generic anthropic \
            --namespace "${APPS_NAMESPACE}" \
            --from-literal=api-key="${ANTHROPIC_API_KEY}" \
            --dry-run=client -o yaml | kubectl apply -f -
        log_success "Anthropic API key Secret created in ${APPS_NAMESPACE}"
    else
        missing_secrets+=("ANTHROPIC_API_KEY")
    fi

    if [[ ${#missing_secrets[@]} -ne 0 ]]; then
        log_warning "Missing secrets: ${missing_secrets[*]}"
        log_warning "Re-run with: vals exec -f .vals.yaml -- $0 ${MODE}"
    fi
}

# =============================================================================
# Phase 8: Verify
# =============================================================================

verify_installation() {
    log_info "Verifying installation..."

    # Check Prometheus
    log_info "Checking Prometheus..."
    wait_for_pods "${OBSERVABILITY_NAMESPACE}" "app.kubernetes.io/name=prometheus" 120 || {
        log_warning "Prometheus pods not ready yet"
    }

    # Check OTel Collector pod
    log_info "Checking OTel Collector..."
    wait_for_pods "${OBSERVABILITY_NAMESPACE}" "app.kubernetes.io/component=opentelemetry-collector" 120 || {
        log_warning "OTel Collector pod not ready yet (may need Datadog secret)"
    }

    # Check Instrumentation CR
    if kubectl get instrumentation -n "${APPS_NAMESPACE}" >/dev/null 2>&1; then
        log_success "Instrumentation CR accepted"
    else
        log_warning "No Instrumentation CR found"
    fi

    # Check ServiceMonitor CRD is available
    if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
        log_success "ServiceMonitor CRD available"
    else
        log_warning "ServiceMonitor CRD not found"
    fi

    log_info "Cluster summary:"
    echo "  Cluster:          ${CLUSTER_NAME}"
    echo "  Mode:             ${MODE}"
    echo "  App namespace:    ${APPS_NAMESPACE}"
    echo "  Observability ns: ${OBSERVABILITY_NAMESPACE}"
    echo "  Knative Serving:  ${KNATIVE_VERSION}"
    echo "  OTel Operator:    v${OTEL_OPERATOR_VERSION}"
    echo "  Prometheus:       kube-prometheus-stack v${KUBE_PROMETHEUS_STACK_VERSION}"
    echo "  Flagger:          without bundled Prometheus"
    echo ""
    echo "  To teardown: ${SCRIPT_DIR}/teardown-cluster.sh"
}

# =============================================================================
# Main
# =============================================================================

main() {
    MODE="${1:-}"

    if [[ -z "${MODE}" ]]; then
        echo "Usage: $0 <kind|gcp>"
        echo ""
        echo "  kind  - Deploy to local Kind cluster"
        echo "  gcp   - Deploy to GKE cluster in ${GCP_PROJECT}"
        exit 1
    fi

    echo ""
    log_info "KubeCon GitOps Cluster Setup"
    log_info "============================="
    echo ""

    case "${MODE}" in
        kind)
            check_kind_prerequisites
            create_kind_cluster
            ;;
        gcp)
            check_gcp_prerequisites
            create_gke_cluster
            ;;
        *)
            log_error "Invalid mode: ${MODE}. Use 'kind' or 'gcp'."
            exit 1
            ;;
    esac

    install_cert_manager
    install_otel_operator
    install_knative_serving
    install_contour
    install_prometheus_operator
    install_flagger
    setup_app_namespace
    apply_manifests
    verify_installation

    echo ""
    log_success "Setup complete!"
}

main "$@"
