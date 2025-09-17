# Instalación Manual del Entorno Kubernetes

Este documento contiene las instrucciones para configurar manualmente un clúster Kubernetes con Kind, Cilium, Flux y Sealed Secrets en una máquina virtual Ubuntu 22.04.

## Requisitos Previos

- Máquina virtual Ubuntu 22.04 con al menos 8GB RAM y 4 CPUs
- Acceso root (sudo)
- Conexión a Internet

## 1. Preparación del Sistema

### Actualizar el sistema
```bash
sudo apt-get update -y
sudo apt-get upgrade -y
```

### Instalar dependencias básicas
```bash
sudo apt-get install -y curl wget apt-transport-https ca-certificates gnupg lsb-release
```

## 2. Instalación de Docker

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
sudo groupadd docker || true

# Agregar tu usuario al grupo docker
sudo usermod -aG docker $USER

# Aplicar los cambios de grupo (reiniciar sesión o usar newgrp)
newgrp docker

# Verificar que puedes ejecutar docker sin sudo
docker info
```

## 3. Instalación de kubectl

```bash
# Descargar kubectl v1.29.6
curl -LO "https://dl.k8s.io/release/v1.29.6/bin/linux/amd64/kubectl"

# Hacerlo ejecutable e instalarlo
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Verificar la instalación
kubectl version --client
```

## 4. Instalación de Kind

```bash
# Descargar Kind v0.27.0
curl -fsSL "https://github.com/kubernetes-sigs/kind/releases/download/v0.27.0/kind-linux-amd64" -o kind

# Hacerlo ejecutable e instalarlo
chmod +x kind
sudo mv kind /usr/local/bin/

# Verificar la instalación
kind version
```

## 5. Instalación de Helm

```bash
# Descargar e instalar Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verificar la instalación
helm version
```

## 6. Instalación de Flux CLI

```bash
# Descargar e instalar Flux CLI
curl -fsSL https://fluxcd.io/install.sh | bash

# Agregar Flux al PATH (si es necesario)
echo 'export PATH="$HOME/.flux/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verificar la instalación
flux version --client
```

## 7. Instalación de Kubeseal

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

## 8. Crear el Clúster Kind

### Crear archivo de configuración para Kind
```bash
cat > /tmp/kind-cluster-config.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
nodes:
- role: control-plane
EOF
```

### Crear el clúster
```bash
# Crear el clúster Kind
kind create cluster \
  --name kind \
  --image kindest/node:v1.31.4 \
  --config /tmp/kind-cluster-config.yaml

# Exportar la configuración de kubectl
kind export kubeconfig --name kind

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

## 9. Instalación de Cilium

### Agregar el repositorio de Helm de Cilium
```bash
helm repo add cilium https://helm.cilium.io
helm repo update
```

### Obtener la IP del nodo de control
```bash
# Obtener el nombre del nodo de control-plane
CONTROL_PLANE=$(kind get nodes --name kind | grep control-plane)

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

## 10. Instalación de Flux

```bash
# Instalar los componentes de Flux
flux install --components-extra=image-reflector-controller,image-automation-controller

# Verificar que Flux esté funcionando
kubectl get pods -n flux-system
```

## 11. Instalación de Sealed Secrets

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

## 12. Configuración del Kubeconfig para el Usuario

Si estás trabajando con un usuario diferente (por ejemplo, `vagrant`):

```bash
# Crear directorio .kube para el usuario
sudo -u vagrant mkdir -p /home/vagrant/.kube

# Exportar kubeconfig para el usuario
kind export kubeconfig \
  --name kind \
  --kubeconfig /home/vagrant/.kube/config

# Cambiar permisos
sudo chown vagrant:vagrant /home/vagrant/.kube/config
sudo chmod 600 /home/vagrant/.kube/config

# Establecer el contexto
sudo -u vagrant kubectl config use-context kind-kind
```

## 13. Verificación Final

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

echo "=== Estado General ==="
kubectl cluster-info
```

## Variables de Entorno Utilizadas

Las siguientes son las versiones específicas utilizadas en este setup:

- **KIND_VERSION**: 0.27.0
- **K8S_VERSION**: v1.29.6 (para kubectl), v1.31.4 (para el nodo Kind)
- **CILIUM_VERSION**: 1.17.2
- **KUBESEAL_VERSION**: 0.32.1
- **CLUSTER_NAME**: kind
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
kind delete cluster --name kind
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
kind delete cluster --name kind

# Opcional: eliminar imágenes Docker relacionadas
docker system prune -f
```
