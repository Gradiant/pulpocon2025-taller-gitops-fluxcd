#!/usr/bin/env bash
#
# Bootstrap a kind cluster with Cilium (kube-proxy replacement) + Flux + Sealed Secrets
# Assumes kind, kubectl, helm, flux, docker, curl are already installed.
#

set -euo pipefail

CILIUM_VERSION="${CILIUM_VERSION:-1.17.2}"
K8S_VERSION="${K8S_VERSION:-v1.31.4}"
CLUSTER_NAME="${CLUSTER_NAME:-kind}"
KIND_NODE_IMAGE="kindest/node:${K8S_VERSION}"

log_info()  { echo "[INFO]  $1"; }
log_warn()  { echo "[WARN]  $1"; }
log_error() { echo "[ERROR] $1" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || log_error "Missing dependency: $1"
}

check_requirements() {
  require_cmd curl
  require_cmd kubectl
  require_cmd docker
  require_cmd kind
  require_cmd flux
  require_cmd helm
}

create_kind_cluster() {
  if kind get clusters | grep -qx "$CLUSTER_NAME"; then
    log_info "Cluster '${CLUSTER_NAME}' already exists. Skipping creation."
    return
  fi

  log_info "Creating kind cluster '${CLUSTER_NAME}' with kube-proxy disabled..."
  cat >/tmp/kind-${CLUSTER_NAME}.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
nodes:
- role: control-plane
EOF

  kind create cluster \
    --name "${CLUSTER_NAME}" \
    --image "${KIND_NODE_IMAGE}" \
    --config /tmp/kind-${CLUSTER_NAME}.yaml

  kind export kubeconfig --name "${CLUSTER_NAME}"
}

wait_for_node() {
  log_info "Waiting for Kubernetes node(s) to register..."
  for i in {1..60}; do
    if kubectl get nodes >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done
  log_error "Timeout waiting for Kubernetes node registration."
}

setup_cilium_repo() {
  log_info "Configuring Cilium Helm repository..."
  if ! helm repo list | grep -qE '(^|[[:space:]])cilium([[:space:]]|$)'; then
    helm repo add cilium https://helm.cilium.io
  fi
  helm repo update
}

install_cilium() {
  log_info "Installing Cilium..."

  local CONTROL_PLANE
  CONTROL_PLANE="$(kind get nodes --name "${CLUSTER_NAME}" | grep control-plane)"
  local API_HOST
  API_HOST="$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CONTROL_PLANE}")"
  local API_PORT=6443

  helm upgrade --install cilium cilium/cilium \
    --version "${CILIUM_VERSION}" \
    --namespace kube-system \
    --create-namespace \
    --set image.pullPolicy=IfNotPresent \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost="${API_HOST}" \
    --set k8sServicePort="${API_PORT}" \
    --set l2announcements.enabled=true \
    --set operator.replicas=1 \
    --set gatewayAPI.enabled=true \
    --wait

  kubectl wait --namespace kube-system --for=condition=Ready --timeout=360s \
    --selector='app.kubernetes.io/part-of=cilium' pods
}

wait_for_node_ready() {
  log_info "Waiting for nodes to become Ready..."
  kubectl wait --for=condition=Ready node --all --timeout=300s
}

install_flux_components() {
  log_info "Installing Flux components..."
  flux install --components-extra=image-reflector-controller,image-automation-controller
}

install_sealed_secrets_controller() {
  log_info "Installing Sealed Secrets controller..."
  helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets >/dev/null 2>&1 || true
  helm repo update
  helm upgrade --install sealed-secrets-controller sealed-secrets/sealed-secrets \
    --namespace kube-system \
    --create-namespace \
    --wait
}

export_kubeconfig_for_user() {
  local user="${1:-vagrant}"
  local home_dir
  home_dir="$(eval echo "~${user}")"

  if ! id -u "$user" >/dev/null 2>&1; then
    log_warn "User '$user' not found; skipping kubeconfig export."
    return 0
  fi

  install -d -m 700 -o "$user" -g "$user" "${home_dir}/.kube"

  kind export kubeconfig \
    --name "${CLUSTER_NAME}" \
    --kubeconfig "${home_dir}/.kube/config"

  chown "$user:$user" "${home_dir}/.kube/config"
  chmod 600 "${home_dir}/.kube/config"

  sudo -u "$user" -H bash -lc "kubectl --kubeconfig='${home_dir}/.kube/config' config use-context 'kind-${CLUSTER_NAME}' >/dev/null 2>&1 || true"

  log_info "Kubeconfig exported to ${home_dir}/.kube/config for user '${user}'."
}


main() {
  check_requirements
  create_kind_cluster
  wait_for_node
  setup_cilium_repo
  install_cilium
  wait_for_node_ready
  install_flux_components
  install_sealed_secrets_controller
  export_kubeconfig_for_user "vagrant"
  log_info "Bootstrap completed! Cluster: ${CLUSTER_NAME}"
  kubectl get nodes -o wide
}

main "$@"
