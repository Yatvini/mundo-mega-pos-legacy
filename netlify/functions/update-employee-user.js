import { createClient } from '@supabase/supabase-js'

const headers = {
  'Access-Control-Allow-Credentials': 'true',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Content-Type': 'application/json',
}

const roles = new Set(['admin', 'supervisor', 'cashier', 'warehouse'])

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

function cleanEmail(value) {
  return cleanText(value).toLowerCase()
}

function friendlyRpcError(error) {
  const message = cleanText(error?.message)
  if (/motivo requerido/i.test(message)) return 'Motivo requerido para cambios sensibles.'
  if (/ultimo administrador/i.test(message)) return 'No puedes inactivar el ultimo administrador activo.'
  if (/inactivarte a ti mismo/i.test(message)) return 'No puedes inactivarte a ti mismo.'
  if (/quitarte.*administrador/i.test(message)) return 'No puedes quitarte tu propio acceso de administrador.'
  if (/propia sucursal/i.test(message)) return 'No puedes cambiar tu propia sucursal.'
  if (/sucursal/i.test(message)) return 'Sucursal invalida.'
  if (/rol/i.test(message)) return 'Rol invalido.'
  if (/no autorizado|autorizado/i.test(message)) return 'No autorizado.'
  if (/platform|plataforma/i.test(message)) return 'No se puede editar un administrador de plataforma desde esta pantalla.'
  if (/correo/i.test(message)) return 'Correo del empleado invalido.'
  if (/nombre|apellido/i.test(message)) return message
  return 'No fue posible actualizar el usuario.'
}

export const handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers, body: '' }
  if (event.httpMethod !== 'POST') return json(405, { error: 'Metodo no permitido.' })

  const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!supabaseUrl || !serviceKey) return json(500, { error: 'Falta configuracion privada del servidor.' })

  const token = String(event.headers.authorization || event.headers.Authorization || '').replace(/^Bearer\s+/i, '')
  if (!token) return json(401, { error: 'Sesion no encontrada.' })

  const body = parseBody(event)
  if (!body) return json(400, { error: 'Solicitud invalida.' })

  const userId = cleanText(body.userId || body.id)
  const role = cleanText(body.role)
  const active = body.active

  if (!userId) return json(400, { error: 'Usuario no encontrado.' })
  if (!roles.has(role)) return json(400, { error: 'Rol invalido.' })
  if (typeof active !== 'boolean') return json(400, { error: 'Estado invalido.' })

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  })

  const { data: userData, error: userError } = await admin.auth.getUser(token)
  if (userError || !userData?.user) return json(401, { error: 'Sesion invalida.' })

  const { data, error } = await admin.rpc('update_employee_user_v2', {
    p_target_user_id: userId,
    p_full_name: cleanText(body.fullName) || null,
    p_first_name: cleanText(body.firstName) || null,
    p_last_name: cleanText(body.lastName) || null,
    p_employee_email: cleanEmail(body.employeeEmail) || null,
    p_phone: cleanText(body.phone) || null,
    p_avatar_url: cleanText(body.avatarUrl) || null,
    p_role: role,
    p_branch_id: cleanText(body.branchId) || null,
    p_active: active,
    p_force_password_change: Boolean(body.forcePasswordChange),
    p_permission_template: cleanText(body.permissionTemplate) || null,
    p_reason: cleanText(body.reason) || null,
  })

  if (error) return json(400, { error: friendlyRpcError(error) })

  const row = Array.isArray(data) ? data[0] : data
  if (!row) return json(200, { ok: true, changed_fields: [] })

  return json(200, {
    ok: true,
    user_id: row.user_id,
    full_name: row.full_name,
    role: row.role,
    branch_id: row.branch_id,
    active: row.active,
    has_employee_account: row.has_employee_account,
    changed_fields: row.changed_fields || [],
  })
}
