-- Seguridad avanzada para control de asistencia:
-- geolocalizacion por sucursal, QR rotativo, alertas y marcaje manual.

alter table public.branches
  add column if not exists latitude numeric(10,7),
  add column if not exists longitude numeric(10,7),
  add column if not exists attendance_radius_m integer not null default 80;

alter table public.attendance_kiosks
  add column if not exists expires_at timestamptz,
  add column if not exists rotation_minutes integer not null default 1440;

alter table public.attendance_events
  add column if not exists latitude numeric(10,7),
  add column if not exists longitude numeric(10,7),
  add column if not exists accuracy_m integer,
  add column if not exists distance_m integer,
  add column if not exists status text not null default 'valid',
  add column if not exists alert_reason text,
  add column if not exists marked_by uuid references auth.users(id);

alter table public.attendance_events drop constraint if exists attendance_events_status_check;
alter table public.attendance_events add constraint attendance_events_status_check
  check (status in ('valid','suspicious','manual'));

create or replace function public.attendance_security_config(p_business_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'geoRequired',coalesce((b.modules->'attendanceSecurity'->>'geoRequired')::boolean,false),
    'dynamicQr',coalesce((b.modules->'attendanceSecurity'->>'dynamicQr')::boolean,false),
    'suspiciousAlerts',coalesce((b.modules->'attendanceSecurity'->>'suspiciousAlerts')::boolean,false),
    'manualEntry',coalesce((b.modules->'attendanceSecurity'->>'manualEntry')::boolean,true),
    'rotationMinutes',coalesce((b.modules->'attendanceSecurity'->>'rotationMinutes')::integer,1440),
    'defaultRadiusM',coalesce((b.modules->'attendanceSecurity'->>'defaultRadiusM')::integer,80)
  )
  from businesses b where b.id=p_business_id;
$$;

