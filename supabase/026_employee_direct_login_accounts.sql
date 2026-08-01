-- 026_employee_direct_login_accounts.sql
-- Creacion directa de empleados con username + password.
-- Ejecutar despues de 025_corporate_cash_movement_controls.sql.
-- Mantiene Supabase Auth como autoridad de sesion y no almacena contrasenas.

begin;

create table if not exists public.employee_accounts (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  business_id uuid not null references public.businesses(id) on delete cascade,
  username text not null,
  auth_email text not null,
  employee_email text not null,
  first_name text not null,
  last_name text not null,
  phone text,
  avatar_url text,
  force_password_change boolean not null default false,
  dark_mode boolean not null default false,
  permission_template text,
  permissions jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_accounts_username_format
    check (username = lower(username) and username ~ '^[a-z0-9._-]{3,32}$'),
  constraint employee_accounts_employee_email_format
    check (employee_email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'),
  constraint employee_accounts_auth_email_format
    check (auth_email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$')
);

create unique index if not exists employee_accounts_username_global_idx
  on public.employee_accounts (lower(username));

create unique index if not exists employee_accounts_auth_email_idx
  on public.employee_accounts (lower(auth_email));

create table if not exists public.employee_account_provisioning (
  auth_email text primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  username text not null,
  first_name text not null,
  last_name text not null,
  role public.user_role not null,
  active boolean not null default true,
  created_by uuid not null references public.profiles(id),
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  created_at timestamptz not null default now(),
  constraint employee_account_provisioning_username_format
    check (username = lower(username) and username ~ '^[a-z0-9._-]{3,32}$')
);

alter table public.employee_accounts enable row level security;
alter table public.employee_account_provisioning enable row level security;

drop policy if exists "employee_accounts_admin_read" on public.employee_accounts;
create policy "employee_accounts_admin_read" on public.employee_accounts for select
using (
  business_id = public.current_business_id()
  and public.has_any_role(array['admin']::public.user_role[])
);

drop policy if exists "employee_accounts_self_read" on public.employee_accounts;
create policy "employee_accounts_self_read" on public.employee_accounts for select
using (user_id = auth.uid());

create or replace function public.current_employee_login_status()
returns table(active boolean, force_password_change boolean)
language sql stable security definer set search_path=public
as $$
  select p.active, coalesce(ea.force_password_change, false)
  from public.profiles p
  left join public.employee_accounts ea on ea.user_id = p.id
  where p.id = auth.uid()
  limit 1
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_direct public.employee_account_provisioning%rowtype;
  v_admin_inv public.business_admin_invitations%rowtype;
  v_team_inv public.team_invitations%rowtype;
  v_branch uuid;
begin
  select * into v_direct
  from public.employee_account_provisioning
  where lower(auth_email) = lower(new.email)
    and expires_at > now()
  limit 1
  for update;

  if found then
    insert into public.profiles(id,business_id,branch_id,full_name,role,active)
    values(
      new.id,
      v_direct.business_id,
      v_direct.branch_id,
      trim(v_direct.first_name || ' ' || v_direct.last_name),
      v_direct.role,
      v_direct.active
    );
    delete from public.employee_account_provisioning where auth_email = v_direct.auth_email;
    return new;
  end if;

  select * into v_admin_inv from public.business_admin_invitations
  where lower(email)=lower(new.email) and accepted_at is null and expires_at>now()
  order by created_at desc limit 1 for update;
  if found then
    select id into v_branch from public.branches where business_id=v_admin_inv.business_id order by created_at limit 1;
    insert into public.profiles(id,business_id,branch_id,full_name,role)
    values(new.id,v_admin_inv.business_id,v_branch,
      coalesce(nullif(new.raw_user_meta_data->>'full_name',''),v_admin_inv.full_name,split_part(new.email,'@',1)),'admin');
    update public.business_admin_invitations set accepted_at=now() where id=v_admin_inv.id;
    update public.businesses set status='active',updated_at=now() where id=v_admin_inv.business_id;
    return new;
  end if;

  select * into v_team_inv from public.team_invitations
  where lower(email)=lower(new.email) and accepted_at is null order by created_at desc limit 1 for update;
  if found then
    insert into public.profiles(id,business_id,branch_id,full_name,role)
    values(new.id,v_team_inv.business_id,v_team_inv.branch_id,
      coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1)),v_team_inv.role);
    update public.team_invitations set accepted_at=now() where id=v_team_inv.id;
    return new;
  end if;

  raise exception 'Necesitas una invitacion valida para crear una cuenta';
end $$;

grant select on public.employee_accounts to authenticated;
grant execute on function public.current_employee_login_status() to authenticated;

select pg_notify('pgrst','reload schema');

commit;
