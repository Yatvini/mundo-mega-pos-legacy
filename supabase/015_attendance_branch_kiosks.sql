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
  if v_branch is null then select branch_id into v_branch from profiles where id=auth.uid(); end if;
  if v_branch is not null and not exists(select 1 from branches where id=v_branch and business_id=v_business) then
    raise exception 'Sucursal no valida';
  end if;
  insert into attendance_kiosks(business_id,branch_id)
  select v_business,v_branch
  where not exists(
    select 1 from attendance_kiosks
    where business_id=v_business and active=true and coalesce(branch_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(v_branch,'00000000-0000-0000-0000-000000000000'::uuid)
  );
  return query
  select k.token from attendance_kiosks k
  where k.business_id=v_business and k.active=true
    and coalesce(k.branch_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(v_branch,'00000000-0000-0000-0000-000000000000'::uuid)
  order by k.created_at limit 1;
end $$;

grant execute on function public.attendance_ensure_kiosk(uuid) to authenticated;
