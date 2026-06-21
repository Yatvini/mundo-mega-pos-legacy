-- Gestión de sucursales, inventario inicial y asignación de usuarios.
create unique index if not exists branches_business_name_idx
on public.branches(business_id,lower(name));

create policy "admins_write_branches" on public.branches for all
using (business_id=current_business_id() and has_any_role(array['admin']::user_role[]))
with check (business_id=current_business_id() and has_any_role(array['admin']::user_role[]));

create or replace function public.create_branch(p_name text,p_address text,p_phone text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_business uuid; v_branch uuid;
begin
  select business_id into v_business from profiles where id=auth.uid() and active and role='admin';
  if v_business is null then raise exception 'Solo un administrador puede crear sucursales'; end if;
  insert into branches(business_id,name,address,phone)
  values(v_business,trim(p_name),nullif(trim(p_address),''),nullif(trim(p_phone),'')) returning id into v_branch;
  insert into inventory(branch_id,product_id,stock)
  select v_branch,id,0 from products where business_id=v_business and active
  on conflict do nothing;
  return v_branch;
end $$;

create or replace function public.switch_branch(p_branch_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_business uuid;
begin
  select business_id into v_business from profiles where id=auth.uid() and active and role in ('admin','supervisor');
  if v_business is null or not exists(select 1 from branches where id=p_branch_id and business_id=v_business and active)
  then raise exception 'Sucursal no autorizada'; end if;
  update profiles set branch_id=p_branch_id where id=auth.uid();
end $$;

create or replace function public.assign_member_branch(p_member_id uuid,p_branch_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_business uuid;
begin
  select business_id into v_business from profiles where id=auth.uid() and active and role='admin';
  if v_business is null
    or not exists(select 1 from profiles where id=p_member_id and business_id=v_business)
    or not exists(select 1 from branches where id=p_branch_id and business_id=v_business and active)
  then raise exception 'Asignación no autorizada'; end if;
  update profiles set branch_id=p_branch_id where id=p_member_id;
end $$;

grant execute on function create_branch(text,text,text) to authenticated;
grant execute on function switch_branch(uuid) to authenticated;
grant execute on function assign_member_branch(uuid,uuid) to authenticated;
