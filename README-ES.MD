# Turbo Flow v4.0 — La Migración a Ruflo

<div align="center">

![Versión](https://img.shields.io/badge/versión-4.0.0-blue?style=for-the-badge)
![Ruflo](https://img.shields.io/badge/Ruflo-v3.5-purple?style=for-the-badge)
![Herramientas MCP](https://img.shields.io/badge/Herramientas_MCP-215+-green?style=for-the-badge)
![Plugins](https://img.shields.io/badge/Plugins-6-critical?style=for-the-badge)
![Licencia](https://img.shields.io/badge/licencia-MIT-orange?style=for-the-badge)
![Adventure Wave Labs](https://img.shields.io/badge/Adventure_Wave_Labs-Constructor-ff6b6b?style=for-the-badge)

**Entorno Completo de Desarrollo Agéntico — Ruflo v3.5 + Beads + Worktrees + Equipos de Agentes**

*Construido y Presentado por [Adventure Wave Labs](https://www.adventureonthewave.com/#projects)*

[Inicio Rápido](#-inicio-rápido) • [Instalación](#-qué-se-instala) • [Plugins](#-plugins-6) • [Comandos](#️-comandos-clave) • [Migración](#-migración-desde-v3x) • [Recursos](#-recursos)

</div>

---

## Acerca de Adventure Wave Labs

<div align="center">
  <img src="https://raw.githubusercontent.com/adventurewave-labs/.github/main/profile/AWLabs.webp" alt="Adventure Wave Labs" width="600">
</div>

#
**Adventure Wave Labs** es el equipo detrás de Turbo Flow un entorno completo de desarrollo agéntico construido para el ecosistema de Claude. Diseñamos, construimos y mantenemos las herramientas que integran orquestación, memoria, inteligencia de código base y aislamiento de agentes en un solo flujo de trabajo optimizado.

---

## Novedades en v4.0.0

| Métrica | v3.4.1 | v4.0.0 | Cambio |
|---------|--------|--------|--------|
| Pasos de instalación | 15 | **10** | -5 (consolidados) |
| Paquetes principales | 4 separados | **1 (Ruflo)** | -75% |
| Herramientas MCP | 175+ | **215+** | +23% |
| Agentes | 60+ | **60+** | — |
| Plugins | 15 | **6** | -9 (redundantes eliminados) |
| Memoria entre sesiones | Ninguna | **Beads** | Nuevo |
| Aislamiento de agentes | Ninguno | **Git Worktrees** | Nuevo |
| Grafo de código base | Ninguno | **GitNexus** | Nuevo |
| Habilidad UI/UX | Sí | **Sí** | Conservada |
| Línea de estado | Sí | **Sí** | Actualizada a 4.0 |

### Cambios Principales

- **claude-flow → Ruflo v3.5** — Un solo `npx ruflo@latest init` reemplaza 4 instalaciones separadas
- **Beads** — Memoria de proyecto entre sesiones vía JSONL nativo de git
- **GitNexus** — Grafo de conocimiento del código base con servidor MCP y detección de radio de impacto
- **Git Worktrees Nativos** — Aislamiento por agente con namespacing automático de esquemas PG Vector
- **Equipos de Agentes Nativos** — Generación multi-agente experimental de Anthropic
- **6 plugins enfocados** — 9 plugins redundantes/específicos de dominio eliminados
- **OpenSpec** — Desarrollo dirigido por especificaciones conservado
- **UI UX Pro Max** — Habilidad de diseño conservada
- **Statusline Pro v4.0** — Actualizado con marca TF 4.0

### Eliminados (redundantes con Ruflo v3.5 o fuera de alcance)

- `claude-flow@alpha`, `@ruvector/cli`, `@ruvector/sona`, `@claude-flow/browser` → incluidos en Ruflo
- 9 plugins: healthcare-clinical, financial-risk, legal-contracts, cognitive-kernel, hyperbolic-reasoning, quantum-optimizer, neural-coordination, prime-radiant, ruvector-upstream
- Claudish, Agentic Jujutsu, Spec-Kit, agtrace, PAL MCP → incluidos o redundantes
- HeroUI + Tailwind + TypeScript scaffold → fuera de alcance
- Ars Contexta, OpenClaw Secure Stack → fuera de alcance

---

## Arquitectura

```
+------------------------------------------------------------------+
|            TURBO FLOW v4.0 — Adventure Wave Labs                  |
+------------------------------------------------------------------+
|  INTERFAZ                                                         |
|  +---------------+  +---------------+  +---------------+          |
|  | Claude Code   |  |  Open WebUI   |  |  Statusline   |          |
|  |     CLI       |  |  (4 instancias)|  |   Pro v4.0   |          |
|  +---------------+  +---------------+  +---------------+          |
+------------------------------------------------------------------+
|  ORQUESTACIÓN: Ruflo v3.5                                         |
|  60+ Agentes | 215+ Herramientas MCP | Habilidades auto-activadas|
|  AgentDB v3 | RuVector WASM | SONA | Ruteo de modelos 3 niveles  |
|  59 Herramientas MCP de navegador | Observabilidad | Gating      |
+------------------------------------------------------------------+
|  PLUGINS (6)                                                      |
|  +--------------------------------------------------------------+ |
|  | Agentic QE | Code Intel | Test Intel | Perf | Teammate | Gas | |
|  +--------------------------------------------------------------+ |
+------------------------------------------------------------------+
|  INTELIGENCIA DE CÓDIGO BASE: GitNexus                            |
|  Grafo de Conocimiento | Detección de Radio de Impacto | MCP     |
+------------------------------------------------------------------+
|  MEMORIA (Tres Niveles)                                           |
|  +---------------+  +---------------+  +---------------+          |
|  |    Beads      |  | Tareas Nativas|  |   AgentDB     |          |
|  |  proyecto/git |  |   sesión      |  |  + RuVector   |          |
|  |    JSONL      |  |  ~/.claude/   |  |  accel WASM   |          |
|  +---------------+  +---------------+  +---------------+          |
+------------------------------------------------------------------+
|  AISLAMIENTO                                                      |
|  Git Worktrees por Agente | Esquema PG Vector por Worktree       |
|  Indexación auto GitNexus | Equipos de Agentes (experimental)    |
+------------------------------------------------------------------+
|  HABILIDADES                                                      |
|  UI UX Pro Max | OpenSpec | 36+ Habilidades auto-activadas Ruflo |
+------------------------------------------------------------------+
|  INFRAESTRUCTURA                                                  |
|  DevPod | Codespaces | Rackspace Spot                            |
+------------------------------------------------------------------+
```

---

## Inicio Rápido

### Instalación de DevPod

<details>
<summary><b>macOS</b></summary>

```bash
brew install loft-sh/devpod/devpod
```
</details>

<details>
<summary><b>Windows</b></summary>

```bash
choco install devpod
```
</details>

<details>
<summary><b>Linux</b></summary>

```bash
curl -L -o devpod "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-amd64"
sudo install devpod /usr/local/bin
```
</details>

### Lanzamiento

```bash
# DevPod (recomendado)
devpod up https://github.com/marcuspat/turbo-flow --ide vscode

# Codespaces
# Sube a GitHub → Abre en Codespace → se ejecuta automáticamente

# Manual
git clone https://github.com/marcuspat/turbo-flow -b main
cd turbo-flow
chmod +x devpods/setup.sh
./devpods/setup.sh
source ~/.bashrc
turbo-status
```

---

## Qué se Instala

El script `devpods/setup.sh` instala el stack completo en **10 pasos automatizados**:

### Paso 1: Requisitos del Sistema

| Paquete | Propósito |
|:--------|:----------|
| `build-essential` | Compilador C/C++ (gcc, g++, make) |
| `python3` | Entorno de ejecución Python |
| `git` | Control de versiones |
| `curl` | Cliente HTTP |
| `jq` | Procesador JSON (requerido para la línea de estado) |
| `Node.js 20+` | Entorno de ejecución JavaScript (requerido por Ruflo v3.5) |

### Paso 2: Claude Code + Ruflo v3.5

| Componente | Propósito |
|:-----------|:----------|
| `Claude Code` | CLI de codificación agéntica de Anthropic |
| `Ruflo v3.5` | Motor de orquestación — reemplaza claude-flow@alpha |
| Ruflo MCP | Registrado como servidor MCP en Claude Code |
| Ruflo Doctor | Diagnóstico automático y corrección |

> Ruflo v3.5 incluye: AgentDB v3, RuVector WASM, SONA, 215 herramientas MCP, 60+ agentes, sistema de habilidades, ruteo de modelos en 3 niveles, 59 herramientas MCP de automatización de navegador, observabilidad, gating

### Paso 3: Plugins de Ruflo (6) + OpenSpec

| Plugin | Propósito |
|:-------|:----------|
| **Agentic QE** | 58 agentes QE — TDD, cobertura, escaneo de seguridad, ingeniería del caos |
| **Code Intelligence** | Análisis de código, detección de patrones, sugerencias de refactorización |
| **Test Intelligence** | Generación de pruebas, análisis de brechas, detección de pruebas inestables |
| **Perf Optimizer** | Perfilado de rendimiento, detección de cuellos de botella |
| **Teammate Plugin** | Puente entre Equipos de Agentes Nativos y enjambres Ruflo (21 herramientas MCP) |
| **Gastown Bridge** | Orquestación acelerada por WASM, sincronización de Beads (20 herramientas MCP) |
| **OpenSpec** | Desarrollo dirigido por especificaciones (paquete npm independiente) |

### Paso 4: Habilidad UI UX Pro Max

| Componente | Propósito |
|:-----------|:----------|
| `uipro-cli` | Habilidad de sistema de diseño — patrones de componentes, accesibilidad, layouts responsivos, tokens de diseño |

### Paso 5: GitNexus (Grafo de Conocimiento del Código Base)

| Componente | Propósito |
|:-----------|:----------|
| `GitNexus` | Indexa dependencias, cadenas de llamadas, flujos de ejecución |
| GitNexus MCP | Registrado como servidor MCP — detección de radio de impacto |

### Paso 6: Beads (Memoria entre Sesiones)

| Componente | Propósito |
|:-----------|:----------|
| `@beads/bd` | Memoria de proyecto JSONL nativa de git — issues, decisiones, bloqueos |

### Paso 7: Espacio de Trabajo + Equipos de Agentes

| Componente | Propósito |
|:-----------|:----------|
| Directorios | `src/` `tests/` `docs/` `scripts/` `config/` `plans/` |
| Equipos de Agentes | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` habilitado |

### Paso 8: Statusline Pro v4.0

Línea de estado de 3 líneas con 15 componentes:

```
LÍNEA 1: [Proyecto] nombre | [Modelo] Sonnet | [Git] rama | [TF] 4.0 | [SID] abc123
LÍNEA 2: [Tokens] 50k/200k | [Ctx] #######--- 65% | [Caché] 42% | [Costo] $1.23 | [Tiempo] 5m
LÍNEA 3: [+150] [-50] | [LISTO]
```

### Paso 9: Generación de CLAUDE.md

Genera el archivo de contexto del espacio de trabajo con:
- Protocolo de memoria de 3 niveles (Beads → Tareas Nativas → AgentDB)
- Reglas de aislamiento (un worktree por agente)
- Reglas de Equipos de Agentes (máximo 3 compañeros, profundidad de recursión 2)
- Niveles de ruteo de modelos (Opus/Sonnet/Haiku)
- Referencia de plugins
- Límites de costo ($15/hr)

### Paso 10: Alias + Entorno + Registro MCP

50+ alias en familias: `rf-*`, `ruv-*`, `mem-*`, `bd-*`, `wt-*`, `gnx-*`, `aqe-*`, `os-*`, `hooks-*`, `neural-*`, `turbo-status`, `turbo-help`

---

## Plugins (6)

| Plugin | Herramientas MCP | Propósito |
|:-------|:-----------------|:----------|
| **Agentic QE** | 16 | 58 agentes QE, TDD, cobertura, seguridad, ingeniería del caos |
| **Code Intelligence** | — | Análisis de código, patrones, refactorización |
| **Test Intelligence** | — | Generación de pruebas, brechas, pruebas inestables |
| **Perf Optimizer** | — | Perfilado, cuellos de botella, optimización |
| **Teammate Plugin** | 21 | Puente Equipos de Agentes ↔ enjambres Ruflo, ruteo semántico |
| **Gastown Bridge** | 20 | Orquestación WASM, sincronización Beads, convoyes |

### Plugins Eliminados (9)

| Plugin | Razón |
|:-------|:------|
| healthcare-clinical | Específico de dominio (HIPAA/FHIR) — no necesario |
| financial-risk | Específico de dominio (PCI-DSS/SOX) — no necesario |
| legal-contracts | Específico de dominio — no necesario |
| cognitive-kernel | Redundante con el sistema neural de Ruflo |
| hyperbolic-reasoning | Redundante con embeddings hiperbólicos de RuVector WASM |
| quantum-optimizer | Redundante con EWC++ y RVFOptimizer de Ruflo |
| neural-coordination | Redundante con la coordinación de enjambres de Ruflo |
| prime-radiant | Nicho — interpretabilidad matemática |
| ruvector-upstream | Redundante — RuVector incluido en Ruflo v3.5 |

---

## Comandos Clave

<details>
<summary><b>Estado y Ayuda</b></summary>

```bash
turbo-status         # Verificar todos los componentes
turbo-help           # Referencia completa de comandos
rf-doctor            # Chequeo de salud de Ruflo
rf-plugins           # Listar plugins instalados
```
</details>

<details>
<summary><b>Orquestación (Ruflo)</b></summary>

```bash
rf-wizard            # Configuración interactiva
rf-swarm             # Enjambre jerárquico (máx 8 agentes)
rf-mesh              # Enjambre en malla
rf-ring              # Enjambre en anillo
rf-star              # Enjambre en estrella
rf-spawn coder       # Generar un agente programador
rf-daemon            # Iniciar trabajadores en segundo plano
rf-status            # Estado de Ruflo
```
</details>

<details>
<summary><b>Memoria</b></summary>

```bash
bd-ready             # Verificar estado del proyecto (inicio de sesión)
bd-add               # Registrar issue/decisión/bloqueo
bd-list              # Listar beads
ruv-remember K V     # Almacenar en AgentDB
ruv-recall Q         # Consultar AgentDB
mem-search Q         # Buscar en memoria de Ruflo
mem-stats            # Estadísticas de memoria
```
</details>

<details>
<summary><b>Aislamiento</b></summary>

```bash
wt-add agente-1      # Crear worktree para agente
wt-remove agente-1   # Limpiar worktree
wt-list              # Mostrar todos los worktrees
wt-clean             # Eliminar worktrees obsoletos
```
</details>

<details>
<summary><b>Calidad y Pruebas</b></summary>

```bash
aqe-generate         # Generar pruebas (plugin Agentic QE)
aqe-gate             # Puerta de calidad
os-init              # Inicializar OpenSpec en el proyecto
os                   # Ejecutar OpenSpec
```
</details>

<details>
<summary><b>Inteligencia</b></summary>

```bash
hooks-train          # Pre-entrenamiento profundo sobre el código base
hooks-route          # Rutear tarea al agente óptimo
neural-train         # Entrenar patrones neuronales
neural-patterns      # Ver patrones aprendidos
gnx-analyze          # Indexar repositorio en grafo de conocimiento
gnx-serve            # Iniciar servidor local para UI web
gnx-wiki             # Generar wiki del repositorio desde el grafo
```
</details>

---

## Migración desde v3.x

1. Los alias antiguos `cf-*` ya no existen — usa `rf-*` en su lugar
2. Los comandos slash (`/sparc`, etc.) fueron eliminados — Ruflo auto-activa las habilidades
3. Ejecuta `bd init` en tus repositorios de proyecto para habilitar la memoria Beads
4. Ejecuta `npx gitnexus analyze` en tus repositorios para construir el grafo de conocimiento
5. El directorio `v3/` conserva todo — no se eliminó nada

| v3.4.1 | v4.0.0 |
|:-------|:-------|
| `cf-init` | `rf-init` |
| `cf-swarm` | `rf-swarm` |
| `cf-doctor` | `rf-doctor` |
| `cf-mcp` | Automático vía `rf-wizard` |
| `mem-search` | `mem-search` (sin cambios) |
| `cfb-open` | Vía herramientas MCP de navegador incluidas en Ruflo |
| Sin memoria entre sesiones | `bd-ready`, `bd-add` |
| Sin aislamiento | `wt-add`, `wt-remove` |
| Sin grafo de código base | `gnx-analyze` |

---

## Estructura del Repositorio

```
turbo-flow/
├── V2/                          ← versión actual
├── devpods/
│   ├── setup.sh                 ← script principal de configuración
│   ├── post-setup.sh            ← verificación post-configuración
│   └── devcontainer_files/      ← archivos de contexto del devcontainer
├── CLAUDE.md                    ← contexto del espacio de trabajo (activo)
└── README.md
```

---

## Post-Configuración

```bash
# 1. Recargar shell
source ~/.bashrc

# 2. Verificar instalación
turbo-status

# 3. Obtener ayuda
turbo-help

# 4. Ejecutar verificación post-configuración (13 chequeos)
# ./devpods/post-setup.sh
```

---

## Historial de Versiones

| Versión | Fecha | Cambios |
|:--------|:------|:--------|
| **v4.0.0** | Mar 2026 | **Migración a Ruflo**: Ruflo v3.5, Beads, GitNexus, Worktrees, Equipos de Agentes, 6 plugins, UI UX Pro Max, OpenSpec |
| v3.4.1 | Feb 2025 | Correcciones: instalación de habilidades eliminada, comando de plugins, respaldo npm |
| v3.4.0 | Feb 2025 | Completo + Plugins: 36 habilidades, 15 plugins |
| v3.3.0 | Feb 2025 | Instalación completa: 41 habilidades, memoria, MCP |
| v3.0.0 | Feb 2025 | Lanzamiento inicial con Claude Flow V3 |

---

## Recursos

| Recurso | Enlace |
|:--------|:-------|
| Adventure Wave Labs | [GitHub: adventurewave-labs](https://github.com/adventurewave-labs) |
| Turbo Flow | [GitHub: marcuspat/turbo-flow](https://github.com/marcuspat/turbo-flow) |
| Ruflo | [GitHub: ruvnet/ruflo](https://github.com/ruvnet/ruflo) |
| OpenSpec | [npm: @fission-ai/openspec](https://npmjs.com/package/@fission-ai/openspec) |
| Agentic QE | [npm: agentic-qe](https://npmjs.com/package/agentic-qe) |

---

## Licencia

MIT — Copyright (c) 2025-2026 Adventure Wave Labs

---

<div align="center">

**Construido y Presentado por Adventure Wave Labs**

*Turbo Flow v4.0 — Ruflo v3.5. 215+ herramientas MCP. 6 plugins. Beads. GitNexus. Worktrees. Un solo comando.*

</div>
