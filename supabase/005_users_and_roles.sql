-- Equipo, invitaciones y permisos por rol.
create table if not exists public.team_invitations (
  id uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses on delete cascade,
  branch_id uuid not null references branches on delete cascade,
  email text not null,
  role user_role not null default 'cashier',
  invited_by uuid not null references profiles,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  unique(business_id,email)
);
alter table public.team_invitations enable row level security;

create or replace function public.current_user_role() returns user_role
language sql stable security definer set search_path=public
as $$ select role from profiles where id=auth.uid() and active $$;

create or replace function public.current_business_id() returns uuid
language sql stable security definer set search_path=public
as $$ select business_id from profiles where id=auth.uid() and active $$;

create or replace function public.has_any_role(allowed user_role[]) returns boolean
language sql stable security definer set search_path=public
as $$ select coalesce((select role=any(allowed) from profiles where id=auth.uid() and active),false) $$;

create policy "team_invitations_admin" on public.team_invitations for all
using (business_id=current_business_id() and has_any_role(array['admin']::user_role[]))
with check (business_id=current_business_id() and has_any_role(array['admin']::user_role[]));

-- Una cuenta invitada se une al negocio; una cuenta sin invitación crea uno nuevo.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_invitation team_invitations%rowtype; v_business_id uuid; v_branch_id uuid;
begin
  select * into v_invitation from team_invitations
  where lower(email)=lower(new.email) and accepted_at is null order by created_at desc limit 1 for update;
  if found then
    insert into profiles(id,business_id,branch_id,full_name,role)
    values(new.id,v_invitation.business_id,v_invitation.branch_id,
      coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1)),v_invitation.role);
    update team_invitations set accepted_at=now() where id=v_invitation.id;
  else
    insert into businesses(name,legal_name)
    values(coalesce(nullif(new.raw_user_meta_data->>'business_name',''),'Mi minimarket'),coalesce(nullif(new.raw_user_meta_data->>'business_name',''),'Mi minimarket'))
    returning id into v_business_id;
    insert into branches(business_id,name) values(v_business_id,'Sucursal Central') returning id into v_branch_id;
    insert into profiles(id,business_id,branch_id,full_name,role)
    values(new.id,v_business_id,v_branch_id,coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1)),'admin');
  end if;
  return new;
end $$;

-- Sustituye políticas amplias por permisos de mínimo privilegio.
drop policy if exists "business_members_write_products" on products;
create policy "product_managers_write" on products for all
using (business_id=current_business_id() and has_any_role(array['admin','supervisor','warehouse']::user_role[]))
with check (business_id=current_business_id() and has_any_role(array['admin','supervisor','warehouse']::user_role[]));

drop policy if exists "business_members_categories" on categories;
create policy "members_read_categories" on categories for select using (business_id=current_business_id());
create policy "product_managers_categories" on categories for all
using (business_id=current_business_id() and has_any_role(array['admin','supervisor','warehouse']::user_role[]))
with check (business_id=current_business_id() and has_any_role(array['admin','supervisor','warehouse']::user_role[]));

drop policy if exists "inventory_access" on inventory;
create policy "members_read_inventory" on inventory for select using (exists(select 1 from branches b where b.id=branch_id and b.business_id=current_business_id()));
create policy "inventory_managers_write" on inventory for all
using (has_any_role(array['admin','supervisor','warehouse']::user_role[]) and exists(select 1 from branches b where b.id=branch_id and b.business_id=current_business_id()))
with check (has_any_role(array['admin','supervisor','warehouse']::user_role[]) and exists(select 1 from branches b where b.id=branch_id and b.business_id=current_business_id()));

drop policy if exists "business_members_customers" on customers;
create policy "sales_team_customers" on customers for all
using (business_id=current_business_id() and has_any_role(array['admin','supervisor','cashier']::user_role[]))
with check (business_id=current_business_id() and has_any_role(array['admin','supervisor','cashier']::user_role[]));

drop policy if exists "business_members_suppliers" on suppliers;
create policy "members_read_suppliers" on suppliers for select using (business_id=current_business_id());
create policy "purchasing_team_suppliers" on suppliers for all
using (business_id=current_business_id() and has_any_role(array['admin','supervisor','warehouse']::user_role[]))
with check (business_id=current_business_id() and has_any_role(array['admin','supervisor','warehouse']::user_role[]));

drop policy if exists "business_members_purchases" on purchases;
create policy "members_read_purchases" on purchases for select using (business_id=current_business_id());
create policy "purchasing_team_purchases" on purchases for all
using (business_id=current_business_id() and has_any_role(array['admin','supervisor','warehouse']::user_role[]))
with check (business_id=current_business_id() and has_any_role(array['admin','supervisor','warehouse']::user_role[]));

drop policy if exists "business_members_sales" on sales;
create policy "members_read_sales" on sales for select using (business_id=current_business_id());
create policy "sales_team_write" on sales for all
using (business_id=current_business_id() and has_any_role(array['admin','supervisor','cashier']::user_role[]))
with check (business_id=current_business_id() and has_any_role(array['admin','supervisor','cashier']::user_role[]));

drop policy if exists "cash_sessions_access" on cash_sessions;
create policy "cash_team_sessions" on cash_sessions for all
using (has_any_role(array['admin','supervisor','cashier']::user_role[]) and exists(select 1 from branches b where b.id=branch_id and b.business_id=current_business_id()))
with check (has_any_role(array['admin','supervisor','cashier']::user_role[]) and exists(select 1 from branches b where b.id=branch_id and b.business_id=current_business_id()));

drop policy if exists "cash_movements_access" on cash_movements;
create policy "cash_team_movements" on cash_movements for all
using (has_any_role(array['admin','supervisor','cashier']::user_role[]) and exists(select 1 from cash_sessions c join branches b on b.id=c.branch_id where c.id=session_id and b.business_id=current_business_id()))
with check (has_any_role(array['admin','supervisor','cashier']::user_role[]) and exists(select 1 from cash_sessions c join branches b on b.id=c.branch_id where c.id=session_id and b.business_id=current_business_id()));

create policy "admins_update_profiles" on profiles for update
using (business_id=current_business_id() and has_any_role(array['admin']::user_role[]))
with check (business_id=current_business_id());

grant execute on function current_user_role() to authenticated;
grant execute on function has_any_role(user_role[]) to authenticated;
