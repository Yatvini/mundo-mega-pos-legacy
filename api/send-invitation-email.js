import { createClient } from '@supabase/supabase-js'

const json = (res, status, body) => res.status(status).json(body)

function cleanEmail(value) {
  return String(value || '').trim().toLowerCase()
}

function publicMessage(error) {
  const message = error?.message || String(error || '')
  if (message.includes('already been registered') || message.includes('already registered')) {
    return 'El correo ya existe en Supabase. Enviamos un enlace para definir o recuperar contrasena.'
  }
  if (message.includes('rate limit')) return 'Supabase limito temporalmente el envio de correos. Intenta de nuevo en unos minutos.'
  return message || 'No fue posible enviar el correo de invitacion.'
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Credentials', 'true')
  res.setHeader('Access-Control-Allow-Origin', req.headers.origin || '*')
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type')
  if (req.method === 'OPTIONS') return res.status(204).end()
  if (req.method !== 'POST') return json(res, 405, { error: 'Metodo no permitido' })

  const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!supabaseUrl || !serviceKey) {
    return json(res, 500, { error: 'Falta configurar SUPABASE_SERVICE_ROLE_KEY en Vercel.' })
  }

  const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '')
  if (!token) return json(res, 401, { error: 'Sesion no encontrada.' })

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: userData, error: userError } = await admin.auth.getUser(token)
  if (userError || !userData?.user) return json(res, 401, { error: 'Sesion invalida.' })

  const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {})
  const kind = body.kind
  const email = cleanEmail(body.email)
  const fullName = String(body.fullName || '').trim()
  const redirectTo = String(body.redirectTo || '').trim()

  if (!email || !redirectTo) return json(res, 400, { error: 'Correo y URL de retorno son obligatorios.' })
  if (!['platform-business-admin', 'team-member'].includes(kind)) return json(res, 400, { error: 'Tipo de invitacion invalido.' })

  if (kind === 'platform-business-admin') {
    const { data: platformAdmin } = await admin
      .from('platform_admins')
      .select('user_id')
      .eq('user_id', userData.user.id)
      .eq('active', true)
      .maybeSingle()
    if (!platformAdmin) return json(res, 403, { error: 'Solo el administrador general puede enviar esta invitacion.' })

    const { data: invite } = await admin
      .from('business_admin_invitations')
      .select('id,business_id,email,full_name,accepted_at')
      .eq('business_id', body.businessId)
      .eq('email', email)
      .is('accepted_at', null)
      .maybeSingle()
    if (!invite) return json(res, 404, { error: 'No existe una invitacion pendiente para ese administrador.' })
  }

  if (kind === 'team-member') {
    const { data: profile } = await admin
      .from('profiles')
      .select('business_id,role,active')
      .eq('id', userData.user.id)
      .maybeSingle()
    if (!profile?.active || profile.role !== 'admin') return json(res, 403, { error: 'Solo un administrador puede invitar usuarios.' })

    const { data: invite } = await admin
      .from('team_invitations')
      .select('id,email,accepted_at')
      .eq('business_id', profile.business_id)
      .eq('email', email)
      .is('accepted_at', null)
      .maybeSingle()
    if (!invite) return json(res, 404, { error: 'No existe una invitacion pendiente para ese usuario.' })
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
    return json(res, 200, { ok: true, mode: 'invite', message: 'Correo de invitacion enviado.' })
  }

  const msg = inviteResult.error.message || ''
  if (msg.includes('already been registered') || msg.includes('already registered')) {
    const recovery = await admin.auth.resetPasswordForEmail(email, { redirectTo })
    if (recovery.error) return json(res, 400, { error: publicMessage(recovery.error) })
    return json(res, 200, { ok: true, mode: 'password', message: publicMessage(inviteResult.error) })
  }

  return json(res, 400, { error: publicMessage(inviteResult.error) })
}
