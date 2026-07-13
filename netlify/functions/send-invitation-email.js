import { createClient } from '@supabase/supabase-js'

const headers = {
  'Access-Control-Allow-Credentials': 'true',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Content-Type': 'application/json',
}

function json(statusCode, body) {
  return { statusCode, headers, body: JSON.stringify(body) }
}

function cleanEmail(value) {
  return String(value || '').trim().toLowerCase()
}

function safeMessage(error) {
  const message = error?.message || String(error || '')
  if (message.includes('already been registered') || message.includes('already registered')) {
    return 'El correo ya existe en Supabase. Enviamos un enlace para definir o recuperar contraseña.'
  }
  if (message.includes('rate limit')) return 'Supabase limitó temporalmente el envío de correos. Intenta de nuevo en unos minutos.'
  return 'No fue posible enviar el correo de invitación.'
}

function parseBody(event) {
  if (!event.body) return {}
  try {
    return JSON.parse(event.body)
  } catch {
    return null
  }
}

function validateRedirectTo(value) {
  try {
    const url = new URL(String(value || '').trim())
    const allowedOrigins = new Set([
      'https://mundo-mega-pos-legacy.netlify.app',
      'http://localhost:5173',
      'http://127.0.0.1:5173',
      process.env.SITE_URL,
    ].filter(Boolean))

    if (!allowedOrigins.has(url.origin)) return null
    return url.toString()
  } catch {
    return null
  }
}

export const handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers, body: '' }
  if (event.httpMethod !== 'POST') return json(405, { error: 'Método no permitido.' })

  const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!supabaseUrl || !serviceKey) {
    return json(500, { error: 'Falta configurar las variables privadas del servidor en Netlify.' })
  }

  const token = String(event.headers.authorization || event.headers.Authorization || '').replace(/^Bearer\s+/i, '')
  if (!token) return json(401, { error: 'Sesión no encontrada.' })

  const body = parseBody(event)
  if (!body) return json(400, { error: 'Solicitud inválida.' })

  const kind = String(body.kind || '').trim()
  const email = cleanEmail(body.email)
  const fullName = String(body.fullName || '').trim()
  const businessId = String(body.businessId || '').trim()
  const redirectTo = validateRedirectTo(body.redirectTo)

  if (!['platform-business-admin', 'team-member'].includes(kind)) return json(400, { error: 'Tipo de invitación inválido.' })
  if (!email) return json(400, { error: 'Correo y URL de retorno son obligatorios.' })
  if (!redirectTo) return json(400, { error: 'URL de retorno no permitida.' })
  if (kind === 'platform-business-admin' && !businessId) return json(400, { error: 'Empresa obligatoria para esta invitación.' })

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: userData, error: userError } = await admin.auth.getUser(token)
  if (userError || !userData?.user) return json(401, { error: 'Sesión inválida.' })

  if (kind === 'platform-business-admin') {
    const { data: platformAdmin, error: platformError } = await admin
      .from('platform_admins')
      .select('user_id')
      .eq('user_id', userData.user.id)
      .eq('active', true)
      .maybeSingle()

    if (platformError || !platformAdmin) return json(403, { error: 'Solo el administrador general puede enviar esta invitación.' })

    const { data: invite, error: inviteError } = await admin
      .from('business_admin_invitations')
      .select('id,business_id,email,accepted_at')
      .eq('business_id', businessId)
      .eq('email', email)
      .is('accepted_at', null)
      .maybeSingle()

    if (inviteError || !invite) return json(404, { error: 'No existe una invitación pendiente para ese administrador.' })
  }

  if (kind === 'team-member') {
    const { data: profile, error: profileError } = await admin
      .from('profiles')
      .select('business_id,role,active')
      .eq('id', userData.user.id)
      .maybeSingle()

    if (profileError || !profile?.active || profile.role !== 'admin') {
      return json(403, { error: 'Solo un administrador puede invitar usuarios.' })
    }

    const { data: invite, error: inviteError } = await admin
      .from('team_invitations')
      .select('id,email,accepted_at')
      .eq('business_id', profile.business_id)
      .eq('email', email)
      .is('accepted_at', null)
      .maybeSingle()

    if (inviteError || !invite) return json(404, { error: 'No existe una invitación pendiente para ese usuario.' })
  }

  const metadata = {
    full_name: fullName || email.split('@')[0],
    invitation_kind: kind,
  }

  const inviteResult = await admin.auth.admin.inviteUserByEmail(email, {
    redirectTo,
    data: metadata,
  })

  if (!inviteResult.error) {
    return json(200, { ok: true, mode: 'invite', message: 'Correo de invitación enviado.' })
  }

  const message = inviteResult.error.message || ''
  if (message.includes('already been registered') || message.includes('already registered')) {
    const recovery = await admin.auth.resetPasswordForEmail(email, { redirectTo })
    if (recovery.error) return json(400, { error: safeMessage(recovery.error) })
    return json(200, { ok: true, mode: 'password', message: safeMessage(inviteResult.error) })
  }

  return json(400, { error: safeMessage(inviteResult.error) })
}
