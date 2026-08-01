import { createClient } from '@supabase/supabase-js'

const headers = {
  'Access-Control-Allow-Credentials': 'true',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Content-Type': 'application/json',
}

const roles = new Set(['admin', 'supervisor', 'cashier', 'warehouse'])
const usernamePattern = /^[a-z0-9._-]{3,32}$/
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

function cleanUsername(value) {
  return cleanText(value).toLowerCase()
}

function cleanEmail(value) {
  return cleanText(value).toLowerCase()
}

function safeError(message = 'No fue posible crear el empleado.') {
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

  const username = cleanUsername(body.username)
  const employeeEmail = cleanEmail(body.employeeEmail)
  const firstName = cleanText(body.firstName)
  const lastName = cleanText(body.lastName)
  const phone = cleanText(body.phone)
  const avatarUrl = cleanText(body.avatarUrl)
  const branchId = cleanText(body.branchId)
  const role = cleanText(body.role)
  const password = String(body.password || '')
  const active = body.active !== false
  const forcePasswordChange = Boolean(body.forcePasswordChange)
  const darkMode = Boolean(body.darkMode)
  const permissionTemplate = cleanText(body.permissionTemplate)
  const permissions = body.permissions && typeof body.permissions === 'object' ? body.permissions : {}

  if (!usernamePattern.test(username)) return safeError('El usuario debe tener 3 a 32 caracteres: minusculas, numeros, punto, guion o guion bajo.')
  if (!emailPattern.test(employeeEmail)) return safeError('Correo del empleado invalido.')
  if (!firstName) return safeError('El nombre es obligatorio.')
  if (!lastName) return safeError('El apellido es obligatorio.')
  if (password.length < 8) return safeError('La contrasena debe tener al menos 8 caracteres.')
  if (!roles.has(role)) return safeError('Rol no permitido.')

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: userData, error: userError } = await admin.auth.getUser(token)
  if (userError || !userData?.user) return json(401, { error: 'Sesion invalida.' })

  const { data: creator, error: creatorError } = await admin
    .from('profiles')
    .select('id,business_id,branch_id,role,active')
    .eq('id', userData.user.id)
    .maybeSingle()

  if (creatorError || !creator?.active || creator.role !== 'admin') {
    return json(403, { error: 'Solo un administrador activo puede crear empleados.' })
  }

  let targetBranchId = branchId || creator.branch_id
  if (targetBranchId) {
    const { data: branch, error: branchError } = await admin
      .from('branches')
      .select('id')
      .eq('id', targetBranchId)
      .eq('business_id', creator.business_id)
      .eq('active', true)
      .maybeSingle()

    if (branchError || !branch) return safeError('La sucursal asignada no pertenece a la empresa.')
    targetBranchId = branch.id
  }

  const { data: existingUsername, error: usernameError } = await admin
    .from('employee_accounts')
    .select('user_id')
    .eq('username', username)
    .maybeSingle()

  if (usernameError) return safeError()
  if (existingUsername) return safeError('Ese usuario ya existe.')

  const authEmail = `${username}@employee.mundo-mega.internal`
  const { data: existingAuthEmail, error: authEmailError } = await admin
    .from('employee_accounts')
    .select('user_id')
    .eq('auth_email', authEmail)
    .maybeSingle()

  if (authEmailError) return safeError()
  if (existingAuthEmail) return safeError('Ese usuario ya existe.')

  const provision = {
    auth_email: authEmail,
    business_id: creator.business_id,
    branch_id: targetBranchId || null,
    username,
    first_name: firstName,
    last_name: lastName,
    role,
    active,
    created_by: creator.id,
  }

  const { error: provisionError } = await admin.from('employee_account_provisioning').insert(provision)
  if (provisionError) return safeError('No fue posible preparar el empleado.')

  let createdUserId = ''
  try {
    const { data: authUser, error: authError } = await admin.auth.admin.createUser({
      email: authEmail,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: `${firstName} ${lastName}`.trim(),
        username,
        employee_login: true,
      },
    })

    if (authError || !authUser?.user?.id) throw authError || new Error('Auth user not created')
    createdUserId = authUser.user.id

    const { error: accountError } = await admin.from('employee_accounts').insert({
      user_id: createdUserId,
      business_id: creator.business_id,
      username,
      auth_email: authEmail,
      employee_email: employeeEmail,
      first_name: firstName,
      last_name: lastName,
      phone: phone || null,
      avatar_url: avatarUrl || null,
      force_password_change: forcePasswordChange,
      dark_mode: darkMode,
      permission_template: permissionTemplate || null,
      permissions,
      created_by: creator.id,
    })

    if (accountError) throw accountError

    return json(200, {
      ok: true,
      user_id: createdUserId,
      username,
      full_name: `${firstName} ${lastName}`.trim(),
      role,
      active,
    })
  } catch {
    if (createdUserId) await admin.auth.admin.deleteUser(createdUserId).catch(() => null)
    try {
      await admin.from('employee_account_provisioning').delete().eq('auth_email', authEmail)
    } catch {
      // No exponemos detalles internos del rollback al cliente.
    }
    return safeError()
  }
}
