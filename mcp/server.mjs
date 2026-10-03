#!/usr/bin/env node
import readline from 'node:readline'
import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, '..')
const MANIFEST = join(ROOT, 'src-tauri', 'Cargo.toml')
const RELEASE_BRIDGE = join(ROOT, 'src-tauri', 'target', 'release', 'publisher_mcp_bridge')
const WEB_URL = 'https://lordjeferies.github.io/abraxas-publisher/'

const schema = (properties = {}, required = []) => ({
  type: 'object',
  additionalProperties: false,
  properties,
  ...(required.length ? { required } : {}),
})

const confirm = {
  confirm: {
    type: 'boolean',
    description: 'Debe ser true para ejecutar esta acción sensible.',
  },
}

const tools = [
  { name: 'publisher_doctor', description: 'Diagnostica SQLite, ffmpeg y ffprobe.', inputSchema: schema() },
  { name: 'publisher_list_brands', description: 'Lista las marcas del workspace.', inputSchema: schema() },
  { name: 'publisher_create_brand', description: 'Crea una marca.', inputSchema: schema({ name: { type: 'string' } }, ['name']) },
  { name: 'publisher_list_contents', description: 'Lista contenidos, assets, targets, estados y validaciones.', inputSchema: schema() },
  { name: 'publisher_get_content', description: 'Obtiene una ficha completa por contentId.', inputSchema: schema({ contentId: { type: 'string' } }, ['contentId']) },
  { name: 'publisher_refresh_content', description: 'Reescanea la fuente de un contenido y actualiza su versión si cambió.', inputSchema: schema({ contentId: { type: 'string' } }, ['contentId']) },
  { name: 'publisher_import_local', description: 'Importa una carpeta local. Requiere confirmación porque puede reemplazar duplicados.', inputSchema: schema({ path: { type: 'string' }, brand: { type: 'string' }, duplicatePolicy: { type: 'string', enum: ['replace', 'keep', 'skip'] }, ...confirm }, ['path', 'confirm']) },
  { name: 'publisher_set_status', description: 'Cambia el estado editorial de una ficha.', inputSchema: schema({ contentId: { type: 'string' }, status: { type: 'string', enum: ['EN_CONFIRMACION', 'CON_CORRECCION', 'LISTO_POR_PROGRAMAR', 'PROGRAMADO'] } }, ['contentId', 'status']) },
  { name: 'publisher_add_correction_note', description: 'Guarda nota de corrección y actualiza CORRECCION.txt.', inputSchema: schema({ contentId: { type: 'string' }, note: { type: 'string' }, status: { type: 'string' } }, ['contentId', 'note']) },
  { name: 'publisher_get_schedule', description: 'Muestra destinos y programación de un contenido.', inputSchema: schema({ contentId: { type: 'string' } }, ['contentId']) },
  { name: 'publisher_set_schedule', description: 'Asigna fecha/hora local a una plataforma.', inputSchema: schema({ contentId: { type: 'string' }, platform: { type: 'string' }, scheduledAt: { type: 'string', description: 'ISO local, por ejemplo 2026-10-08T17:00:00' } }, ['contentId', 'platform', 'scheduledAt']) },
  { name: 'publisher_clear_schedule', description: 'Quita la programación local de una plataforma.', inputSchema: schema({ contentId: { type: 'string' }, platform: { type: 'string' } }, ['contentId', 'platform']) },
  { name: 'publisher_list_activity', description: 'Lista el historial de actividad.', inputSchema: schema() },
  { name: 'publisher_undo', description: 'Deshace la última acción local reversible.', inputSchema: schema() },
  { name: 'publisher_redo', description: 'Rehace la última acción local reversible.', inputSchema: schema() },
  { name: 'publisher_dry_run', description: 'Simula el lote sin llamar APIs sociales ni publicar.', inputSchema: schema() },
  { name: 'publisher_list_accounts', description: 'Lista metadatos de cuentas sociales configuradas.', inputSchema: schema() },
  { name: 'publisher_save_account', description: 'Crea/actualiza metadatos de una cuenta. No guarda passwords ni OAuth tokens.', inputSchema: schema({ account: { type: 'object', additionalProperties: true } }, ['account']) },
  { name: 'publisher_remove_account', description: 'Elimina los metadatos locales de una cuenta. Requiere confirmación.', inputSchema: schema({ accountId: { type: 'string' }, ...confirm }, ['accountId', 'confirm']) },
  { name: 'publisher_list_jobs', description: 'Lista la cola de publicación.', inputSchema: schema() },
  { name: 'publisher_preflight', description: 'Ejecuta preflight editorial/técnico para un target.', inputSchema: schema({ targetId: { type: 'string' }, accountId: { type: 'string' } }, ['targetId']) },
  { name: 'publisher_enqueue_publications', description: 'Encola targets AUTO_API/MANUAL/EXTERNAL. No equivale a publicación remota confirmada. Requiere confirmación.', inputSchema: schema({ inputs: { type: 'array', items: { type: 'object', additionalProperties: true } }, ...confirm }, ['inputs', 'confirm']) },
  { name: 'publisher_mark_scheduled_external', description: 'Registra que un target fue programado fuera de Publisher. Requiere confirmación.', inputSchema: schema({ targetId: { type: 'string' }, method: { type: 'string' }, scheduledAt: { type: 'string' }, remoteUrl: { type: 'string' }, note: { type: 'string' }, ...confirm }, ['targetId', 'method', 'confirm']) },
  { name: 'publisher_get_drive_client_id', description: 'Lee el Google Drive OAuth Client ID configurado. No devuelve tokens.', inputSchema: schema() },
  { name: 'publisher_set_drive_client_id', description: 'Guarda el Client ID público de Google Drive. El consentimiento OAuth se realiza en la UI.', inputSchema: schema({ clientId: { type: 'string' } }, ['clientId']) },
  { name: 'publisher_open_app', description: 'Abre ABRAXAS Publisher.app en macOS.', inputSchema: schema() },
  { name: 'publisher_open_web', description: 'Abre la Web/PWA pública de Publisher.', inputSchema: schema() },
  { name: 'publisher_clear_workspace', description: 'BORRA el workspace SQLite local. Acción destructiva; requiere confirmación explícita.', inputSchema: schema(confirm, ['confirm']) },
]