create or replace function public.platform_set_attendance_security(p_business_id uuid,p_security jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not is_platform_admin() then raise exception 'Acceso exclusivo del administrador de plataforma'; end if;
  update businesses
  set modules = jsonb_set(
      coalesce(modules,'{}'::jsonb),
      '{attendanceSecurity}',
      coalesce(p_security,'{}'::jsonb),
      true
    ),
    updated_at=now()
  where id=p_business_id;
  if not found then raise exception 'Empresa no encontrada'; end if;
end $$;

create or replace function public.distance_meters(p_lat1 numeric,p_lon1 numeric,p_lat2 numeric,p_lon2 numeric)
returns integer language sql immutable as $$
  select round(
    6371000 * 2 * asin(
      sqrt(
        power(sin(radians((p_lat2 - p_lat1)::double precision) / 2), 2) +
        cos(radians(p_lat1::double precision)) *
        cos(radians(p_lat2::double precision)) *
        power(sin(radians((p_lon2 - p_lon1)::double precision) / 2), 2)
      )
    )
  )::integer;
$$;

drop function if exists public.attendance_ensure_kiosk(uuid);

create or replace function public.attendance_ensure_kiosk(p_branch_id uuid default null)
returns table(token text, expires_at timestamptz)
language plpgsql security definer set search_path=public as $$
declare
  v_business uuid:=public.current_business_id();
  v_branch uuid:=p_branch_id;
  v_security jsonb;
  v_dynamic boolean;
  v_minutes integer;
  v_expires timestamptz;
begin
  if v_business is null then raise exception 'Sesion no encontrada'; end if;
  if not exists(select 1 from profiles where id=auth.uid() and role in ('admin','supervisor')) then
    raise exception 'No tienes permiso para administrar asistencia';
  end if;
  perform public.attendance_seed_defaults(v_business);
  if v_branch is null then select branch_id into v_branch from profiles where id=auth.uid(); end if;
  if v_branch is not null and not exists(select 1 from branches where id=v_branch and business_id=v_business) then
    raise exception 'Sucursal no valida';
  end if;

  v_security:=public.attendance_security_config(v_business);
  v_dynamic:=coalesce((v_security->>'dynamicQr')::boolean,false);
  v_minutes:=greatest(5,coalesce((v_security->>'rotationMinutes')::integer,1440));
  v_expires:=case when v_dynamic then now() + make_interval(mins=>v_minutes) else null end;

  if v_dynamic then
    update attendance_kiosks set active=false
    where business_id=v_business and active=true and expires_at is not null and expires_at<=now()
      and coalesce(branch_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(v_branch,'00000000-0000-0000-0000-000000000000'::uuid);
  end if;

  insert into attendance_kiosks(business_id,branch_id,token,expires_at,rotation_minutes)
  select v_business,v_branch,encode(gen_random_bytes(18),'hex'),v_expires,v_minutes
  where not exists(
    select 1 from attendance_kiosks
    where business_id=v_business and active=true
      and (not v_dynamic or expires_at is null or expires_at>now())
      and coalesce(branch_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(v_branch,'00000000-0000-0000-0000-000000000000'::uuid)
  );

  return query
  select k.token,k.expires_at from attendance_kiosks k
  where k.business_id=v_business and k.active=true
    and (not v_dynamic or k.expires_at is null or k.expires_at>now())
    and coalesce(k.branch_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(v_branch,'00000000-0000-0000-0000-000000000000'::uuid)
  order by k.created_at desc limit 1;
end $$;

create or replace function public.attendance_kiosk_data(p_token text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_kiosk attendance_kiosks%rowtype;
  v_security jsonb;
  v_result jsonb;
begin
  select * into v_kiosk from attendance_kiosks where token=p_token and active=true;
  if not found then raise exception 'Link de asistencia no valido'; end if;
  if v_kiosk.expires_at is not null and v_kiosk.expires_at<=now() then
    update attendance_kiosks set active=false where id=v_kiosk.id;
    raise exception 'Este QR ya vencio. Solicita el QR actualizado.';
  end if;

  perform public.attendance_seed_defaults(v_kiosk.business_id);
  v_security:=public.attendance_security_config(v_kiosk.business_id);

  select jsonb_build_object(
    'business',(select jsonb_build_object('id',b.id,'name',b.name) from businesses b where b.id=v_kiosk.business_id),
    'branch',(select jsonb_build_object('id',br.id,'name',br.name,'latitude',br.latitude,'longitude',br.longitude,'radiusM',br.attendance_radius_m) from branches br where br.id=v_kiosk.branch_id),
    'security',v_security,
    'expiresAt',v_kiosk.expires_at,
    'employees',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'fullName',e.full_name,'position',coalesce(e.position,'')) order by e.full_name) from attendance_employees e where e.business_id=v_kiosk.business_id and e.active=true and (v_kiosk.branch_id is null or e.branch_id is null or e.branch_id=v_kiosk.branch_id)),'[]'::jsonb),
    'categories',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'kind',c.kind) order by c.sort_order,c.name) from attendance_categories c where c.business_id=v_kiosk.business_id and c.active=true),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $$;

