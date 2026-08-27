import { createClient } from '@supabase/supabase-js'
import { randomBytes } from 'node:crypto'

const headers = {
  'Access-Control-Allow-Credentials': 'true',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Content-Type': 'application/json',
}

const publicActions = new Set(['validate-employee', 'record-movement'])
const adminActions = new Set(['list-movements', 'create-movement', 'update-movement', 'initialize-defaults', 'create-reader-v3', 'report'])

function json(statusCode, body) {
  return { statusCode, headers, body: JSON.stringify(body) }
}

function parseBody(event) {
  if (!event.body) return {}
  try {
    return JSON.parse(event.body)
  } catch {
    return null
  }
}

function cleanText(value) {
  return String(value || '').trim()
}

function cleanNumber(value, fallback = 100) {
  const next = Number(value)
  return Number.isFinite(next) ? next : fallback
}

function safeError(message = 'No fue posible procesar Asistencia V3.') {
  return json(400, { error: message })
}

function safeRpcMessage(error, fallback = 'No fue posible completar la operacion.') {
  const message = cleanText(error?.message)
  if (!message) return fallback
  if (/service[_\s-]?role|supabase_service_role_key|database_password|jwt_secret|token_hash|stack|password|secret|bearer/i.test(message)) {
    return fallback
  }
  return message.slice(0, 220)
}

function requireToken(value, label) {
  const token = cleanText(value)
  if (token.length < 24) throw new Error(`${label} no valido.`)
  return token
}

function randomToken() {
  return randomBytes(32).toString('base64url')
}

function readerV3Link(token) {
  const siteUrl = cleanText(process.env.SITE_URL) || 'https://mundo-mega-pos-legacy.netlify.app'
  return `${siteUrl.replace(/\/$/, '')}/asistencia/v3/lector/${encodeURIComponent(token)}`
}

export const handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers, body: '' }
  if (event.httpMethod !== 'POST') return json(405, { error: 'Metodo no permitido.' })

  const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!supabaseUrl || !serviceKey) return json(500, { error: 'Falta configuracion privada del servidor.' })

  const body = parseBody(event)
  if (!body) return json(400, { error: 'Solicitud invalida.' })

  const action = cleanText(body.action)
  if (!publicActions.has(action) && !adminActions.has(action)) return json(400, { error: 'Accion no permitida.' })

  const bearerToken = String(event.headers.authorization || event.headers.Authorization || '').replace(/^Bearer\s+/i, '')
  if (adminActions.has(action) && !bearerToken) return json(401, { error: 'Sesion no encontrada.' })

  const client = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: bearerToken ? { headers: { Authorization: `Bearer ${bearerToken}` } } : undefined,
  })

  try {
    if (adminActions.has(action)) {
      const { data: authData, error: authError } = await client.auth.getUser(bearerToken)
      if (authError || !authData?.user) return json(401, { error: 'Sesion invalida.' })
    }

    if (action === 'initialize-defaults') {
      const { data, error } = await client.rpc('attendance_v3_admin_initialize_defaults')
      if (error) return safeError(safeRpcMessage(error, 'No fue posible inicializar movimientos V3.'))
      return json(200, { ok: true, movements: data || [] })
    }

    if (action === 'list-movements') {
      const { data, error } = await client.rpc('attendance_v3_admin_list_movements')
      if (error) return safeError(safeRpcMessage(error, 'No fue posible cargar movimientos V3.'))
      return json(200, { ok: true, movements: data || [] })
    }

    if (action === 'create-movement') {
      const { data, error } = await client.rpc('attendance_v3_admin_create_movement', {
        p_name: cleanText(body.name),
        p_category: cleanText(body.category) || null,
        p_description: cleanText(body.description) || null,
        p_sort_order: cleanNumber(body.sortOrder, 100),
        p_color: cleanText(body.color) || null,
        p_icon: cleanText(body.icon) || null,
        p_requires_note: Boolean(body.requiresNote),
      })
      if (error) return safeError(safeRpcMessage(error, 'No fue posible crear el movimiento V3.'))
      return json(200, { ok: true, movementId: data })
    }

    if (action === 'update-movement') {
      const movementId = cleanText(body.movementId)
      if (!movementId) return safeError('Movimiento no encontrado.')
      const { error } = await client.rpc('attendance_v3_admin_update_movement', {
        p_movement_id: movementId,
        p_name: cleanText(body.name),
        p_category: cleanText(body.category) || null,
        p_description: cleanText(body.description) || null,
        p_active: body.active !== false,
        p_sort_order: cleanNumber(body.sortOrder, 100),
        p_color: cleanText(body.color) || null,
        p_icon: cleanText(body.icon) || null,
        p_requires_note: Boolean(body.requiresNote),
      })
      if (error) return safeError(safeRpcMessage(error, 'No fue posible actualizar el movimiento V3.'))
      return json(200, { ok: true })
    }

    if (action === 'create-reader-v3') {
      const businessId = cleanText(body.businessId)
      if (!businessId) return safeError('Empresa no encontrada.')

      const readerToken = randomToken()
      const { data, error } = await client.rpc('attendance_v3_create_reader_token', {
        p_business_id: businessId,
        p_token: readerToken,
      })
      if (error) return safeError(safeRpcMessage(error, 'No fue posible generar lector V3.'))

      const row = Array.isArray(data) ? data[0] : data
      const link = readerV3Link(readerToken)
      return json(200, {
        ok: true,
        readerId: row?.reader_id || null,
        businessId: row?.business_id || businessId,
        active: row?.active !== false,
        createdAt: row?.created_at || null,
        readerToken,
        token: readerToken,
        link,
        publicUrl: link,
      })
    }

    if (action === 'validate-employee') {
      const readerToken = requireToken(body.readerToken, 'Lector')
      const employeeToken = requireToken(body.employeeToken, 'QR de empleado')
      const { data, error } = await client.rpc('attendance_v3_validate_employee', {
        p_reader_token: readerToken,
        p_employee_token: employeeToken,
      })
      if (error) return safeError(safeRpcMessage(error, 'No fue posible validar el empleado.'))
      return json(200, data)
    }

    if (action === 'record-movement') {
      const readerToken = requireToken(body.readerToken, 'Lector')
      const employeeToken = requireToken(body.employeeToken, 'QR de empleado')
      const movementId = cleanText(body.movementId)
      if (!movementId) return safeError('Movimiento no encontrado.')
      const { data, error } = await client.rpc('attendance_v3_record_movement', {
        p_reader_token: readerToken,
        p_employee_token: employeeToken,
        p_movement_id: movementId,
        p_note: cleanText(body.note) || null,
      })
      if (error) return safeError(safeRpcMessage(error, 'No fue posible registrar el movimiento.'))
      return json(200, data)
    }

    if (action === 'report') {
      const { data, error } = await client.rpc('attendance_v3_report', {
        p_from: cleanText(body.from),
        p_to: cleanText(body.to),
        p_branch_id: cleanText(body.branchId) || null,
      })
      if (error) return safeError(safeRpcMessage(error, 'No fue posible cargar reporte V3.'))
      return json(200, { ok: true, rows: data || [] })
    }

    return json(400, { error: 'Accion no permitida.' })
  } catch (error) {
    return safeError(safeRpcMessage(error))
  }
}
