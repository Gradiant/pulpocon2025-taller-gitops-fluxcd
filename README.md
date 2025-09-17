# Pulpocon 2025 | Taller - Devops: Despliegue Continuo en Kubernetes con GitOps y FluxCD

## Preparación del taller
Para evitar los problemas del directo y no saturar la red te sugerimos preparar el entorno antes del viernes. 

## Te dejamos aquí los pasos:

1. Crea una cuenta en [GitHub](https://github.com/) si no la tienes.
2. Crea una cuenta en [DockerHub](https://hub.docker.com/) si no la tienes.
3. Instala [VirtualBox](https://www.virtualbox.org/wiki/Downloads) en tu sistema preferido.
4. Instala [Vagrant](https://developer.hashicorp.com/vagrant/install) en tu sistema preferido.
5. Clona este repo:
    ```
    git clone https://github.com/Gradiant/pulpocon2025-taller-gitops-fluxcd.git
    ```
6. Colócate en el directorio del repo y:
    ```
    cd ./vm
    vagrant up
    ```
    > Este proceso puede tardar un buen rato, ten paciencia.
    
7. Comprueba que todo haya ido bien
    ```
    ssh vagrant@192.168.56.210
    # password: vagrant

    kubectl get pods -A
    ```
    > Si ves todo en estado `Running` perfecto, ya estás listo para mañana!

## ¿Y ahora?
Ahora ya tienes una máquina virtual con todo lo necesario en tu ordenador.

Puedes apagarla (hasta el día del taller) con:
```
# desde ./vm
vagrant halt
```
volver a encenderla cuando quieras con:
```
# desde ./vm
vagrant up
```
o borrarla (despúes del taller) con:
```
# desde ./vm
vagrant destroy
```

> También puedes usar la interfaz gráfica de VirtualBox para interactuar con ella.

## Se me ha complicado esto...
Si no has sido capaz de llegar hasta el punto 7, no te preocupes, lo dejaremos listo entre todos el viernes al comezar el taller.
