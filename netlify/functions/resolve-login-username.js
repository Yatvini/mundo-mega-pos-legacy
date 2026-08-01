import { createClient } from '@supabase/supabase-js'

const headers = {
  'Access-Control-Allow-Credentials': 'true',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type',
  'Content-Type': 'application/json',
}

const usernamePattern = /^[a-z0-9._-]{3,32}$/

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

function cleanUsername(value) {
  return String(value || '').trim().toLowerCase()
}

export const handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers, body: '' }
  if (event.httpMethod !== 'POST') return json(405, { error: 'Metodo no permitido.' })

  const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!supabaseUrl || !serviceKey) return json(500, { error: 'Falta configuracion privada del servidor.' })

  const body = parseBody(event)
  if (!body) return json(400, { error: 'Solicitud invalida.' })

  const username = cleanUsername(body.username)
  if (!usernamePattern.test(username)) return json(400, { error: 'Usuario o contrasena incorrectos.' })

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: account, error: accountError } = await admin
    .from('employee_accounts')
    .select('username,auth_email,user_id,business_id')
    .eq('username', username)
    .maybeSingle()

  if (accountError || !account?.auth_email || !account?.user_id || !account?.business_id) {
    return json(400, { error: 'Usuario o contrasena incorrectos.' })
  }

  const { data: profile, error: profileError } = await admin
    .from('profiles')
    .select('id,business_id,active')
    .eq('id', account.user_id)
    .maybeSingle()

  if (
    profileError ||
    !profile ||
    !profile.active ||
    profile.business_id !== account.business_id
  ) {
    return json(400, { error: 'Usuario o contrasena incorrectos.' })
  }

  const { data: business, error: businessError } = await admin
    .from('businesses')
    .select('id,status')
    .eq('id', account.business_id)
    .maybeSingle()

  if (businessError || !business || business.status !== 'active') {
    return json(400, { error: 'Usuario o contrasena incorrectos.' })
  }

  return json(200, { ok: true, auth_email: account.auth_email })
}
