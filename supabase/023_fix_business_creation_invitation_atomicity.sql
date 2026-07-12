-- 023_fix_business_creation_invitation_atomicity.sql
-- Objetivo: evitar empresas, sucursales e invitaciones huerfanas cuando falla
-- el envio externo del correo de invitacion del administrador.
-- Ejecutar despues de 022.

begin;

create or replace function public.platform_rollback_failed_business_invitation(
  p_business_id uuid,
  p_admin_email text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_business public.businesses%rowtype;
begin
  if not public.is_platform_admin() then
    raise exception 'Acceso exclusivo del administrador de plataforma';
  end if;

  if p_business_id is null then
    raise exception 'Empresa no encontrada';
  end if;

  if p_admin_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then
    raise exception 'Correo del administrador invalido';
  end if;

  select *
    into v_business
  from public.businesses
  where id = p_business_id
  for update;

  if not found then
    return;
  end if;

  if v_business.status <> 'pending' then
    raise exception 'No se puede revertir una empresa que ya no esta pendiente';
  end if;

  if not exists (
    select 1
    from public.business_admin_invitations bai
    where bai.business_id = p_business_id
      and lower(bai.email) = lower(trim(p_admin_email))
      and bai.accepted_at is null
  ) then
    raise exception 'No existe una invitacion pendiente para revertir';
  end if;

  if exists (select 1 from public.profiles p where p.business_id = p_business_id)
    or exists (select 1 from public.products p where p.business_id = p_business_id)
    or exists (select 1 from public.customers c where c.business_id = p_business_id)
    or exists (select 1 from public.suppliers s where s.business_id = p_business_id)
    or exists (select 1 from public.sales s where s.business_id = p_business_id)
    or exists (select 1 from public.sale_returns sr where sr.business_id = p_business_id)
    or exists (select 1 from public.purchases p where p.business_id = p_business_id)
    or exists (select 1 from public.inventory_movements im where im.business_id = p_business_id)
    or exists (select 1 from public.team_invitations ti where ti.business_id = p_business_id)
    or exists (
      select 1
      from public.cash_sessions cs
      join public.branches br on br.id = cs.branch_id
      where br.business_id = p_business_id
    )
  then
    raise exception 'No se puede revertir la empresa porque ya tiene datos operativos';
  end if;

  delete from public.business_admin_invitations
  where business_id = p_business_id
    and lower(email) = lower(trim(p_admin_email))
    and accepted_at is null;

  delete from public.branches
  where business_id = p_business_id;

  delete from public.businesses
  where id = p_business_id
    and status = 'pending';
end;
$$;

grant execute on function public.platform_rollback_failed_business_invitation(uuid,text) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
