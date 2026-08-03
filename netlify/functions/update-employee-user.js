import { createClient } from '@supabase/supabase-js'

const headers = {
  'Access-Control-Allow-Credentials': 'true',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Content-Type': 'application/json',
}

const roles = new Set(['admin', 'supervisor', 'cashier', 'warehouse'])
const emailPattern = /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i

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

function safeError(message = 'No fue posible actualizar el usuario.') {
  return json(400, { error: message })
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
  const branchId = cleanText(body.branchId)
  const active = body.active
  const fullName = cleanText(body.fullName)
  const firstName = cleanText(body.firstName)
  const lastName = cleanText(body.lastName)
  const employeeEmail = cleanEmail(body.employeeEmail)
  const phone = cleanText(body.phone)
  const avatarUrl = cleanText(body.avatarUrl)
  const forcePasswordChange = Boolean(body.forcePasswordChange)
  const permissionTemplate = cleanText(body.permissionTemplate)

  if (!userId) return safeError('Usuario no encontrado.')
  if (!roles.has(role)) return safeError('Rol no permitido.')
  if (typeof active !== 'boolean') return safeError('Estado invalido.')

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: userData, error: userError } = await admin.auth.getUser(token)
  if (userError || !userData?.user) return json(401, { error: 'Sesion invalida.' })

  const { data: editor, error: editorError } = await admin
    .from('profiles')
    .select('id,business_id,role,active')
    .eq('id', userData.user.id)
    .maybeSingle()

  if (editorError || !editor?.active || editor.role !== 'admin' || !editor.business_id) {
    return json(403, { error: 'Solo un administrador activo puede editar usuarios.' })
  }

  const { data: target, error: targetError } = await admin
    .from('profiles')
    .select('id,business_id,branch_id,full_name,role,active')
    .eq('id', userId)
    .maybeSingle()

  if (targetError || !target) return safeError('Usuario no encontrado.')
  if (target.business_id !== editor.business_id) return json(403, { error: 'Usuario no autorizado.' })

  const { data: platformAdmin } = await admin
    .from('platform_admins')
    .select('user_id')
    .eq('user_id', userId)
    .eq('active', true)
    .maybeSingle()

  if (platformAdmin) return json(403, { error: 'No se puede editar un administrador de plataforma desde esta pantalla.' })

  const targetBranchId = branchId || target.branch_id
  if (targetBranchId) {
    const { data: branch, error: branchError } = await admin
      .from('branches')
      .select('id')
      .eq('id', targetBranchId)
      .eq('business_id', editor.business_id)
      .eq('active', true)
      .maybeSingle()

    if (branchError || !branch) return safeError('La sucursal asignada no pertenece a la empresa.')
  }

  const { data: account, error: accountError } = await admin
    .from('employee_accounts')
    .select('user_id,business_id,username,auth_email')
    .eq('user_id', userId)
    .maybeSingle()

  if (accountError) return safeError()
  if (account && account.business_id !== editor.business_id) return json(403, { error: 'Cuenta no autorizada.' })

  const hasDirectAccount = Boolean(account)
  const nextFullName = hasDirectAccount ? `${firstName} ${lastName}`.trim() : fullName

  if (!nextFullName) return safeError('El nombre es obligatorio.')
  if (hasDirectAccount) {
    if (!firstName) return safeError('El nombre es obligatorio.')
    if (!lastName) return safeError('El apellido es obligatorio.')
    if (!emailPattern.test(employeeEmail)) return safeError('Correo del empleado invalido.')
  }

  const { error: profileUpdateError } = await admin
    .from('profiles')
    .update({
      full_name: nextFullName,
      role,
      branch_id: targetBranchId || null,
      active,
    })
    .eq('id', userId)
    .eq('business_id', editor.business_id)

  if (profileUpdateError) return safeError()

  if (hasDirectAccount) {
    const { error: accountUpdateError } = await admin
      .from('employee_accounts')
      .update({
        first_name: firstName,
        last_name: lastName,
        employee_email: employeeEmail,
        phone: phone || null,
        avatar_url: avatarUrl || null,
        force_password_change: forcePasswordChange,
        permission_template: permissionTemplate || null,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId)
      .eq('business_id', editor.business_id)

    if (accountUpdateError) return safeError()
  }

  return json(200, {
    ok: true,
    user_id: userId,
    full_name: nextFullName,
    role,
    branch_id: targetBranchId || null,
    active,
  })
}
