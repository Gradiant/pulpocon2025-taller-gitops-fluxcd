# Instalación Manual del Entorno Kubernetes

Este documento contiene las instrucciones para configurar manualmente un clúster Kubernetes con Kind, Cilium, Flux y Sealed Secrets en una máquina virtual Ubuntu 22.04.

## Requisitos Previos

- Máquina virtual Ubuntu 22.04 con al menos 8GB RAM y 4 CPUs
- Acceso root (sudo)
- Conexión a Internet

## 1. Verificación de Dependencias

Antes de comenzar, verifica que tienes acceso a todas las herramientas necesarias:

```bash
# Verificar que curl esté disponible
command -v curl >/dev/null 2>&1 || { echo "curl no está instalado"; exit 1; }

# Verificar que wget esté disponible
command -v wget >/dev/null 2>&1 || { echo "wget no está instalado"; exit 1; }

# Verificar permisos de sudo
sudo -v || { echo "Se requieren permisos de sudo"; exit 1; }

echo "Todas las dependencias básicas están disponibles"
```

## 2. Preparación del Sistema

### Actualizar el sistema
```bash
sudo apt-get update -y
sudo apt-get upgrade -y
```

### Instalar dependencias básicas
```bash
sudo apt-get install -y curl wget apt-transport-https ca-certificates gnupg lsb-release
```

### Instalar bash-completion
```bash
# Instalar bash-completion para autocompletado
sudo apt-get install -y bash-completion
```

## 3. Instalación de Docker

### Instalar Docker Community Edition
```bash
# Descargar e instalar Docker
curl -fsSL https://get.docker.com | sudo sh
```

### Configurar el servicio Docker
```bash
# Habilitar y iniciar el servicio Docker
sudo systemctl enable docker
sudo systemctl start docker

# Verificar que Docker esté funcionando
sudo systemctl status docker
```

### Configurar permisos de usuario
```bash
# Crear el grupo docker (si no existe)
sudo groupadd --system docker 2>/dev/null || true

# Agregar el usuario actual al grupo docker
sudo usermod -aG docker $USER

# Si estás trabajando como root, agregar también otros usuarios administrativos
if [ "$EUID" -eq 0 ]; then
  # Agregar usuarios del grupo sudo al grupo docker
  for user in $(getent group sudo | cut -d: -f4 | tr ',' ' '); do
    if [ -n "$user" ]; then
      sudo usermod -aG docker "$user"
    fi
  done
fi

# Aplicar los cambios de grupo (reiniciar sesión o usar newgrp)
newgrp docker

# Verificar que puedes ejecutar docker sin sudo
docker info
```

> **Nota importante**: Los usuarios agregados al grupo docker deben cerrar sesión y volver a iniciar sesión para que los cambios surtan efecto.

## 4. Instalación de kubectl

```bash
# Descargar kubectl v1.29.6
curl -LO "https://dl.k8s.io/release/v1.29.6/bin/linux/amd64/kubectl"

# Hacerlo ejecutable e instalarlo
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Verificar la instalación
kubectl version --client
```

### Configurar autocompletado de kubectl
```bash
# Configurar autocompletado y alias para kubectl
cat >> ~/.bashrc <<'EOF'

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
EOF

# Aplicar los cambios
source ~/.bashrc
```

## 5. Instalación de Kind

```bash
# Descargar Kind v0.27.0
curl -fsSL "https://github.com/kubernetes-sigs/kind/releases/download/v0.27.0/kind-linux-amd64" -o kind

# Hacerlo ejecutable e instalarlo
chmod +x kind
sudo mv kind /usr/local/bin/

# Verificar la instalación
kind version
```

## 6. Instalación de Helm

```bash
# Descargar e instalar Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verificar la instalación
helm version
```

## 7. Instalación de Flux CLI

```bash
# Descargar e instalar Flux CLI
curl -fsSL https://fluxcd.io/install.sh | bash

# Agregar Flux al PATH (si es necesario)
echo 'export PATH="$HOME/.flux/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verificar la instalación
flux version --client
```

## 8. Instalación de Kubeseal

```bash
# Descargar kubeseal v0.32.1
curl -fsSLo kubeseal-0.32.1-linux-amd64.tar.gz \
  "https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.32.1/kubeseal-0.32.1-linux-amd64.tar.gz"

# Extraer e instalar
tar -xvzf kubeseal-0.32.1-linux-amd64.tar.gz kubeseal
sudo mv kubeseal /usr/local/bin/
chmod +x /usr/local/bin/kubeseal

# Limpiar archivos temporales
rm kubeseal-0.32.1-linux-amd64.tar.gz

# Verificar la instalación
kubeseal --version
```

## 9. Crear el Clúster Kind

### Crear archivo de configuración para Kind
```bash
cat > /tmp/kind-cluster-config.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
  - containerPort: 30443
    hostPort: 30443
    protocol: TCP
EOF
```

### Crear el clúster
```bash
# Crear el clúster Kind
kind create cluster \
  --name kind-cilium \
  --image kindest/node:v1.31.4 \
  --config /tmp/kind-cluster-config.yaml

# Exportar la configuración de kubectl
kind export kubeconfig --name kind-cilium

# Verificar que el clúster esté funcionando
kubectl get nodes
```

### Esperar a que el nodo esté registrado
```bash
# Esperar hasta que el nodo aparezca (puede tomar unos minutos)
while ! kubectl get nodes >/dev/null 2>&1; do
  echo "Esperando que el nodo se registre..."
  sleep 5
done

echo "Nodo registrado exitosamente"
```

## 10. Instalación de Cilium

### Agregar el repositorio de Helm de Cilium
```bash
helm repo add cilium https://helm.cilium.io
helm repo update
```