const mapping = {
  publisher_doctor: ['doctor', false],
  publisher_list_brands: ['brands.list', false],
  publisher_create_brand: ['brands.create', false],
  publisher_list_contents: ['content.list', false],
  publisher_get_content: ['content.show', false],
  publisher_refresh_content: ['content.refresh', false],
  publisher_import_local: ['content.importLocal', true],
  publisher_set_status: ['status.set', false],
  publisher_add_correction_note: ['note.add', false],
  publisher_get_schedule: ['schedule.show', false],
  publisher_set_schedule: ['schedule.set', false],
  publisher_clear_schedule: ['schedule.clear', false],
  publisher_list_activity: ['activity.list', false],
  publisher_undo: ['undo', false],
  publisher_redo: ['redo', false],
  publisher_dry_run: ['dryRun', false],
  publisher_list_accounts: ['accounts.list', false],
  publisher_save_account: ['accounts.save', false],
  publisher_remove_account: ['accounts.remove', true],
  publisher_list_jobs: ['jobs.list', false],
  publisher_preflight: ['publishing.preflight', false],
  publisher_enqueue_publications: ['publishing.enqueue', true],
  publisher_mark_scheduled_external: ['publishing.markExternal', true],
  publisher_get_drive_client_id: ['drive.getClientId', false],
  publisher_set_drive_client_id: ['drive.setClientId', false],
  publisher_clear_workspace: ['workspace.clear', true],
}

function runBridge(op, args = {}) {
  const payload = JSON.stringify(args)
  const custom = process.env.ABRAXAS_PUBLISHER_MCP_BRIDGE

  let result
  if (custom) {
    result = spawnSync(custom, [op, payload], { encoding: 'utf8' })
  } else if (existsSync(RELEASE_BRIDGE)) {
    result = spawnSync(RELEASE_BRIDGE, [op, payload], { encoding: 'utf8' })
  } else {
    result = spawnSync('cargo', ['run', '--quiet', '--manifest-path', MANIFEST, '--bin', 'publisher_mcp_bridge', '--', op, payload], { encoding: 'utf8', cwd: ROOT })
  }

  if (result.error) throw result.error
  if (result.status !== 0) throw new Error((result.stderr || result.stdout || `bridge exit ${result.status}`).trim())
  const raw = (result.stdout || '').trim()
  return raw ? JSON.parse(raw) : null
}

function requireConfirmation(toolName, args, sensitive) {
  if (sensitive && args?.confirm !== true) {
    throw new Error(`${toolName} requiere confirm: true. Explica al usuario qué cambiará antes de repetir la llamada.`)
  }
}

