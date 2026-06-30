-- Restaurar asistencia al comportamiento anterior a la seguridad avanzada.
-- No borra empleados, marcajes ni QR existentes.
-- Solo vuelve a dejar las funciones con la firma que usa la app estable.

drop function if exists public.attendance_ensure_kiosk(uuid);
drop function if exists public.attendance_mark(text,uuid,uuid,text,numeric,numeric,integer);
drop function if exists public.attendance_manual_mark(uuid,uuid,timestamptz,text);

create or replace function public.attendance_ensure_kiosk(p_branch_id uuid default null)
returns table(token text)
language plpgsql security definer set search_path=public as $$
declare
  v_business uuid:=public.current_business_id();
  v_branch uuid:=p_branch_id;
begin
  if v_business is null then raise exception 'Sesion no encontrada'; end if;
  if not exists(select 1 from profiles where id=auth.uid() and role in ('admin','supervisor')) then
    raise exception 'No tienes permiso para administrar asistencia';
  end if;

  perform public.attendance_seed_defaults(v_business);

  if v_branch is null then
    select branch_id into v_branch from profiles where id=auth.uid();
  end if;

  if v_branch is not null and not exists(select 1 from branches where id=v_branch and business_id=v_business) then
    raise exception 'Sucursal no valida';
  end if;

  insert into attendance_kiosks(business_id,branch_id)
  select v_business,v_branch
  where not exists(
    select 1
    from attendance_kiosks
    where business_id=v_business
      and active=true
      and coalesce(branch_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(v_branch,'00000000-0000-0000-0000-000000000000'::uuid)
  );

  return query
  select k.token
  from attendance_kiosks k
  where k.business_id=v_business
    and k.active=true
    and coalesce(k.branch_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(v_branch,'00000000-0000-0000-0000-000000000000'::uuid)
  order by k.created_at
  limit 1;
end $$;

create or replace function public.attendance_kiosk_data(p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_kiosk attendance_kiosks%rowtype;
  v_result jsonb;
begin
  select * into v_kiosk from attendance_kiosks where token=p_token and active=true;
  if not found then raise exception 'Link de asistencia no valido'; end if;

  perform public.attendance_seed_defaults(v_kiosk.business_id);

  select jsonb_build_object(
    'business',(select jsonb_build_object('id',b.id,'name',b.name) from businesses b where b.id=v_kiosk.business_id),
    'branch',(select jsonb_build_object('id',br.id,'name',br.name) from branches br where br.id=v_kiosk.branch_id),
    'employees',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'fullName',e.full_name,'position',coalesce(e.position,'')) order by e.full_name) from attendance_employees e where e.business_id=v_kiosk.business_id and e.active=true and (v_kiosk.branch_id is null or e.branch_id is null or e.branch_id=v_kiosk.branch_id)),'[]'::jsonb),
    'categories',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'kind',c.kind) order by c.sort_order,c.name) from attendance_categories c where c.business_id=v_kiosk.business_id and c.active=true),'[]'::jsonb)
  ) into v_result;

  return v_result;
end $$;

create or replace function public.attendance_mark(p_token text,p_employee_id uuid,p_category_id uuid,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_kiosk attendance_kiosks%rowtype;
  v_employee attendance_employees%rowtype;
  v_category attendance_categories%rowtype;
  v_event attendance_events%rowtype;
begin
  select * into v_kiosk from attendance_kiosks where token=p_token and active=true;
  if not found then raise exception 'Link de asistencia no valido'; end if;

  select * into v_employee from attendance_employees where id=p_employee_id and business_id=v_kiosk.business_id and active=true;
  if not found then raise exception 'Empleado no encontrado'; end if;

  select * into v_category from attendance_categories where id=p_category_id and business_id=v_kiosk.business_id and active=true;
  if not found then raise exception 'Categoria no encontrada'; end if;

  insert into attendance_events(business_id,branch_id,employee_id,category_id,note,source)
  values(v_kiosk.business_id,coalesce(v_employee.branch_id,v_kiosk.branch_id),v_employee.id,v_category.id,p_note,'qr')
  returning * into v_event;

  return jsonb_build_object(
    'id',v_event.id,
    'markedAt',v_event.marked_at,
    'employeeName',v_employee.full_name,
    'categoryName',v_category.name
  );
end $$;

grant execute on function public.attendance_ensure_kiosk(uuid) to authenticated;
grant execute on function public.attendance_kiosk_data(text) to anon, authenticated;
grant execute on function public.attendance_mark(text,uuid,uuid,text) to anon, authenticated;