### Obtener la IP del nodo de control
```bash
# Obtener el nombre del nodo de control-plane
CONTROL_PLANE=$(kind get nodes --name kind-cilium | grep control-plane)

# Obtener la IP del contenedor
API_HOST=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CONTROL_PLANE}")
API_PORT=6443

echo "API Server: ${API_HOST}:${API_PORT}"
```

### Instalar Cilium
```bash
helm upgrade --install cilium cilium/cilium \
  --version 1.17.2 \
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
```

### Verificar la instalación de Cilium
```bash
# Esperar a que los pods de Cilium estén listos
kubectl wait --namespace kube-system --for=condition=Ready --timeout=360s \
  --selector='app.kubernetes.io/part-of=cilium' pods

# Verificar que los nodos estén Ready
kubectl wait --for=condition=Ready node --all --timeout=300s

# Mostrar el estado de los nodos
kubectl get nodes -o wide
```

## 11. Instalación de Flux

```bash
# Instalar los componentes de Flux
flux install --components-extra=image-reflector-controller,image-automation-controller

# Verificar que Flux esté funcionando
kubectl get pods -n flux-system
```

## 12. Instalación de Sealed Secrets

### Agregar el repositorio de Sealed Secrets
```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
```

### Instalar el controlador de Sealed Secrets
```bash
helm upgrade --install sealed-secrets-controller sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --create-namespace \
  --wait

# Verificar la instalación
kubectl get pods -n kube-system | grep sealed-secrets
```

## 13. Instalación de HAProxy

HAProxy se utiliza como balanceador de carga para redirigir el tráfico HTTP del puerto 80 al puerto 30080 del clúster.

### Instalar HAProxy
```bash
# Actualizar repositorios e instalar HAProxy
sudo apt-get update -y
sudo apt-get install -y haproxy

# Habilitar el servicio
sudo systemctl enable haproxy
```

### Configurar HAProxy
```bash
# Crear la configuración de HAProxy
sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
global
    daemon
    maxconn 2048

defaults
    mode http
    option httplog
    option dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend http
    bind *:80
    mode http
    default_backend apisix_http

backend apisix_http
    mode http
    option http-keep-alive
    option forwardfor
    http-request set-header Host %[req.hdr(Host)]
    http-request set-header X-Forwarded-Host %[req.hdr(Host)]
    http-request set-header X-Forwarded-Proto http if !{ ssl_fc }
    server apisix 127.0.0.1:30080 check
EOF
```

### Verificar y reiniciar HAProxy
```bash
# Verificar la configuración
sudo haproxy -c -V -f /etc/haproxy/haproxy.cfg

# Reiniciar el servicio
sudo systemctl restart haproxy

# Verificar que esté funcionando
sudo systemctl status haproxy
```

## 14. Configuración del Kubeconfig para el Usuario

Si estás trabajando con un usuario diferente (por ejemplo, `vagrant`):

```bash
# Crear directorio .kube para el usuario
sudo -u vagrant mkdir -p /home/vagrant/.kube

# Exportar kubeconfig para el usuario
kind export kubeconfig \
  --name kind-cilium \
  --kubeconfig /home/vagrant/.kube/config

# Cambiar permisos
sudo chown vagrant:vagrant /home/vagrant/.kube/config
sudo chmod 600 /home/vagrant/.kube/config

# Establecer el contexto
sudo -u vagrant kubectl config use-context kind-kind-cilium
```

## 15. Verificación Final

```bash
# Verificar que todos los componentes estén funcionando
echo "=== Verificación del Clúster ==="
kubectl get nodes -o wide

echo "=== Pods del Sistema ==="
kubectl get pods -A

echo "=== Servicios ==="
kubectl get svc -A

echo "=== Verificación de Cilium ==="
kubectl get pods -n kube-system -l app.kubernetes.io/part-of=cilium

echo "=== Verificación de Flux ==="
kubectl get pods -n flux-system

echo "=== Verificación de Sealed Secrets ==="
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets

echo "=== Verificación de HAProxy ==="
sudo systemctl status haproxy --no-pager -l

echo "=== Estado General ==="
kubectl cluster-info
```

## Variables de Entorno Utilizadas

Las siguientes son las versiones específicas utilizadas en este setup:

- **KIND_VERSION**: 0.27.0
- **K8S_VERSION**: v1.29.6 (para kubectl), v1.31.4 (para el nodo Kind)
- **CILIUM_VERSION**: 1.17.2
- **KUBESEAL_VERSION**: 0.32.1
- **CLUSTER_NAME**: kind-cilium
- **KIND_NODE_IMAGE**: kindest/node:v1.31.4

## Solución de Problemas

### Si Docker no funciona después de la instalación:
```bash
# Verificar el estado del servicio
sudo systemctl status docker

# Reiniciar Docker si es necesario
sudo systemctl restart docker

# Verificar permisos de grupo
groups $USER
```

### Si Kind no puede crear el clúster:
```bash
# Verificar que Docker esté funcionando
docker ps

# Limpiar clústeres existentes si es necesario
kind delete cluster --name kind-cilium
```

### Si los pods de Cilium no arrancan:
```bash
# Verificar logs de Cilium
kubectl logs -n kube-system -l app.kubernetes.io/part-of=cilium

# Verificar la configuración de red
kubectl get nodes -o wide
```

### Si Flux no se instala correctamente:
```bash
# Verificar prerequisitos de Flux
flux check --pre

# Ver logs de Flux
kubectl logs -n flux-system -l app=source-controller
```

## Limpieza

Para eliminar todo el setup:
```bash
# Eliminar el clúster Kind
kind delete cluster --name kind-cilium

# Opcional: eliminar imágenes Docker relacionadas
docker system prune -f
```