function openTarget(target) {
  const result = spawnSync('open', [target], { encoding: 'utf8' })
  if (result.status !== 0) throw new Error((result.stderr || 'No se pudo abrir').trim())
  return { opened: target }
}

function callTool(name, args = {}) {
  if (name === 'publisher_open_app') return openTarget('/Users/' + (process.env.USER || '') + '/Applications/ABRAXAS Publisher.app')
  if (name === 'publisher_open_web') return openTarget(WEB_URL)

  const entry = mapping[name]
  if (!entry) throw new Error(`Tool desconocida: ${name}`)
  const [op, sensitive] = entry
  requireConfirmation(name, args, sensitive)
  const clean = { ...args }
  delete clean.confirm
  return runBridge(op, clean)
}

const prompts = [
  {
    name: 'publisher_morning_review',
    description: 'Revisión operativa del Publisher sin hacer cambios.',
    arguments: [],
  },
  {
    name: 'publisher_prepare_week',
    description: 'Preparar y validar una semana antes de calendarizar/publicar.',
    arguments: [{ name: 'brand', description: 'Marca a revisar', required: false }],
  },
  {
    name: 'publisher_fix_content',
    description: 'Analizar una ficha, registrar corrección y dejarla en el estado correcto.',
    arguments: [{ name: 'contentId', description: 'ID de contenido', required: true }],
  },
]

function promptMessages(name, args = {}) {
  if (name === 'publisher_morning_review') return [{ role: 'user', content: { type: 'text', text: 'Usa publisher_doctor, publisher_list_contents, publisher_list_jobs y publisher_dry_run. Resume bloqueos, correcciones pendientes, piezas listas y trabajos de publicación. No cambies nada.' } }]
  if (name === 'publisher_prepare_week') return [{ role: 'user', content: { type: 'text', text: `Revisa el workspace${args.brand ? ` de la marca ${args.brand}` : ''}. Identifica CON_CORRECCION, LISTO_POR_PROGRAMAR y targets sin fecha. Ejecuta preflight antes de proponer cualquier enqueue. No encoles nada sin confirmación explícita.` } }]
  if (name === 'publisher_fix_content') return [{ role: 'user', content: { type: 'text', text: `Abre la ficha ${args.contentId}. Revisa issues/assets/targets. Si el usuario da la corrección exacta, usa publisher_add_correction_note y deja el estado editorial coherente. Después vuelve a leer la ficha.` } }]
  throw new Error(`Prompt desconocido: ${name}`)
}

function reply(id, result) {
  process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\n')
}

function fail(id, error) {
  process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, error: { code: -32000, message: error instanceof Error ? error.message : String(error) } }) + '\n')
}

async function handle(message) {
  const { id, method, params = {} } = message
  try {
    if (method === 'initialize') return reply(id, {
      protocolVersion: params.protocolVersion || '2025-06-18',
      capabilities: { tools: {}, prompts: {} },
      serverInfo: { name: 'abraxas-publisher', version: '1.0.0' },
      instructions: 'Opera el workspace real de ABRAXAS Publisher. Lee antes de escribir. No confundas PROGRAMADO editorial con SCHEDULED_REMOTE. Las acciones sensibles exigen confirm:true.',
    })
    if (method === 'ping') return reply(id, {})
    if (method === 'tools/list') return reply(id, { tools })
    if (method === 'tools/call') {
      const value = callTool(params.name, params.arguments || {})
      return reply(id, {
        content: [{ type: 'text', text: JSON.stringify(value, null, 2) }],
        structuredContent: value && typeof value === 'object' ? value : { value },
        isError: false,
      })
    }
    if (method === 'prompts/list') return reply(id, { prompts })
    if (method === 'prompts/get') return reply(id, { description: params.name, messages: promptMessages(params.name, params.arguments || {}) })
    if (method === 'resources/list') return reply(id, { resources: [] })
    if (method?.startsWith('notifications/')) return
    if (id !== undefined) return fail(id, new Error(`Método MCP no soportado: ${method}`))
  } catch (error) {
    if (id !== undefined) fail(id, error)
  }
}

if (process.argv.includes('--self-test')) {
  try {
    const result = runBridge('doctor', {})
    console.log(JSON.stringify({ ok: true, doctor: result }, null, 2))
    process.exit(0)
  } catch (error) {
    console.error(error)
    process.exit(1)
  }
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity })
rl.on('line', (line) => {
  const text = line.trim()
  if (!text) return
  try { handle(JSON.parse(text)) } catch (error) { console.error(error) }
})
