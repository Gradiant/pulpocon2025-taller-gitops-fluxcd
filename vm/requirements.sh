#!/usr/bin/env bash
#
# Install local requirements.
# This script must be run with sudo (for installing binaries system-wide).
#

set -euo pipefail

KIND_VERSION="${KIND_VERSION:-0.27.0}"
K8S_VERSION="${K8S_VERSION:-v1.29.6}"
HELM_INSTALL_SCRIPT="${HELM_INSTALL_SCRIPT:-https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3}"
FLUX_INSTALL_URL="${FLUX_INSTALL_URL:-https://fluxcd.io/install.sh}"
KUBESEAL_VERSION="${KUBESEAL_VERSION:-0.32.1}"


log_info()  { echo "[INFO]  $1"; }
log_warn()  { echo "[WARN]  $1"; }
log_error() { echo "[ERROR] $1" >&2; exit 1; }

require_sudo() {
  [[ "$EUID" -eq 0 ]] || log_error "This script must be run as root. Use sudo."
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log_info "Docker already installed."
    return
  fi
  log_info "Installing Docker (community edition)..."
  curl -fsSL https://get.docker.com | sh
  log_info "Docker installed."
}

enable_docker_service() {
  if command -v systemctl >/dev/null 2>&1; then
    log_info "Enabling and starting Docker service..."
    systemctl enable --now docker >/dev/null 2>&1 || {
      log_warn "Could not enable/start docker with systemd (non-fatal)."
    }
  else
    log_warn "systemctl not found; skipping docker service enable/start."
  fi
}

configure_docker_group() {
  if ! getent group docker >/dev/null 2>&1; then
    log_info "Creating 'docker' group..."
    groupadd --system docker
  else
    log_info "'docker' group already exists."
  fi

  add_user_to_docker() {
    local user="$1"
    [[ -z "$user" ]] && return 0
    if id -nG "$user" | grep -qw docker; then
      log_info "User '$user' already in 'docker' group."
    else
      log_info "Adding user '$user' to 'docker' group..."
      usermod -aG docker "$user"
    fi
  }

  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    add_user_to_docker "$SUDO_USER"
  fi

  for admin_group in sudo wheel; do
    if getent group "$admin_group" >/dev/null 2>&1; then
      IFS=',' read -r -a admin_users <<<"$(getent group "$admin_group" | awk -F: '{print $4}')"
      for u in "${admin_users[@]:-}"; do
        [[ -n "$u" ]] && add_user_to_docker "$u"
      done
    fi
  done

  log_warn "Users newly added to 'docker' group must log out and back in (or run 'newgrp docker') for changes to take effect."
}

install_kind() {
  if command -v kind >/dev/null 2>&1; then
    log_info "kind already installed."
    return
  fi
  log_info "Installing kind ${KIND_VERSION}..."
  curl -fsSL "https://github.com/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/kind-$(uname -s | tr '[:upper:]' '[:lower:]')-amd64" -o /usr/local/bin/kind
  chmod +x /usr/local/bin/kind
  log_info "kind installed."
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    log_info "kubectl already installed."
    return
  fi
  log_info "Installing kubectl ${K8S_VERSION}..."
  curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/$(uname | tr '[:upper:]' '[:lower:]')/amd64/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
  log_info "kubectl installed."
}

install_bash_completion() {
  if dpkg -l | grep -q bash-completion; then
    log_info "bash-completion already installed."
    return
  fi
  
  log_info "Installing bash-completion..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y bash-completion
  elif command -v yum >/dev/null 2>&1; then
    yum install -y bash-completion
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y bash-completion
  else
    log_warn "Package manager not found. bash-completion may need to be installed manually."
    return
  fi
  log_info "bash-completion installed."
}

configure_kubectl_completion() {
  log_info "Configuring kubectl autocompletion and alias..."
  
  # Add kubectl completion and alias to bashrc for all users
  local completion_config='
# Enable bash completion if available
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# kubectl autocompletion and alias
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash)
  alias k=kubectl
  complete -o default -F __start_kubectl k
fi
'
  
  # Configure for root
  if ! grep -q "kubectl completion bash" /root/.bashrc 2>/dev/null; then
    echo "$completion_config" >> /root/.bashrc
  fi
  
  # Configure for sudo user if exists
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    local user_home
    user_home="$(eval echo "~${SUDO_USER}")"
    if [[ -f "${user_home}/.bashrc" ]]; then
      if ! grep -q "kubectl completion bash" "${user_home}/.bashrc"; then
        echo "$completion_config" >> "${user_home}/.bashrc"
        chown "${SUDO_USER}:${SUDO_USER}" "${user_home}/.bashrc"
      fi
    fi
  fi
  
  # Configure for vagrant user if exists
  if id -u vagrant >/dev/null 2>&1; then
    if [[ -f "/home/vagrant/.bashrc" ]]; then
      if ! grep -q "kubectl completion bash" "/home/vagrant/.bashrc"; then
        echo "$completion_config" >> "/home/vagrant/.bashrc"
        chown vagrant:vagrant "/home/vagrant/.bashrc"
      fi
    fi
  fi
  
  log_info "kubectl autocompletion and alias 'k' configured."
}

install_helm() {
  if command -v helm >/dev/null 2>&1; then
    log_info "Helm already installed."
    return
  fi
  log_info "Installing Helm..."
  curl -fsSL "$HELM_INSTALL_SCRIPT" | bash
  log_info "Helm installed."
}

install_flux() {
  if command -v flux >/dev/null 2>&1; then
    log_info "Flux CLI already installed."
    return
  fi
  log_info "Installing Flux CLI..."
  curl -fsSL "$FLUX_INSTALL_URL" | bash
  log_info "Flux CLI installed."
}

install_kubeseal() {
  if command -v kubeseal >/dev/null 2>&1; then
    log_info "kubeseal already installed."
    return
  fi

  log_info "Installing kubeseal ${KUBESEAL_VERSION}..."
  local os="linux"
  local arch="amd64"
  local tarball="kubeseal-${KUBESEAL_VERSION}-${os}-${arch}.tar.gz"

  curl -fsSLo "${tarball}" \
    "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/${tarball}"
  
  tar -xvzf "${tarball}" kubeseal
  install -m 755 kubeseal /usr/local/bin/kubeseal

  rm -f "${tarball}" kubeseal
  log_info "kubeseal installed."
}


postcheck_docker() {
  if ! docker info >/dev/null 2>&1; then
    log_warn "Docker daemon not reachable as current user. This is expected if group changes haven't taken effect yet."
  else
    log_info "Docker daemon reachable."
  fi
}

main() {
  require_sudo
  install_docker
  enable_docker_service
  configure_docker_group
  postcheck_docker

  install_bash_completion
  install_kind
  install_kubectl
  configure_kubectl_completion
  install_helm
  install_flux
  install_kubeseal

  log_info "All requirements installed and Docker group configured!"
}

main "$@"
