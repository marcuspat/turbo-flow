# Guía de Supervivencia del Clúster Kubernetes de Rackspace
## Manejo de Problemas Recurrentes Sin Perder la Cordura

Esta guía es para cuando tu clúster de Rackspace actúa mal (otra vez). Omite la teoría, aquí están las soluciones que realmente funcionan.

---

## Tabla de Contenidos
1. [Comandos de Referencia Rápida](#-comandos-de-referencia-rápida)
2. [Soluciones Rápidas: Los Más Grandes Éxitos](#soluciones-rápidas-los-más-grandes-éxitos)
3. [La Lista de Verificación "Oh Mierda"](#la-lista-de-verificación-oh-mierda)
4. [Problemas Recurrentes Comunes](#problemas-recurrentes-comunes)
5. [Verificaciones de Salud Automatizadas](#verificaciones-de-salud-automatizadas)
6. [Opciones Nucleares](#opciones-nucleares)
7. [Prevención y Monitoreo](#prevención-y-monitoreo)

---

## Comandos de Referencia Rápida

Copia y pega estos cuando la mierda golpee el ventilador. Sin explicaciones, solo soluciones.

### Problemas de Conexión

```bash
# Arreglar token expirado / no puede conectar
unset KUBECONFIG
cp fresh-kubeconfig.yaml ~/.kube/config
chmod 600 ~/.kube/config
kubectl get nodes

# Cambiar a OIDC (tokens auto-refrescantes)
kubectl config use-context jmp_agentics-devpods-1-oidc
```

### Problemas de Pods

```bash
# Forzar eliminación de pod atascado
kubectl delete pod <nombre-pod> -n <namespace> --force --grace-period=0

# Eliminar todos los pods no en ejecución en un namespace
kubectl delete pods --all -n <namespace> --force --grace-period=0

# Encontrar todos los pods problemáticos
kubectl get pods -A | grep -v "Running\|Completed"

# Obtener detalles y eventos del pod
kubectl describe pod <nombre-pod> -n <namespace>

# Obtener logs del pod
kubectl logs <nombre-pod> -n <namespace>
kubectl logs <nombre-pod> -n <namespace> --previous

# Seguir logs en tiempo real
kubectl logs -f <nombre-pod> -n <namespace>

# Shell en pod
kubectl exec -it <nombre-pod> -n <namespace> -- /bin/bash
```

### Verificaciones de Salud del Clúster

```bash
# Vista general rápida de salud
kubectl get nodes
kubectl get pods -A | grep -v Running
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Uso de recursos
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -10

# Verificar todos los componentes
kubectl get pods -n kube-system
kubectl get pods -n calico-system
kubectl get pods -n calico-apiserver

# Verificar almacenamiento
kubectl get pvc -A
```

### Problemas de Nodos

```bash
# Verificar estado del nodo
kubectl get nodes
kubectl describe node <nombre-nodo>

# Acordonar y drenar nodo problemático
kubectl cordon <nombre-nodo>
kubectl drain <nombre-nodo> --ignore-daemonsets --delete-emptydir-data --force

# Desacordonar después de arreglar
kubectl uncordon <nombre-nodo>
```

### Problemas de Red

```bash
# Reiniciar CoreDNS
kubectl rollout restart deployment coredns -n kube-system

# Reiniciar Calico
kubectl delete pods -n calico-system --all
kubectl delete pods -n calico-apiserver --all

# Probar DNS desde dentro del clúster
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Pod de depuración de red
kubectl run -it --rm netdebug --image=nicolaka/netshoot --restart=Never -- bash
```

### Problemas de Almacenamiento

```bash
# Verificar estado de PVC
kubectl get pvc -A

# Describir PVC para problemas
kubectl describe pvc <nombre-pvc> -n <namespace>

# Verificar clases de almacenamiento
kubectl get storageclass

# Forzar desmontaje (eliminar pod antiguo primero)
kubectl delete pod <nombre-pod-antiguo> -n <namespace> --force --grace-period=0
```

### Operaciones Masivas

```bash
# Eliminar todos los pods en estado Unknown/Error (¡CUIDADO!)
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded -o json | \
  jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read ns pod; do kubectl delete pod $pod -n $ns --force --grace-period=0; done

# Reiniciar todos los deployments en un namespace
kubectl rollout restart deployment -n <namespace>

# Escalar hacia abajo todos los deployments en namespace
kubectl get deployments -n <namespace> -o name | xargs -I {} kubectl scale {} --replicas=0 -n <namespace>

# Escalar de vuelta
kubectl get deployments -n <namespace> -o name | xargs -I {} kubectl scale {} --replicas=1 -n <namespace>
```

### Recopilación de Información

```bash
# Obtener toda la información del pod con ubicación del nodo
kubectl get pods -A -o wide

# Encontrar pods con reinicios altos
kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[]?.restartCount > 5) | "\(.metadata.namespace)/\(.metadata.name) reinicios: \(.status.containerStatuses[].restartCount)"'

# Obtener todos los recursos en namespace
kubectl get all -n <namespace>

# Verificar eventos recientes
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Obtener información del clúster
kubectl cluster-info
kubectl version
```

### Alias Útiles (Agregar a ~/.zshrc)

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kx='kubectl exec -it'
alias kdel='kubectl delete'
alias khealth='kubectl get nodes && echo "" && kubectl get pods -A | grep -v Running | grep -v Completed'
alias kn='kubectl config set-context --current --namespace'
```

### Comando de Emergencia "Todo Está Roto"

```bash
# Ejecutar todas las verificaciones de salud a la vez
echo "=== NODOS ===" && kubectl get nodes && \
echo -e "\n=== PODS PROBLEMÁTICOS ===" && kubectl get pods -A | grep -v "Running\|Completed" && \
echo -e "\n=== EVENTOS RECIENTES ===" && kubectl get events -A --sort-by='.lastTimestamp' | tail -15 && \
echo -e "\n=== USO DE RECURSOS ===" && kubectl top nodes && \
echo -e "\n=== COREDNS ===" && kubectl get pods -n kube-system -l k8s-app=kube-dns && \
echo -e "\n=== CALICO ===" && kubectl get pods -n calico-system
```

---

## Soluciones Rápidas: Los Más Grandes Éxitos

### Problema: Pods Atascados en `ContainerStatusUnknown`

**Lo que significa:** El nodo perdió conexión con el pod. Kubernetes no sabe si el pod está vivo o muerto.

**Solución Rápida:**
```bash
# Forzar eliminación del pod atascado
kubectl delete pod <nombre-pod> -n <namespace> --force --grace-period=0

# Si es parte de un deployment/statefulset, se recreará automáticamente
# Verificar si se recrea
kubectl get pods -n <namespace> -w
```

**Por qué funciona:** Kubernetes limpia el estado atascado y comienza de nuevo. Si está gestionado por un controlador, se recreará automáticamente.

**Prevención:**
```bash
# Agregar esto a la especificación del pod para manejar mejor los problemas del nodo
spec:
  terminationGracePeriodSeconds: 30
  tolerations:
  - key: "node.kubernetes.io/unreachable"
    operator: "Exists"
    effect: "NoExecute"
    tolerationSeconds: 30
  - key: "node.kubernetes.io/not-ready"
    operator: "Exists"
    effect: "NoExecute"
    tolerationSeconds: 30
```

---

### Problema: No Puede Conectarse al Clúster (Fallos de Búsqueda DNS)

**Síntomas:**
```
dial tcp: lookup hcp-XXXXX.spot.rackspace.com: no such host
```

**Solución Rápida:**
```bash
# 1. Verificar si tienes el kubeconfig correcto
kubectl config view --minify

# 2. Descargar kubeconfig nuevo del panel de control Rackspace
# Colocarlo en tu directorio actual como 'new-kubeconfig.yaml'

# 3. Reemplazar tu configuración
cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d)
cp new-kubeconfig.yaml ~/.kube/config
chmod 600 ~/.kube/config

# 4. Verificar variables de entorno que interfieren
echo $KUBECONFIG
# Si está configurado a algo, desconfigurar o arreglarlo
unset KUBECONFIG

# 5. Probar
kubectl get nodes
```

**Causa Raíz:** O tu token de autenticación expiró (expiran después de ~3 días), o el clúster fue reconstruido con un nuevo UUID de punto final.

---

### Problema: Token de Autenticación Expirado

**Síntomas:**
```
Unable to connect to the server: Unauthorized
```

**Solución Rápida:**
```bash
# Descargar kubeconfig nuevo de Rackspace (los tokens de autenticación expiran)
# Reemplazar tu configuración local
cp fresh-kubeconfig.yaml ~/.kube/config

# O si tienes OIDC configurado, refrescar el token
kubectl oidc-login get-token
```

**Prevención:** Configurar autenticación OIDC en lugar de tokens estáticos - se auto-refrescan.

---

### Problema: Nodos Mostrando como `NotReady`

**Verificarlo:**
```bash
kubectl get nodes
```

**Solución Rápida:**
```bash
# Describir el nodo problemático
kubectl describe node <nombre-nodo>

# Soluciones comunes:

# 1. Nodo sin recursos - verificar uso
kubectl top node <nombre-nodo>

# 2. Problema de red - reiniciar el nodo desde el panel Rackspace
# Ir a: Panel de Control Rackspace → Clúster → Nodos → Reiniciar

# 3. Si el nodo está realmente muerto, acordonarlo y drenarlo
kubectl cordon <nombre-nodo>
kubectl drain <nombre-nodo> --ignore-daemonsets --delete-emptydir-data
# Luego eliminar del panel Rackspace y dejar que auto-escale uno nuevo
```

---

### Problema: Pods Atascados en `Pending` Por Siempre

**Diagnóstico Rápido:**
```bash
kubectl describe pod <nombre-pod> -n <namespace> | grep -A 10 Events
```

**Causas Comunes y Soluciones:**

**1. Recursos Insuficientes:**
```bash
# Verificar capacidad del nodo
kubectl describe nodes | grep -A 5 "Allocated resources"

# Solución: Escalar pool de nodos en el panel Rackspace
```

**2. PVC No Se Vincula:**
```bash
# Verificar estado de PVC
kubectl get pvc -n <namespace>

# Si está atascado, verificar clase de almacenamiento
kubectl get storageclass
kubectl describe pvc <nombre-pvc> -n <namespace>

# Solución: Eliminar y recrear PVC, o provisionar almacenamiento en el panel Rackspace
```

**3. Problemas de Pull de Imagen:**
```bash
# Verificar eventos
kubectl describe pod <nombre-pod> -n <namespace>

# Soluciones comunes:
# - Agregar secretos de pull de imagen
# - Verificar si la imagen existe
# - Verificar autenticación del registro
```

---

## La Lista de Verificación "Oh Mierda"

Cuando todo está en llamas, ejecuta estos comandos en orden:

### 1. Verificar Conectividad del Clúster
```bash
# ¿Puedes alcanzar el clúster en absoluto?
kubectl cluster-info

# Si no:
# - Descargar kubeconfig nuevo de Rackspace
# - Verificar página de estado Rackspace: https://status.rackspace.com
# - Desconfigurar cualquier variable de entorno KUBECONFIG
```

### 2. Verificar Salud del Nodo
```bash
# ¿Están todos los nodos listos?
kubectl get nodes

# ¿Algún nodo NotReady o Unknown?
# → Ir al panel Rackspace y reiniciar esos nodos
```

### 3. Verificar Estado del Pod en Todo el Clúster
```bash
# ¿Qué está realmente ejecutándose?
kubectl get pods -A

# Enfocarse en:
# - Cualquier cosa en CrashLoopBackOff
# - Cualquier cosa en Error
# - Cualquier cosa en Pending por >5 minutos
# - Cualquier cosa en Unknown/ContainerStatusUnknown
```

### 4. Verificar Eventos Recientes
```bash
# ¿Qué acaba de pasar?
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Buscar:
# - FailedScheduling
# - FailedMount
# - ImagePullBackOff
# - OOMKilled
# - Evicted
```

### 5. Verificar Presión de Recursos
```bash
# ¿Están los nodos bajo presión de recursos?
kubectl top nodes
kubectl top pods -A --sort-by=memory

# Si los nodos están al >80% de memoria o CPU:
# → Escalar en el panel Rackspace inmediatamente
```

### 6. Verificar Problemas de Almacenamiento
```bash
# ¿Algún problema de PVC?
kubectl get pvc -A

# ¿Alguno atascado en Pending?
# → Verificar estado de Rackspace Cloud Block Storage
```

---

## Problemas Recurrentes Comunes

### El Problema "Token Expirado Otra Vez"

Los tokens de Rackspace Spot expiran rápidamente (~3 días). Deja de descargar configuraciones manualmente.

**Solución Permanente - Usar OIDC:**

¡Tu kubeconfig ya tiene OIDC configurado! Cambia a él:
```bash
# Listar tus contextos
kubectl config get-contexts

# Cambiar al contexto OIDC (se ve como: jmp_agentics-devpods-1-oidc)
kubectl config use-context jmp_agentics-devpods-1-oidc

# Instalar plugin kubectl oidc-login si es necesario
brew install int128/kubelogin/kubelogin

# Probar
kubectl get nodes
# ¡Esto auto-refrescará tokens!
```

---

### El Problema "Muerte Aleatoria de Pod"

**Síntomas:** Los pods mueren aleatoriamente o entran en estado Unknown.

**Causas Raíz:**
1. Presión del nodo (OOM, presión de disco)
2. Hipo de infraestructura Rackspace
3. Desalojos de pod debido a restricciones de recursos

**Solución:**
```bash
# 1. Establecer límites de recursos adecuados en TODOS los pods
kubectl set resources deployment <nombre-deployment> \
  --limits=cpu=2,memory=4Gi \
  --requests=cpu=1,memory=2Gi \
  -n <namespace>

# 2. Agregar presupuestos de interrupción de pod
kubectl create pdb <nombre-pdb> \
  --selector=app=<tu-app> \
  --min-available=1 \
  -n <namespace>

# 3. Habilitar anti-afinidad de pod para distribuir entre nodos
# Agregar a tu deployment:
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - <tu-app>
              topologyKey: kubernetes.io/hostname
```

---

### El Problema "La Red Está Rota"

**Síntomas:**
- Los pods no pueden alcanzar servicios
- DNS no resuelve
- El tráfico externo no llega al clúster

**Diagnóstico Rápido:**
```bash
# Probar DNS desde dentro del clúster
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Probar conectividad del servicio
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
# Luego dentro: curl http://<nombre-servicio>.<namespace>.svc.cluster.local

# Verificar CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

**Soluciones Comunes:**

**1. Reiniciar CoreDNS:**
```bash
kubectl rollout restart deployment coredns -n kube-system
```

**2. Verificar Calico (Rackspace usa Calico):**
```bash
kubectl get pods -n calico-system
kubectl get pods -n calico-apiserver

# Si alguno está fallando, reiniciarlos
kubectl delete pod <nombre-pod> -n calico-system
```

**3. Verificar NetworkPolicies:**
```bash
# Listar todas las políticas de red
kubectl get networkpolicies -A

# Si sospechas que están bloqueando tráfico, descríbelas
kubectl describe networkpolicy <nombre-política> -n <namespace>

# Opción nuclear: eliminar políticas problemáticas
kubectl delete networkpolicy <nombre-política> -n <namespace>
```

---

### El Problema "El Almacenamiento No Se Montará"

**Síntomas:**
- Pods atascados en ContainerCreating
- Los eventos muestran errores FailedMount

**Solución Rápida:**
```bash
# Verificar los eventos del pod
kubectl describe pod <nombre-pod> -n <namespace> | grep -A 20 Events

# Problemas comunes:

# 1. Volumen ya adjunto a otro nodo
# → Forzar eliminación del pod antiguo primero
kubectl delete pod <nombre-pod-antiguo> -n <namespace> --force --grace-period=0

# 2. PVC no existe o no está vinculado
kubectl get pvc -n <namespace>
# → Verificar Rackspace Cloud Block Storage, asegurar que el volumen existe

# 3. Clase de almacenamiento faltante
kubectl get storageclass
# → Usar 'rackspace-standard' o 'rackspace-ssd'

# 4. Volumen todavía adjunto en Rackspace
# → Ir al panel Rackspace → Cloud Block Storage → Desadjuntar el volumen
```

---

## Verificaciones de Salud Automatizadas

### Crear un Script de Verificación de Salud Diario

Guardar esto como `check-cluster-health.sh`:

```bash
#!/bin/bash

echo "=== Verificación de Salud del Clúster ==="
echo "Fecha: $(date)"
echo ""

echo "=== Estado del Nodo ==="
kubectl get nodes
echo ""

echo "=== Pods Problemáticos ==="
kubectl get pods -A | grep -v "Running\|Completed" | grep -v "NAMESPACE"
echo ""

echo "=== Eventos Recientes (Últimos 15) ==="
kubectl get events -A --sort-by='.lastTimestamp' | tail -15
echo ""

echo "=== Uso de Recursos ==="
kubectl top nodes
echo ""

echo "=== Pods Usando Más Memoria ==="
kubectl top pods -A --sort-by=memory | head -10
echo ""

echo "=== Estado de PVC ==="
kubectl get pvc -A | grep -v "Bound"
echo ""

echo "=== Pods en Unknown/ContainerStatusUnknown ==="
kubectl get pods -A | grep -E "Unknown|ContainerStatusUnknown"
echo ""

echo "=== Estado de CoreDNS ==="
kubectl get pods -n kube-system -l k8s-app=kube-dns
echo ""

echo "=== Estado de Calico ==="
kubectl get pods -n calico-system
echo ""

# Verificar pods que necesitan eliminación forzada
echo "=== Pods Que Deberían Ser Eliminados Forzadamente ==="
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.status.phase == "Unknown" or (.status.containerStatuses[]?.state.waiting.reason == "ContainerStatusUnknown")) | "\(.metadata.namespace) \(.metadata.name)"'

echo ""
echo "=== Verificación de Salud Completa ==="
```

Hacerlo ejecutable:
```bash
chmod +x check-cluster-health.sh
```

Ejecutarlo diariamente:
```bash
# Agregar a crontab (se ejecuta a las 9 AM diariamente)
crontab -e
# Agregar esta línea:
0 9 * * * /ruta/a/check-cluster-health.sh > /ruta/a/cluster-health-$(date +\%Y\%m\%d).log
```

---

### Script de Limpieza Automática para Pods Atascados

Guardar esto como `cleanup-stuck-pods.sh`:

```bash
#!/bin/bash

echo "=== Limpiando Pods Atascados ==="

# Forzar eliminación de pods en estado Unknown o ContainerStatusUnknown
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.status.phase == "Unknown" or (.status.containerStatuses[]?.state.waiting.reason == "ContainerStatusUnknown")) | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read namespace pod; do
    echo "Eliminando forzadamente: $pod en namespace $namespace"
    kubectl delete pod $pod -n $namespace --force --grace-period=0
  done

# Reiniciar cualquier pod que se haya estado reiniciando demasiado
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.status.containerStatuses[]?.restartCount > 10) | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read namespace pod; do
    echo "Alto conteo de reinicios detectado para: $pod en namespace $namespace"
    echo "  Considerar investigar o escalar hacia abajo/arriba el deployment"
  done

echo "=== Limpieza Completa ==="
```

Hacerlo ejecutable:
```bash
chmod +x cleanup-stuck-pods.sh
```

**PRECAUCIÓN:** Solo ejecuta esto si entiendes lo que hace. Fuerza la eliminación de pods.

---

## Opciones Nucleares

Cuando nada más funciona y necesitas hacer que las cosas funcionen AHORA.

### Opción Nuclear 1: Reiniciar Todos los Pods Problemáticos

```bash
# Eliminar todos los pods que no están en estado Running o Completed
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded -o json | \
  jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read namespace pod; do
    kubectl delete pod $pod -n $namespace --force --grace-period=0
  done
```

### Opción Nuclear 2: Reiniciar Todo CoreDNS y Red

```bash
# Reiniciar CoreDNS
kubectl rollout restart deployment coredns -n kube-system

# Reiniciar componentes Calico
kubectl delete pods -n calico-system --all
kubectl delete pods -n calico-apiserver --all

# Esperar a que regresen
kubectl wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=300s
```

### Opción Nuclear 3: Drenar y Reiniciar Nodos Problemáticos

```bash
# Identificar el nodo problemático
kubectl get nodes

# Acordonarlo (prevenir que se programen nuevos pods)
kubectl cordon <nombre-nodo>

# Drenarlo (mover pods existentes fuera)
kubectl drain <nombre-nodo> --ignore-daemonsets --delete-emptydir-data --force

# Ir al panel Rackspace y reiniciar el nodo
# O eliminar el nodo y dejar que el auto-escalado cree uno nuevo

# Después de que el nodo regrese, desacordonar
kubectl uncordon <nombre-nodo>
```

### Opción Nuclear 4: Reinicio Completo del Clúster (Último Recurso)

```bash
# Esto es DESTRUCTIVO - ¡respalda todo primero!

# 1. Escalar hacia abajo todos los deployments
kubectl get deployments -A -o json | \
  jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read namespace deployment; do
    kubectl scale deployment $deployment -n $namespace --replicas=0
  done

# 2. Esperar un minuto, luego escalar de vuelta
sleep 60

kubectl get deployments -A -o json | \
  jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read namespace deployment; do
    kubectl scale deployment $deployment -n $namespace --replicas=1
  done
```

---

## Prevención y Monitoreo

### 1. Establecer Límites de Recursos Adecuados

Nunca despliegues sin límites de recursos:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mi-app
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: app
        image: mi-app:latest
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

### 2. Usar Auto-Escalado Horizontal de Pods

```bash
# Auto-escalar basado en CPU
kubectl autoscale deployment <nombre-deployment> \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n <namespace>
```

### 3. Configurar Presupuestos de Interrupción de Pod

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: mi-app-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: mi-app
```

### 4. Habilitar Monitoreo

Usar Rackspace Intelligence o configurar Prometheus:

```bash
# Configuración rápida de Prometheus (si no está ya instalado)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

### 5. Crear Alertas

Configurar alertas para:
- Nodo NotReady
- Pods en CrashLoopBackOff por >5 minutos
- Alto uso de memoria/CPU (>80%)
- Fallos de montaje de PVC
- Fallos de CoreDNS

---

## Recomendaciones de Flujo de Trabajo Diario

### Rutina Matutina (5 minutos):

```bash
# Ejecutar tu verificación de salud
./check-cluster-health.sh

# Verificar pods atascados
kubectl get pods -A | grep -E "Unknown|Error|CrashLoop|ImagePull"

# Limpiar si es necesario
./cleanup-stuck-pods.sh
```

### Mantenimiento Semanal (30 minutos):

```bash
# Verificar tendencias de uso de recursos
kubectl top nodes
kubectl top pods -A --sort-by=memory

# Verificar uso de almacenamiento
kubectl get pvc -A

# Revisar y limpiar recursos antiguos/no usados
kubectl get all -A | grep -i <nombre-proyecto-antiguo>

# Actualizar cargas de trabajo pendientes
kubectl get pods -A -o wide | grep -v "Running"
```

### Tareas Mensuales:

1. Revisar y actualizar límites de recursos basados en uso real
2. Verificar actualizaciones de versión de Kubernetes de Rackspace
3. Revisar facturación de Rackspace para recursos sobre-provisionados
4. Actualizar tu kubeconfig (descargar uno nuevo)
5. Probar procedimientos de recuperación ante desastres

---

## Referencia Rápida de Comandos

### Una Línea para Tareas Comunes

```bash
# Forzar eliminación de todos los pods en un namespace
kubectl delete pods --all -n <namespace> --force --grace-period=0

# Obtener todos los pods que no están en estado Running
kubectl get pods -A --field-selector=status.phase!=Running

# Obtener todos los eventos de los últimos 15 minutos
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Encontrar pods usando más memoria
kubectl top pods -A --sort-by=memory | head -20

# Encontrar pods con altos conteos de reinicios
kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[]?.restartCount > 5) | "\(.metadata.namespace)/\(.metadata.name) reinicios
