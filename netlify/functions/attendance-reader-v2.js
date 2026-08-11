import { randomBytes } from 'crypto'
import { createClient } from '@supabase/supabase-js'

const headers = {
  'Access-Control-Allow-Credentials': 'true',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Content-Type': 'application/json',
}

const publicActions = new Set(['resolve-reader', 'validate-employee', 'record'])
const adminActions = new Set(['create-token', 'revoke-token'])
const attendanceActions = new Set(['check_in', 'lunch_out', 'lunch_in', 'check_out', 'half_day_out', 'continuous_day_out'])

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

function randomToken() {
  return randomBytes(32).toString('base64url')
}

function publicReaderLink(token) {
  const siteUrl = cleanText(process.env.SITE_URL) || 'https://mundo-mega-pos-legacy.netlify.app'
  return `${siteUrl.replace(/\/$/, '')}/asistencia/lector/${encodeURIComponent(token)}`
}

function safeError(message = 'No fue posible procesar el lector QR.') {
  return json(400, { error: message })
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
  const client = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: bearerToken ? { headers: { Authorization: `Bearer ${bearerToken}` } } : undefined,
  })

  try {
    if (action === 'resolve-reader') {
      const readerToken = cleanText(body.readerToken)
      if (readerToken.length < 24) return safeError('Lector no valido.')
      const { data, error } = await client.rpc('attendance_reader_v2_resolve', { p_reader_token: readerToken })
      if (error) return safeError('Lector no valido o inactivo.')
      return json(200, data)
    }

    if (action === 'validate-employee') {
      const readerToken = cleanText(body.readerToken)
      const employeeToken = cleanText(body.employeeToken)
      if (readerToken.length < 24) return safeError('Lector no valido.')
      if (employeeToken.length < 24) return safeError('QR de empleado no valido.')
      const { data, error } = await client.rpc('attendance_reader_v2_validate_employee_token', {
        p_reader_token: readerToken,
        p_employee_token: employeeToken,
      })
      if (error) return safeError(error.message || 'No fue posible validar el QR.')
      return json(200, data)
    }

    if (action === 'record') {
      const readerToken = cleanText(body.readerToken)
      const employeeToken = cleanText(body.employeeToken)
      const eventType = cleanText(body.eventType)
      if (readerToken.length < 24) return safeError('Lector no valido.')
      if (employeeToken.length < 24) return safeError('QR de empleado no valido.')
      if (!attendanceActions.has(eventType)) return safeError('Accion no permitida.')
      const { data, error } = await client.rpc('attendance_reader_v2_record', {
        p_reader_token: readerToken,
        p_employee_token: employeeToken,
        p_action: eventType,
      })
      if (error) return safeError(error.message || 'No fue posible registrar la asistencia.')
      return json(200, data)
    }

    if (!bearerToken) return json(401, { error: 'Sesion no encontrada.' })

    if (action === 'create-token') {
      const businessId = cleanText(body.businessId)
      if (!businessId) return safeError('Empresa no encontrada.')
      const readerToken = randomToken()
      const { data, error } = await client.rpc('attendance_reader_v2_create_token', {
        p_business_id: businessId,
        p_token: readerToken,
      })
      if (error) return safeError('No fue posible generar el lector.')
      const row = Array.isArray(data) ? data[0] : data
      const link = publicReaderLink(readerToken)
      return json(200, {
        ok: true,
        readerId: row?.reader_id || null,
        businessId: row?.business_id || businessId,
        active: row?.active ?? true,
        createdAt: row?.created_at || null,
        readerToken,
        token: readerToken,
        link,
        publicUrl: link,
      })
    }

    if (action === 'revoke-token') {
      const readerTokenId = cleanText(body.readerTokenId)
      if (!readerTokenId) return safeError('Lector no encontrado.')
      const { error } = await client.rpc('attendance_reader_v2_revoke_token', { p_reader_token_id: readerTokenId })
      if (error) return safeError('No fue posible revocar el lector.')
      return json(200, { ok: true })
    }

    return json(400, { error: 'Accion no permitida.' })
  } catch {
    return safeError()
  }
}
