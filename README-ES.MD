> **⚡ TURBO FLOW — LA CAPA DE REGLAS PARA CÓDIGO ESCRITO POR IA.**
> Un solo producto vive aquí: [`rig-lite/`](rig-lite/) — un kit de gobernanza portátil. No empaqueta ningún harness, no instala nada, solo depende de bash. Suéltalo en cualquier repo y tus agentes obtienen leyes con dientes.

![v5](https://img.shields.io/badge/versión-5.2.0-blue?style=flat-square) ![gate](https://img.shields.io/badge/gate-fail--closed-4a9d63?style=flat-square) ![tests](https://img.shields.io/badge/self--tests-ALL__PASS-e0a63c?style=flat-square) ![estudio](https://img.shields.io/badge/revisión_entre_familias-71.6%25→89.7%25-c25550?style=flat-square)

## Trae tu propio harness

Turbo Flow no empaqueta ningún agente ni orquestador. Nombra los harnesses por **rol** y funciona con cualquier herramienta que lea `AGENTS.md` y pueda ejecutar bash:

| Rol | Quién | Cómo lo usa el kit |
|---|---|---|
| **Constructor** | ZCode (GLM), Claude Code, Codex, Gemini, Grok | `gate.sh --builder <cli>` conoce la familia; cualquiera puede construir |
| **Revisor** | Claude Code o Codex CLI — nunca la familia del constructor | el gate lo detecta solo y rechaza la revisión de la misma familia |
| **Orquestación** (opcional) | Ruflo, como mod de Claude Code | tráelo si quieres swarms — al kit le da igual |

**ZCode construye · Claude Code revisa (con el mod de Ruflo instalado cuando quieres orquestación) · Codex respalda la revisión.** Ese ciclo corre en producción en este repo hoy: cada PR desde que llegó rig-lite (v5.0) fue construido por una familia, revisado por otra y fusionado por un humano.

## 🎬 El demo — grabado en un Codespace limpio, nada preinstalado

![demo rig-lite](demo/rig-lite-demo.gif)

Un Codespace limpio arranca el devcontainer de este repo y el kit se prueba a sí mismo: suite de auto-tests fail-closed y una corrida del gate en vivo (CLI del revisor stubbeado; sin API keys en la máquina de grabación). La grabación es anterior al lean pivot (muestra el contenedor previo del repo); el contenedor actual corre el self-test directamente en su `postCreate`, y el grabador ahora recorre ese flujo. Reproducible con [`demo/record-rig-lite-demo.sh`](demo/record-rig-lite-demo.sh).

## El gate sobrevivió 17 rondas de revisión

`rig-lite/gate.sh` fue revisado por una familia de modelos que no lo escribió — y recibió **REVISE diecisiete veces** antes de ganar su APPROVED (contado desde el propio log JSONL del gate). Los hallazgos son exactamente la clase que el gate existe para atrapar: un agujero de inyección de prompt que dejaba que un diff se aprobara solo, una ruta fail-open que saltaba la revisión, un bug de quoting que enterraba tests fallidos, un silent-reviewer mal diagnosticado. Cada fix se volvió un self-test.

## rig-lite — un kit, diez minutos, cero dependencias nuevas

| archivo | qué te da |
|---|---|
| [`gate.sh`](rig-lite/gate.sh) | gate de revisión entre modelos — checks deterministas primero (son gratis), luego un revisor de **otra familia** debe devolver `APPROVED` / `REVISE` parseable. Fail-closed; nunca fusiona. `--pr <n>` gatea un PR de GitHub y publica el veredicto como comentario. |
| [`wt.sh`](rig-lite/wt.sh) | un worktree aislado por escritor en paralelo. |
| [`init-repo.sh`](rig-lite/init-repo.sh) | onboarding de un comando para cualquier repo: un `AGENTS.md` delgado + el symlink `CLAUDE.md → AGENTS.md`. Nunca pisa archivos existentes. |
| [`specs/`](rig-lite/specs/) | plantillas de spec + contrato UAT: plan antes de construir, verificar contra la app desplegada. |
| [`digest.sh`](rig-lite/digest.sh) | salud de tu flota de repos en un comando: cola de merges unida a veredictos del gate, working copies sucios, liveness de sitios, codespaces viejos. |
| [`automations/`](rig-lite/automations/README.md) | el tier de fondo como pack portable de prompts: 9 tareas programadas + dos formas de agendarlas. |
| [`secret.sh`](rig-lite/secret.sh) | secretos cifrados en reposo, backend autodetectado (Keychain → libsecret → age → texto plano con advertencia). `list` muestra nombres, nunca valores. |
| [`memory.md`](rig-lite/memory.md) + [`memory/`](rig-lite/memory/) | el patrón de memoria versionado en git: índice, decisiones, gotchas, inbox. |
| [`tokens.py`](rig-lite/tokens.py) | dashboard en vivo de consumo de tokens entre **zcode + claude + codex + gate** — lee los datos locales de cada CLI en solo-lectura; `--watch`, `--json`, self-test de 32 casos fijando la zona horaria. El primer drop open-core desde Turbo Rig. En macOS la corrida por defecto además lee el token OAuth de Claude del Keychain y consulta el endpoint de uso de Anthropic — `--no-quota` salta ambos. |
| [`hooks/pre-commit`](rig-lite/hooks/pre-commit) | guardián de borrados: las eliminaciones staged se anuncian en voz alta. |
| [`constitution.md`](rig-lite/constitution.md) | las leyes — constructor ≠ revisor, los agentes nunca fusionan, secretos cifrados, estado en disco. |
| [`self-test.sh`](rig-lite/self-test.sh) | la suite fail-closed del kit; avisa cuando el coverage de shellcheck se omite. |

## Instalación en diez minutos

```bash
# desde cualquier repo que quieras gobernar:
bash /ruta/a/turbo-flow/rig-lite/init-repo.sh   # escribe AGENTS.md + symlink, nunca pisa
bash /ruta/a/turbo-flow/rig-lite/self-test.sh   # demuestra el kit en tu máquina
/ruta/a/turbo-flow/rig-lite/gate.sh --pr 1 --builder <tu-cli>
```

Sin Codespace no pasa nada — es bash. ¿Quieres el tour de 30 segundos en contenedor? Abre este repo en un Codespace; el `postCreate` corre el self-test.

## A dónde se fue el entorno v4

Turbo Flow v4 empaquetaba y cableaba un entorno Claude Code + Ruflo. Ruflo creció su propio onboarding (`npx ruflo@latest init wizard`, marketplace de plugins, memoria y consola integradas), lo que jubiló la razón de ser de un repo envoltorio. La cadena de instalación v4 vive en los tags `v1.0.1 → v4.0`; la línea v5 es gobernanza-primero y agnóstica de orquestación.

## Únete a la beta privada

El kit es el extracto portable de **Turbo Rig** — gate + constitución + memoria + automatizaciones corriendo como un sistema integrado, en tu máquina, a través de tus repos.

- **Aplicar / página del producto** → [turbo-rig.vercel.app](https://turbo-rig.vercel.app) (EN/ES)
- **Deep dive** → [turbo-rig-deep-dive.vercel.app](https://turbo-rig-deep-dive.vercel.app) · **Escena 3D** → [turbo-rig-deep-dive-3d.vercel.app](https://turbo-rig-deep-dive-3d.vercel.app)

**Feedback de la beta:** abre un issue o una discusión aquí — este repo es el tracker público de la beta.

## ¿Importa realmente que constructor ≠ revisor?

En un estudio controlado de 116 tareas, la revisión entre familias subió los pass rates de **71.6% → 89.7%**, mientras que la auto-revisión de la misma familia apenas se movió. Una semana reciente construyendo Turbo Rig con Turbo Rig: **141 PRs · 868 corridas del gate · 104 lanes en paralelo** — cada merge sostenido por un humano.

## Sobre Adventure Wave Labs

**Adventure Wave Labs** construye Turbo Flow y Turbo Rig — packaging, automatización de setup, y la capa de gobernanza que aguanta cuando los agentes aceleran. El núcleo de orquestación referenciado por v4 fue [Ruflo](https://github.com/ruvnet/ruflo) de rUv; Turbo Flow lo integra — y ahora lo señala — en lugar de reconstruirlo.

<div align="center">

**Turbo Flow v5.2 — la capa de reglas. Un kit, cualquier harness, los humanos fusionan.**

</div>

## Licencia

MIT — Copyright (c) 2025-2026 Adventure Wave Labs
