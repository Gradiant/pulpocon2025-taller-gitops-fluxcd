# Guía del Taller GitOps con FluxCD - PulpoCon 2025

## Prerequisitos
- VM del taller
- Cuenta de GitHub
- Cuenta de DockerHub

## Paso 1: Configuración del Repositorio de Infraestructura

### 1.1 Clonar el repositorio de infraestructura en la VM
```bash
git clone https://github.com/Gradiant/pulpocon2025-taller-gitops-fluxcd-infra.git
cd pulpocon2025-taller-gitops-fluxcd-infra
```

### 1.2 Abrir el repositorio con VS Code en la VM


### 1.3 Configurar usuario y email de Git en la VM
```bash
git config --global user.name "Tu Nombre"
git config --global user.email "tu.email@ejemplo.com"
```

### 1.4 Eliminar historial Git y subir a tu GitHub
```bash
rm -rf .git
git init
git add .
git commit -m "Initial commit - GitOps infra repository"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/pulpocon2025-taller-gitops-fluxcd-infra.git
git push -u origin main
```

## Paso 2: Configuración de las Aplicaciones

### 2.1 Clonar los repositorios de aplicaciones en nuestro equipo
```bash
cd ..
git clone https://github.com/franiglesias/api-inventory.git
git clone https://github.com/annasm07/inventory-frontend.git
```

### 2.2 Configurar repositorio del backend
```bash
cd api-inventory
code .
```

Eliminar historial Git y subir a tu GitHub:
```bash
rm -rf .git
git init
git add .
git commit -m "Initial commit - Inventory API backend"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/api-inventory.git
git push -u origin main
```

### 2.3 Configurar repositorio del frontend
```bash
cd ../inventory-frontend
code .
```

Eliminar historial Git y subir a tu GitHub:
```bash
rm -rf .git
git init
git add .
git commit -m "Initial commit - Inventory frontend"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/inventory-frontend.git
git push -u origin main
```

## Paso 3: Configuración de CI/CD con GitHub Actions

### 3.1 Configurar CI para el backend (api-inventory)
Crear `.github/workflows/ci.yml` en el repositorio del backend copiando el ejemplo del repo https://github.com/Gradiant/pulpocon2025-taller-gitops-fluxcd-infra.git

### 3.2 Configurar CI para el frontend (inventory-frontend)
Crear `.github/workflows/ci.yml` en el repositorio del frontend copiando el ejemplo del repo https://github.com/Gradiant/pulpocon2025-taller-gitops-fluxcd-infra.git

### 3.3 Configurar secrets en GitHub
Para cada repositorio (backend y frontend):
1. Ve a Settings > Secrets and variables > Actions
2. Añadir secret: `DOCKERHUB_TOKEN` con tu token personal de DockerHub
3. Añadir secret: `DOCKERHUB_USERNAME` con tu usuario de DockerHub

### 3.4 Crear tags iniciales y subirlos
Para cada repositorio:
```bash
git tag v1.0.0
git push origin tags --all
```

## Paso 4: Configuración del Cluster y Secrets

### 4.1 Configurar repositorio de infra en clusters
En el repositorio de infraestructura, editar  `clusters/kind/flux.yaml` para apuntar a tu repositorio.

### 4.2 Configurar secrets de DockerHub
```bash
cd secrets
cp dockerhub-pat-secret-example.yaml dockerhub-pat-secret.yaml
```

Generar credenciales en base64:
```bash
echo -n "TU_USUARIO_DOCKERHUB:dckr_pat_xyz" | base64
```

Editar `dockerhub-pat-secret.yaml` con el resultado del base64.

### 4.3 Sellar secrets
```bash
./seal-secrets.sh
```

### 4.4 Hacer push de los cambios
```bash
git add .
git commit -m "Configure cluster and secrets"
git push
```

### 4.5 Sincronizar FluxCD
```bash
./scripts/sync-flux.sh
```

### 4.6 Añadir clave SSH en GitHub


## Paso 5: Desplegar las Aplicaciones

### 5.1 Descomentar las apps
En `clusters/kind/apps.yaml`, descomentar las secciones de las aplicaciones.

### 5.2 Configurar imágenes en los deployments
Editar los siguientes archivos para usar tus imágenes de DockerHub:

**apps/inventory-app/backend/deployment.yaml**:
```yaml
spec:
  template:
    spec:
      containers:
      - name: backend
        image: TU_USUARIO_DOCKERHUB/api-inventory:v0.1.0
```

**apps/inventory-app/frontend/deployment.yaml**:
```yaml
spec:
  template:
    spec:
      containers:
      - name: frontend
        image: TU_USUARIO_DOCKERHUB/inventory-frontend:v0.1.0
```

### 5.3 Configurar ImageRepository
**apps/inventory-app/backend/image-automation/imagerepository.yaml**:
```yaml
spec:
  image: TU_USUARIO_DOCKERHUB/api-inventory
```

**apps/inventory-app/frontend/image-automation/imagerepository.yaml**:
```yaml
spec:
  image: TU_USUARIO_DOCKERHUB/inventory-frontend
```

### 5.4 Hacer push de los cambios
```bash
git add .
git commit -m "Deploy applications with custom images"
git push
```

## Paso 6: Verificar el Despliegue

### 6.1 Acceder a la aplicación
Abrir en el navegador:
```
http://inventory-app.192.168.56.210.nip.io/
```

### 6.2 Verificar que el frontend se puede ver correctamente

## Paso 7: Probar GitOps en Acción

### 7.1 Modificar el frontend
En el repositorio `inventory-frontend`, cambiar el subtítulo en el código:
- Cambiar "Inventory Management System" por "Sistema de Gestión de Inventario - PulpoCon 2025"

### 7.2 Modificar el backend
En el repositorio `api-inventory`, cambiar la respuesta del endpoint `/`:
- Cambiar "Hello World" por "¡Hola PulpoCon 2025!"

### 7.3 Crear nuevos tags y subirlos
Para cada repositorio modificado:
```bash
git add .
git commit -m "Update for PulpoCon 2025"
git tag v1.1.0
git push origin main
git push origin v1.1.0
```

### 7.4 Observar el proceso GitOps
1. Ver las GitHub Actions construyendo las nuevas imágenes
2. Ver como FluxCD detecta las nuevas imágenes automáticamente
3. Ver los nuevos commits generados por FluxCD con las actualizaciones de imagen
4. Ver como se actualizan los deployments en el cluster

## Comandos Útiles para Debugging

### Sincronizar FluxCD manualmente
```bash
flux reconcile source git flux-system
```

### Ver pods de la aplicación
```bash
kubectl get pods -n inventory-app
```

### Probar conectividad entre servicios
```bash
kubectl exec -n inventory-app <pod> -- curl -i http://inventory-app-backend:3000/
```

### Ver logs de los pods
```bash
kubectl logs -n inventory-app -l app=inventory-app-frontend
kubectl logs -n inventory-app -l app=inventory-app-backend
```

### Ver estado de FluxCD
```bash
flux get all
```