create or replace function public.attendance_mark(
  p_token text,p_employee_id uuid,p_category_id uuid,p_note text default null,
  p_latitude numeric default null,p_longitude numeric default null,p_accuracy_m integer default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_kiosk attendance_kiosks%rowtype;
  v_employee attendance_employees%rowtype;
  v_category attendance_categories%rowtype;
  v_branch branches%rowtype;
  v_security jsonb;
  v_geo_required boolean;
  v_alerts boolean;
  v_distance integer;
  v_status text:='valid';
  v_reason text;
  v_event attendance_events%rowtype;
begin
  select * into v_kiosk from attendance_kiosks where token=p_token and active=true;
  if not found then raise exception 'Link de asistencia no valido'; end if;
  if v_kiosk.expires_at is not null and v_kiosk.expires_at<=now() then
    update attendance_kiosks set active=false where id=v_kiosk.id;
    raise exception 'Este QR ya vencio. Solicita el QR actualizado.';
  end if;
  select * into v_employee from attendance_employees where id=p_employee_id and business_id=v_kiosk.business_id and active=true;
  if not found then raise exception 'Empleado no encontrado'; end if;
  select * into v_category from attendance_categories where id=p_category_id and business_id=v_kiosk.business_id and active=true;
  if not found then raise exception 'Categoria no encontrada'; end if;

  v_security:=public.attendance_security_config(v_kiosk.business_id);
  v_geo_required:=coalesce((v_security->>'geoRequired')::boolean,false);
  v_alerts:=coalesce((v_security->>'suspiciousAlerts')::boolean,false);
  select * into v_branch from branches where id=coalesce(v_employee.branch_id,v_kiosk.branch_id);

  if v_geo_required and (p_latitude is null or p_longitude is null) then
    raise exception 'La ubicacion es obligatoria para marcar asistencia';
  end if;
  if (v_geo_required or v_alerts) and (v_branch.latitude is null or v_branch.longitude is null) then
    raise exception 'Esta sucursal no tiene ubicacion configurada';
  end if;
  if p_latitude is not null and p_longitude is not null and v_branch.latitude is not null and v_branch.longitude is not null then
    v_distance:=public.distance_meters(v_branch.latitude,v_branch.longitude,p_latitude,p_longitude);
    if v_geo_required and v_distance > coalesce(v_branch.attendance_radius_m,80) then
      raise exception 'Estas fuera del rango permitido para marcar asistencia. Distancia aproximada: % metros', v_distance;
    end if;
    if v_alerts and v_distance > coalesce(v_branch.attendance_radius_m,80) then
      v_status:='suspicious';
      v_reason:='Fuera del rango configurado';
    elsif v_alerts and coalesce(p_accuracy_m,0)>100 then
      v_status:='suspicious';
      v_reason:='GPS con baja precision';
    end if;
  end if;

  insert into attendance_events(business_id,branch_id,employee_id,category_id,note,source,latitude,longitude,accuracy_m,distance_m,status,alert_reason)
  values(v_kiosk.business_id,coalesce(v_employee.branch_id,v_kiosk.branch_id),v_employee.id,v_category.id,p_note,'qr',p_latitude,p_longitude,p_accuracy_m,v_distance,v_status,v_reason)
  returning * into v_event;
  return jsonb_build_object('id',v_event.id,'markedAt',v_event.marked_at,'employeeName',v_employee.full_name,'categoryName',v_category.name,'status',v_event.status,'alertReason',v_event.alert_reason,'distanceM',v_event.distance_m);
end $$;

create or replace function public.attendance_manual_mark(p_employee_id uuid,p_category_id uuid,p_marked_at timestamptz default now(),p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_business uuid:=public.current_business_id();
  v_employee attendance_employees%rowtype;
  v_category attendance_categories%rowtype;
  v_security jsonb;
  v_event attendance_events%rowtype;
begin
  if v_business is null then raise exception 'Sesion no encontrada'; end if;
  if not exists(select 1 from profiles where id=auth.uid() and role in ('admin','supervisor')) then
    raise exception 'No tienes permiso para registrar asistencia manual';
  end if;
  v_security:=public.attendance_security_config(v_business);
  if not coalesce((v_security->>'manualEntry')::boolean,true) then
    raise exception 'El marcaje manual no esta activo para esta empresa';
  end if;
  select * into v_employee from attendance_employees where id=p_employee_id and business_id=v_business and active=true;
  if not found then raise exception 'Empleado no encontrado'; end if;
  select * into v_category from attendance_categories where id=p_category_id and business_id=v_business and active=true;
  if not found then raise exception 'Categoria no encontrada'; end if;

  insert into attendance_events(business_id,branch_id,employee_id,category_id,note,marked_at,source,status,alert_reason,marked_by)
  values(v_business,v_employee.branch_id,v_employee.id,v_category.id,p_note,p_marked_at,'manual','manual','Marcaje manual por administrador',auth.uid())
  returning * into v_event;
  return jsonb_build_object('id',v_event.id,'markedAt',v_event.marked_at,'employeeName',v_employee.full_name,'categoryName',v_category.name,'status',v_event.status);
end $$;

update businesses
set modules=jsonb_set(coalesce(modules,'{}'::jsonb),'{attendanceSecurity}',
  coalesce(modules->'attendanceSecurity','{"geoRequired":false,"dynamicQr":false,"suspiciousAlerts":true,"manualEntry":true,"rotationMinutes":1440,"defaultRadiusM":80}'::jsonb),true)
where modules->'attendanceSecurity' is null;

grant execute on function public.attendance_security_config(uuid) to anon, authenticated;
grant execute on function public.platform_set_attendance_security(uuid,jsonb) to authenticated;
grant execute on function public.distance_meters(numeric,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.attendance_ensure_kiosk(uuid) to authenticated;
grant execute on function public.attendance_kiosk_data(text) to anon, authenticated;
grant execute on function public.attendance_mark(text,uuid,uuid,text,numeric,numeric,integer) to anon, authenticated;
grant execute on function public.attendance_manual_mark(uuid,uuid,timestamptz,text) to authenticated;
