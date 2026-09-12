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

function friendlyReason(value) {
  const reason = cleanText(value)
  if (!reason) return 'No fue posible eliminar el usuario.'
  if (/registros historicos|historial/i.test(reason)) {
    return 'No se puede eliminar permanentemente porque este usuario tiene registros historicos. Puede inactivarlo.'
  }
  if (/propio usuario|self_delete/i.test(reason)) return 'No puedes eliminar tu propio usuario.'
  if (/ultimo administrador|last_active_admin/i.test(reason)) return 'No se puede eliminar el ultimo administrador activo.'
  if (/platform|plataforma/i.test(reason)) return 'No se puede eliminar un administrador de plataforma desde esta pantalla.'
  return reason
}

function firstRow(data) {
  return Array.isArray(data) ? data[0] : data
}

export const handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers, body: '' }
  if (event.httpMethod !== 'POST') return json(405, { error: 'Metodo no permitido.' })

  const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!supabaseUrl || !serviceKey) return json(500, { error: 'Falta configuracion privada del servidor.' })

  const bearerToken = String(event.headers.authorization || event.headers.Authorization || '').replace(/^Bearer\s+/i, '')
  if (!bearerToken) return json(401, { error: 'Sesion no encontrada.' })

  const body = parseBody(event)
  if (!body) return json(400, { error: 'Solicitud invalida.' })

  const targetUserId = cleanText(body.targetUserId)
  const reason = cleanText(body.reason)

  if (!targetUserId) return json(400, { error: 'Usuario no encontrado.' })
  if (reason.length < 10) return json(400, { error: 'El motivo debe tener al menos 10 caracteres.' })

  const adminClient = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: userData, error: userError } = await adminClient.auth.getUser(bearerToken)
  if (userError || !userData?.user) return json(401, { error: 'Sesion invalida.' })

  const rpcClient = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${bearerToken}` } },
  })

  const { data: eligibilityData, error: eligibilityError } = await rpcClient.rpc('admin_check_user_delete_eligibility', {
    p_target_user_id: targetUserId,
  })

  if (eligibilityError) return json(400, { error: friendlyReason(eligibilityError.message) })

  const eligibility = firstRow(eligibilityData)
  if (!eligibility?.can_delete) {
    await rpcClient.rpc('admin_prepare_user_permanent_delete', {
      p_target_user_id: targetUserId,
      p_reason: reason,
    })

    return json(403, {
      error: friendlyReason(eligibility?.reason),
      reason: friendlyReason(eligibility?.reason),
      block_reasons: eligibility?.block_reasons || [],
      metadata: eligibility?.metadata || {},
    })
  }

  const { data: prepareData, error: prepareError } = await rpcClient.rpc('admin_prepare_user_permanent_delete', {
    p_target_user_id: targetUserId,
    p_reason: reason,
  })

  if (prepareError) return json(400, { error: friendlyReason(prepareError.message) })

  const prepared = firstRow(prepareData)
  if (!prepared?.prepared) {
    return json(403, {
      error: friendlyReason(prepared?.reason),
      reason: friendlyReason(prepared?.reason),
      metadata: prepared?.metadata || {},
    })
  }

  const { error: authDeleteError } = await adminClient.auth.admin.deleteUser(prepared.auth_user_id || targetUserId)
  if (authDeleteError) {
    await rpcClient.rpc('admin_mark_user_auth_delete_failed', {
      p_target_user_id: targetUserId,
      p_reason: authDeleteError.message,
    })

    return json(500, {
      error: 'No fue posible eliminar el acceso de autenticacion. No se eliminaron registros publicos del usuario.',
    })
  }

  const { data: deleteData, error: deleteError } = await rpcClient.rpc('admin_delete_user_public_records', {
    p_target_user_id: targetUserId,
    p_reason: reason,
  })

  if (deleteError) {
    return json(500, {
      error: 'El acceso de autenticacion fue eliminado, pero no fue posible finalizar la limpieza publica. Revisa el usuario manualmente.',
    })
  }

  const deleted = firstRow(deleteData)
  if (!deleted?.deleted) {
    return json(500, {
      error: 'El acceso de autenticacion fue eliminado, pero la limpieza publica no confirmo eliminacion. Revisa el usuario manualmente.',
      reason: friendlyReason(deleted?.reason),
      metadata: deleted?.metadata || {},
    })
  }

  return json(200, {
    ok: true,
    deleted: true,
    reason: deleted.reason || 'Usuario eliminado permanentemente.',
    target_user_id: deleted.target_user_id || targetUserId,
    metadata: deleted.metadata || {},
  })
}
