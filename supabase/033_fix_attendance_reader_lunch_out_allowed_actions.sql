-- 033_fix_attendance_reader_lunch_out_allowed_actions.sql
-- Hotfix complementario para asegurar que el lector QR V2 devuelva lunch_out
-- cuando el empleado ya tiene entrada abierta y la empresa usa almuerzo.
-- Ejecutar despues de 032_fix_attendance_v2_lunch_out_state.sql.
-- No cambia tablas, datos, RLS, policies, tokens ni digest; solo recrea la RPC de validacion del lector.

create or replace function public.attendance_reader_v2_validate_employee_token(
  p_reader_token text,
  p_employee_token text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_reader record;
  v_employee record;
  v_resolved jsonb;
  v_allowed text[] := '{}';
  v_status text;
  v_uses_lunch boolean := false;
  v_allows_half_day boolean := false;
  v_allows_continuous_day boolean := false;
begin
  select * into v_reader from public.attendance_reader_v2_context(p_reader_token);
  select * into v_employee from public.attendance_qr_v2_context(p_employee_token);

  if v_employee.business_id <> v_reader.business_id then
    raise exception 'El QR pertenece a otra empresa';
  end if;

  v_resolved := public.attendance_qr_v2_resolve(p_employee_token);

  select coalesce(array_agg(value), '{}')
  into v_allowed
  from jsonb_array_elements_text(coalesce(v_resolved -> 'allowedActions', '[]'::jsonb)) as actions(value);

  v_status := coalesce(v_resolved -> 'daily' ->> 'status', '');
  v_uses_lunch := coalesce((v_resolved -> 'settings' ->> 'usesLunch')::boolean, false);
  v_allows_half_day := coalesce((v_resolved -> 'settings' ->> 'allowsHalfDay')::boolean, false);
  v_allows_continuous_day := coalesce((v_resolved -> 'settings' ->> 'allowsContinuousDay')::boolean, false);

  if v_status = 'open'
     and v_uses_lunch
     and v_resolved -> 'daily' ->> 'checkInAt' is not null
     and v_resolved -> 'daily' ->> 'lunchOutAt' is null
     and v_resolved -> 'daily' ->> 'lunchInAt' is null
     and v_resolved -> 'daily' ->> 'checkOutAt' is null then
    v_allowed := array['lunch_out','check_out'];
    if v_allows_half_day then v_allowed := array_append(v_allowed, 'half_day_out'); end if;
    if v_allows_continuous_day then v_allowed := array_append(v_allowed, 'continuous_day_out'); end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'readerId', v_reader.reader_id,
    'businessId', v_reader.business_id,
    'businessName', v_reader.business_name,
    'person', v_resolved -> 'person',
    'daily', v_resolved -> 'daily',
    'allowedActions', v_allowed,
    'message', coalesce(v_resolved -> 'daily' ->> 'message', 'Empleado validado.')
  );
end;
$$;

grant execute on function public.attendance_reader_v2_validate_employee_token(text,text) to authenticated, service_role;

select pg_notify('pgrst','reload schema');
