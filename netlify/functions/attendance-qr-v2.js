import { randomBytes } from 'crypto'
import { createClient } from '@supabase/supabase-js'

const headers = {
  'Access-Control-Allow-Credentials': 'true',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Content-Type': 'application/json',
}

const publicActions = new Set(['resolve', 'record'])
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

function publicLink(token) {
  const siteUrl = cleanText(process.env.SITE_URL) || 'https://mundo-mega-pos-legacy.netlify.app'
  return `${siteUrl.replace(/\/$/, '')}/asistencia/qr/${encodeURIComponent(token)}`
}

function safeError(message = 'No fue posible procesar la asistencia.') {
  return json(400, { error: message })
}

async function currentAdmin(client, bearerToken) {
  const { data: userData, error: userError } = await client.auth.getUser(bearerToken)
  if (userError || !userData?.user) return null
  const { data: profile, error: profileError } = await client
    .from('profiles')
    .select('id,business_id,role,active')
    .eq('id', userData.user.id)
    .maybeSingle()
  if (profileError || !profile?.active || !['admin', 'supervisor'].includes(profile.role)) return null
  return profile
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
    if (action === 'resolve') {
      const token = cleanText(body.token)
      if (token.length < 24) return safeError('QR no valido.')
      const { data, error } = await client.rpc('attendance_qr_v2_resolve', { p_token: token })
      if (error) return safeError('QR no valido o inactivo.')
      return json(200, data)
    }

    if (action === 'record') {
      const token = cleanText(body.token)
      const eventType = cleanText(body.eventType)
      if (token.length < 24) return safeError('QR no valido.')
      if (!attendanceActions.has(eventType)) return safeError('Accion no permitida.')
      const { data, error } = await client.rpc('attendance_qr_v2_record', { p_token: token, p_action: eventType })
      if (error) return safeError(error.message || 'No fue posible registrar la asistencia.')
      return json(200, data)
    }

    if (!bearerToken) return json(401, { error: 'Sesion no encontrada.' })
    const actor = await currentAdmin(client, bearerToken)
    if (!actor) return json(403, { error: 'No autorizado.' })

    if (action === 'create-token') {
      const personId = cleanText(body.personId)
      if (!personId) return safeError('Persona no encontrada.')
      const { data: person, error: personError } = await client
        .from('attendance_people_v2')
        .select('id,business_id,active')
        .eq('id', personId)
        .eq('business_id', actor.business_id)
        .maybeSingle()
      if (personError || !person?.active) return safeError('Persona no encontrada o inactiva.')

      const token = randomToken()
      const { data, error } = await client.rpc('attendance_qr_v2_create_token', { p_person_id: personId, p_token: token })
      if (error) return safeError('No fue posible generar el QR.')
      const row = Array.isArray(data) ? data[0] : data
      const link = publicLink(token)
      return json(200, { ok: true, tokenId: row?.token_id || null, token, link, publicUrl: link })
    }

    if (action === 'revoke-token') {
      const tokenId = cleanText(body.tokenId)
      if (!tokenId) return safeError('QR no encontrado.')
      const { data: qrRow, error: qrError } = await client
        .from('attendance_qr_tokens_v2')
        .select('id,business_id')
        .eq('id', tokenId)
        .eq('business_id', actor.business_id)
        .maybeSingle()
      if (qrError || !qrRow) return safeError('QR no encontrado.')
      const { error } = await client.rpc('attendance_qr_v2_revoke_token', { p_token_id: tokenId })
      if (error) return safeError('No fue posible revocar el QR.')
      return json(200, { ok: true })
    }

    return json(400, { error: 'Accion no permitida.' })
  } catch {
    return safeError()
  }
}
