# Guía Completa: Configuración de DevPod con Rackspace Spot

Esta guía te guiará a través de la configuración de DevPod para ejecutar contenedores de desarrollo basados en la nube en la infraestructura Kubernetes de Rackspace Spot a ~$0.04/hora (aproximadamente $28.80/mes para uso 24/7).

## Lo Que Obtendrás

- **Contenedores de desarrollo en la nube** similares a GitHub Codespaces
- **Costo**: ~$0.04/hora vs $0.18-0.36/hora de Codespaces
- **Entornos Linux completos** con almacenamiento persistente
- **Acceso desde cualquier lugar** - tu código vive en la nube
- **Detención automática después de inactividad** para ahorrar dinero

## Requisitos Previos

1. **Instalar DevPod**: Descargar desde [devpod.sh](https://devpod.sh)
2. **Cuenta de Rackspace Spot**: Registrarse en [spot.rackspace.com](https://spot.rackspace.com)
3. **kubectl**: Instalar en tu máquina local
4. **Crear un clúster Kubernetes** en el panel de Rackspace Spot

## Paso 1: Obtener tu Kubeconfig

1. Iniciar sesión en tu panel de Rackspace Spot
2. Navegar a tu clúster Kubernetes
3. Descargar el archivo kubeconfig
4. Guardarlo en `~/.kube/devpod-kubeconfig.yaml`

```bash
# Crear el directorio .kube si no existe
mkdir -p ~/.kube

# Copiar tu kubeconfig descargado
cp /ruta/al/kubeconfig/descargado.yaml ~/.kube/devpod-kubeconfig.yaml

# Probar la conexión
kubectl --kubeconfig ~/.kube/devpod-kubeconfig.yaml get nodes
```

## Paso 2: Verificar tus Recursos de Nodos

Averigua qué recursos estás pagando:

```bash
kubectl --kubeconfig ~/.kube/devpod-kubeconfig.yaml get node -o json | grep -A 10 "allocatable"
```

Busca los valores de CPU y memoria. Un nodo típico de $0.04/hora tiene aproximadamente:
- **CPU**: 3.5 núcleos
- **Memoria**: ~13.5Gi

## Paso 3: Configurar el Proveedor DevPod

Agregar y configurar el proveedor Kubernetes:

```bash
# Agregar el proveedor Kubernetes
devpod provider add kubernetes --name rackspace-spot

# Configurar con tus ajustes (ajustar recursos según el Paso 2)
devpod provider set-options rackspace-spot \
  -o KUBERNETES_CONFIG=$HOME/.kube/devpod-kubeconfig.yaml \
  -o KUBERNETES_CONTEXT=jmp_agentics-devpods \
  -o KUBERNETES_NAMESPACE=devpod \
  -o DISK_SIZE=20Gi \
  -o CREATE_NAMESPACE=true \
  -o INACTIVITY_TIMEOUT=5h \
  -o RESOURCES="requests.cpu=2,requests.memory=8Gi,limits.cpu=3,limits.memory=12Gi"

# Establecer como proveedor predeterminado
devpod provider use rackspace-spot

# Verificar configuración
devpod provider options rackspace-spot
```

### Configuración Explicada

- **KUBERNETES_CONFIG**: Ruta a tu archivo kubeconfig
- **KUBERNETES_CONTEXT**: Nombre del contexto de tu kubeconfig (verificar con `kubectl config get-contexts`)
- **KUBERNETES_NAMESPACE**: Espacio de nombres para espacios de trabajo DevPod (crea si no existe)
- **DISK_SIZE**: Almacenamiento persistente por espacio de trabajo
- **INACTIVITY_TIMEOUT**: Detención automática después de inactividad (5h = 5 horas)
- **RESOURCES**: Asignación de CPU/memoria por espacio de trabajo
  - `requests`: Recursos mínimos garantizados
  - `limits`: Recursos máximos que el espacio de trabajo puede usar

## Paso 4: Agregar Configuración DevContainer a tu Repositorio

**IMPORTANTE**: Antes de crear tu primer espacio de trabajo, necesitas agregar la configuración devcontainer a tu repositorio.

### Opción 1: Agregar Directamente a tu Repositorio (Recomendado)

```bash
# Clonar tu repositorio
git clone https://github.com/tuusuario/tu-repo
cd tu-repo

# Crear el directorio .devcontainer
mkdir -p .devcontainer

# Descargar la configuración devcontainer
curl -o .devcontainer/devcontainer.json \
  https://raw.githubusercontent.com/marcuspat/turbo-flow-claude/refs/heads/main/devpods/rackspace-devcontainer.json

# Confirmar y enviar
git add .devcontainer/devcontainer.json
git commit -m "Agregar configuración DevPod devcontainer"
git push
```

### Opción 2: Creación Manual

Crear `.devcontainer/devcontainer.json` en tu repositorio con este contenido:

```json
{
    "name": "Espacio de Trabajo Claude Dev",
    "image": "mcr.microsoft.com/devcontainers/base:debian",
    "remoteUser": "vscode",
    "features": {
        "ghcr.io/devcontainers/features/rust:1": {
            "version": "1.70"
        },
        "ghcr.io/devcontainers/features/docker-in-docker:2": {
            "moby": false
        },
        "ghcr.io/devcontainers/features/node:1": {}
    },
    "containerEnv": {
        "WORKSPACE_FOLDER": "${containerWorkspaceFolder}",
        "DEVPOD_WORKSPACE_FOLDER": "${containerWorkspaceFolder}",
        "AGENTS_DIR": "${containerWorkspaceFolder}/agents"
    },
    "postCreateCommand": "sudo apt-get update && sudo apt-get install -y tmux htop && cd ${containerWorkspaceFolder} && git clone https://github.com/marcuspat/turbo-flow-claude && cp -r turbo-flow-claude/devpods . && rm -rf turbo-flow-claude && chmod +x ${containerWorkspaceFolder}/devpods/*.sh 2>/dev/null || true && if [ -f ${containerWorkspaceFolder}/devpods/setup.sh ]; then ${containerWorkspaceFolder}/devpods/setup.sh; fi",
    "postStartCommand": "echo '✅ Contenedor iniciado, esperando VS Code...'",
    "postAttachCommand": "if [ -f ${containerWorkspaceFolder}/devpods/post-setup.sh ]; then chmod +x ${containerWorkspaceFolder}/devpods/post-setup.sh && ${containerWorkspaceFolder}/devpods/post-setup.sh; fi && if [ -f ${containerWorkspaceFolder}/devpods/tmux-workspace.sh ]; then chmod +x ${containerWorkspaceFolder}/devpods/tmux-workspace.sh && sed 's/tmux attach-session -t workspace/echo \"✅ espacio de trabajo tmux listo\"/' ${containerWorkspaceFolder}/devpods/tmux-workspace.sh | bash; fi",
    "customizations": {
        "vscode": {
            "extensions": [
                "rooveterinaryinc.roo-cline",
                "vsls-contrib.gistfs",
                "github.copilot",
                "github.copilot-chat"
            ],
            "settings": {
                "terminal.integrated.cwd": "${containerWorkspaceFolder}",
                "terminal.integrated.shellIntegration.enabled": true,
                "workbench.startupEditor": "none",
                "terminal.integrated.profiles.linux": {
                    "tmux-workspace": {
                        "path": "/bin/bash",
                        "args": ["-c", "tmux attach-session -t workspace 2>/dev/null || bash"]
                    }
                },
                "terminal.integrated.defaultProfile.linux": "tmux-workspace"
            }
        }
    }
}
```

### Lo Que Hace Este DevContainer

- **Imagen Base**: Contenedor de desarrollo basado en Debian
- **Características**: Instala Rust, Docker-in-Docker y Node.js
- **Scripts de Configuración**: Clona automáticamente el repositorio turbo-flow-claude y copia scripts de configuración personalizados
- **Extensiones VS Code**: Instala Roo Cline, GitHub Copilot y otras herramientas de productividad
- **Integración tmux**: Configura espacio de trabajo tmux para sesiones de terminal persistentes

## Paso 5: Crear tu Primer Espacio de Trabajo

**Después de agregar el devcontainer.json a tu repositorio**, crea tu espacio de trabajo:

```bash
# Desde un repositorio GitHub
devpod up https://github.com/tuusuario/tu-repo
```

### Lo Que Sucede Durante el Primer Lanzamiento

1. DevPod clona tu repositorio al pod Kubernetes
2. Lee `.devcontainer/devcontainer.json`
3. Descarga la imagen base Debian
4. Instala características Rust, Docker-in-Docker y Node.js
5. Ejecuta `postCreateCommand`:
   - Instala tmux y htop
   - Clona turbo-flow-claude para scripts de configuración
   - Copia carpeta `devpods/` a tu espacio de trabajo
   - Ejecuta `setup.sh` si existe
6. Abre VS Code conectado al contenedor remoto

## Paso 6: Script de Inicio Rápido (Opcional)

Crear un script para agregar rápidamente el devcontainer a nuevos repositorios:

```bash
#!/bin/bash
# Guardar como ~/bin/add-devcontainer.sh

REPO_PATH=$1

if [ -z "$REPO_PATH" ]; then
  echo "Uso: add-devcontainer.sh /ruta/al/repo"
  exit 1
fi

cd "$REPO_PATH" || exit 1
mkdir -p .devcontainer

curl -o .devcontainer/devcontainer.json \
  https://raw.githubusercontent.com/marcuspat/turbo-flow-claude/refs/heads/main/devpods/rackspace-devcontainer.json

echo "✅ ¡Configuración DevContainer agregada!"
echo "Siguientes pasos:"
echo "  git add .devcontainer/devcontainer.json"
echo "  git commit -m 'Agregar configuración DevPod'"
echo "  git push"
echo "  devpod up https://github.com/tuusuario/$(basename "$REPO_PATH")"
```

Hacerlo ejecutable:

```bash
chmod +x ~/bin/add-devcontainer.sh
```

Usarlo:

```bash
add-devcontainer.sh ~/Proyectos/mi-repo
```

## Gestión de Espacios de Trabajo

### Ver Todos los Espacios de Trabajo
```bash
devpod list
```

### Detener un Espacio de Trabajo (Preserva Datos)
```bash
devpod stop nombre-espacio-trabajo
```

### Reiniciar un Espacio de Trabajo
```bash
devpod up nombre-espacio-trabajo
```

### Eliminar un Espacio de Trabajo (Elimina Todo)
```bash
devpod delete nombre-espacio-trabajo
```

### SSH a un Espacio de Trabajo
```bash
devpod ssh nombre-espacio-trabajo
```

## Consideraciones Importantes

### Límites de Recursos
Con un nodo de 3.5 CPU / 13.5Gi RAM:
- Puedes ejecutar **~1 espacio de trabajo a capacidad completa**
- O **2-3 espacios de trabajo más pequeños** si reduces los límites de recursos
- Los espacios de trabajo detenidos no consumen recursos

### Múltiples Espacios de Trabajo
```bash
# Cada repositorio obtiene su propio pod
devpod up https://github.com/usuario/proyecto1
devpod up https://github.com/usuario/proyecto2
devpod up https://github.com/usuario/proyecto3

# Solo los espacios de trabajo activos usan recursos
```

### Gestión de Costos

**Establecer una Alerta de Presupuesto:**
1. Iniciar sesión en [Portal del Cliente Rackspace](https://manage.rackspace.com)
2. Ir a **Facturación** → **Establecer Umbral de Facturación**
3. Establecer tu límite mensual (ej., $40-50)
4. Recibirás alertas por correo electrónico al acercarte al límite

**Desglose de Costos:**
- 1 nodo 24/7: ~$28.80/mes
- Almacenamiento (20Gi PVC): ~$2-3/mes
- Salida de red: Mínima para trabajo de desarrollo
- **Total**: ~$30-35/mes

**Optimización de Costos:**
- Usar el tiempo de espera de inactividad de 5 horas (espacios de trabajo se detienen automáticamente)
- Detener espacios de trabajo al cambiar de proyectos
- Eliminar espacios de trabajo que ya no necesites

## Solución de Problemas

### Error de Recursos Insuficientes
```
0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory
```

**Solución**: Detener otros espacios de trabajo o reducir solicitudes de recursos:

```bash
# Detener espacio de trabajo no usado
devpod stop otro-espacio-trabajo

# O reducir límites de recursos
devpod provider set-options rackspace-spot \
  -o RESOURCES="requests.cpu=1,requests.memory=4Gi,limits.cpu=3,limits.memory=12Gi"
```

### Expiración de Token
Tu token kubeconfig expirará periódicamente. Cuando lo haga:
1. Descargar un kubeconfig nuevo del panel Rackspace Spot
2. Reemplazar `~/.kube/devpod-kubeconfig.yaml`
3. Los espacios de trabajo existentes se reconectarán automáticamente

### Verificar Estado del Pod
```bash
# Ver todos los pods
kubectl --kubeconfig ~/.kube/devpod-kubeconfig.yaml get pods -n devpod

# Obtener logs del pod
kubectl --kubeconfig ~/.kube/devpod-kubeconfig.yaml logs -n devpod NOMBRE_POD --tail=50
```

### El Espacio de Trabajo No Se Inicia
```bash
# Eliminar y recrear con salida de depuración
devpod delete nombre-espacio-trabajo --force
devpod up https://github.com/usuario/repo --debug
```

### DevContainer No Encontrado
Si obtienes un error sobre devcontainer.json faltante:
```bash
# Asegúrate de haberlo confirmado en tu repositorio
git add .devcontainer/devcontainer.json
git commit -m "Agregar configuración devcontainer"
git push

# Luego eliminar y recrear el espacio de trabajo
devpod delete nombre-espacio-trabajo --force
devpod up https://github.com/usuario/repo
```

## Referencia Rápida

```bash
# Agregar devcontainer al repositorio
mkdir -p .devcontainer
curl -o .devcontainer/devcontainer.json \
  https://raw.githubusercontent.com/marcuspat/turbo-flow-claude/refs/heads/main/devpods/rackspace-devcontainer.json

# Crear espacio de trabajo
devpod up https://github.com/usuario/repo

# Listar espacios de trabajo
devpod list

# Detener espacio de trabajo (guardar estado)
devpod stop nombre-espacio-trabajo

# Iniciar espacio de trabajo
devpod up nombre-espacio-trabajo

# Eliminar espacio de trabajo (permanente)
devpod delete nombre-espacio-trabajo

# SSH al espacio de trabajo
devpod ssh nombre-espacio-trabajo

# Ver logs
devpod logs nombre-espacio-trabajo

# Verificar opciones del proveedor
devpod provider options rackspace-spot
```

## Beneficios Sobre el Desarrollo Tradicional

✅ **Rentable**: ~$30/mes vs $100-300 para AWS/GCP  
✅ **Trabajo desde cualquier lugar**: Acceso desde cualquier dispositivo con VS Code  
✅ **Entornos consistentes**: Misma configuración en todos los proyectos  
✅ **Flexibilidad de recursos**: Escalar CPU/RAM según sea necesario  
✅ **Limpieza automática**: Los espacios de trabajo se detienen cuando están inactivos  
✅ **Sin dependencias locales**: Mantén tu laptop rápida y limpia  
✅ **Herramientas personalizadas**: Scripts de configuración automáticos vía turbo-flow-claude  
✅ **Integración tmux**: Sesiones de terminal persistentes  

---

**¿Necesitas Ayuda?**
- Documentos DevPod: [devpod.sh/docs](https://devpod.sh/docs)
- Documentos Rackspace Spot: [spot.rackspace.com/docs](https://spot.rackspace.com/docs)
- Soporte Rackspace: [support.rackspace.com](https://support.rackspace.com)
- DevContainer de Referencia: [turbo-flow-claude/devpods](https://github.com/marcuspat/turbo-flow-claude/tree/main/devpods)
