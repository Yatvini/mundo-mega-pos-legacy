-- Plataforma SaaS multiempresa para Grupo Multimarkets S.A.
-- Cada usuario operativo pertenece a una sola empresa. Los administradores de
-- plataforma gestionan empresas mediante RPCs SECURITY DEFINER sin abrir las RLS.

create extension if not exists unaccent;

alter table public.businesses
  add column if not exists slug text,
  add column if not exists industry text not null default 'retail',
  add column if not exists slogan text,
  add column if not exists logo_url text,
  add column if not exists primary_color text not null default '#155b3d',
  add column if not exists accent_color text not null default '#c9f45c',
  add column if not exists plan text not null default 'starter',
  add column if not exists status text not null default 'active',
  add column if not exists modules jsonb not null default '{"pos":true,"inventory":true,"purchases":true,"customers":true,"cash":true,"reports":true,"branches":true}'::jsonb,
  add column if not exists max_branches integer not null default 1,
  add column if not exists max_users integer not null default 5,
  add column if not exists updated_at timestamptz not null default now();

update public.businesses
set slug = trim(both '-' from regexp_replace(lower(unaccent(name)), '[^a-z0-9]+', '-', 'g')) || '-' || left(id::text, 6)
where slug is null or slug = '';

create unique index if not exists businesses_slug_idx on public.businesses(slug);

alter table public.businesses drop constraint if exists businesses_industry_check;
alter table public.businesses add constraint businesses_industry_check
  check (industry in ('retail','minimarket','pharmacy','hardware','clothing','restaurant','services','other'));
alter table public.businesses drop constraint if exists businesses_plan_check;
alter table public.businesses add constraint businesses_plan_check
  check (plan in ('starter','business','enterprise'));
alter table public.businesses drop constraint if exists businesses_status_check;
alter table public.businesses add constraint businesses_status_check
  check (status in ('pending','active','suspended','cancelled'));

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.business_admin_invitations (
  id uuid primary key default uuid_generate_v4(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  email text not null,
  full_name text,
  invited_by uuid not null references auth.users(id),
  expires_at timestamptz not null default (now() + interval '14 days'),
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists pending_business_admin_email_idx
  on public.business_admin_invitations(lower(email)) where accepted_at is null;

alter table public.platform_admins enable row level security;
alter table public.business_admin_invitations enable row level security;

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path=public
as $$
  select exists(select 1 from platform_admins where user_id=auth.uid() and active);
$$;

drop policy if exists "platform_admin_own_record" on public.platform_admins;
create policy "platform_admin_own_record" on public.platform_admins for select
using (user_id=auth.uid() and active);

drop policy if exists "platform_admin_invitations" on public.business_admin_invitations;
create policy "platform_admin_invitations" on public.business_admin_invitations for all
using (is_platform_admin()) with check (is_platform_admin());

-- Convierte al administrador actual de MUNDO MEGA en dueño de la plataforma.
insert into public.platform_admins(user_id,full_name)
select u.id,coalesce(nullif(p.full_name,''),split_part(u.email,'@',1))
from auth.users u left join public.profiles p on p.id=u.id
where lower(u.email)=lower('yatdavid326@gmail.com')
on conflict (user_id) do update set active=true,full_name=excluded.full_name;

-- Conserva MUNDO MEGA como la primera empresa y aplica su identidad actual.
update public.businesses b set
  industry='minimarket', slogan='Minimarket más cercano.', plan='enterprise',
  max_branches=100, max_users=500,
  modules='{"pos":true,"inventory":true,"purchases":true,"customers":true,"cash":true,"reports":true,"branches":true,"returns":true,"corporate":true}'::jsonb,
  updated_at=now()
where exists (
  select 1 from public.profiles p join auth.users u on u.id=p.id
  where p.business_id=b.id and lower(u.email)=lower('yatdavid326@gmail.com')
);

create or replace function public.platform_summary()
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  if not is_platform_admin() then raise exception 'Acceso exclusivo del administrador de plataforma'; end if;
  select jsonb_build_object(
    'businesses',count(*),
    'activeBusinesses',count(*) filter(where status='active'),
    'pendingBusinesses',count(*) filter(where status='pending'),
    'suspendedBusinesses',count(*) filter(where status='suspended'),
    'branches',(select count(*) from branches),
    'users',(select count(*) from profiles where active),
    'salesToday',(select coalesce(sum(total),0) from sales where status='completed' and completed_at>=current_date)
  ) into result from businesses;
  return result;
end $$;

create or replace function public.platform_list_businesses()
returns table(
  id uuid,name text,legal_name text,slug text,industry text,plan text,status text,
  slogan text,primary_color text,accent_color text,modules jsonb,max_branches integer,max_users integer,
  branches bigint,users bigint,products bigint,sales_total numeric,created_at timestamptz
) language plpgsql security definer set search_path=public as $$
begin
  if not is_platform_admin() then raise exception 'Acceso exclusivo del administrador de plataforma'; end if;
  return query
  select b.id,b.name,b.legal_name,b.slug,b.industry,b.plan,b.status,b.slogan,
    b.primary_color,b.accent_color,b.modules,b.max_branches,b.max_users,
    (select count(*) from branches br where br.business_id=b.id),
    (select count(*) from profiles p where p.business_id=b.id and p.active),
    (select count(*) from products pr where pr.business_id=b.id and pr.active),
    (select coalesce(sum(s.total),0) from sales s where s.business_id=b.id and s.status='completed'),
    b.created_at
  from businesses b order by b.created_at desc;
end $$;

create or replace function public.platform_create_business(
  p_name text,p_legal_name text,p_industry text,p_admin_email text,p_admin_name text default null,
  p_plan text default 'starter',p_slogan text default null,p_primary_color text default '#155b3d',
  p_accent_color text default '#c9f45c'
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_business uuid; v_slug text; v_modules jsonb;
begin
  if not is_platform_admin() then raise exception 'Acceso exclusivo del administrador de plataforma'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'El nombre de la empresa es obligatorio'; end if;
  if p_admin_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then raise exception 'Correo del administrador inválido'; end if;
  if p_industry not in ('retail','minimarket','pharmacy','hardware','clothing','restaurant','services','other') then raise exception 'Nicho no válido'; end if;
  if p_plan not in ('starter','business','enterprise') then raise exception 'Plan no válido'; end if;
  if exists(select 1 from auth.users where lower(email)=lower(p_admin_email)) then
    raise exception 'Ese correo ya tiene una cuenta. Use otro correo para el administrador de la empresa.';
  end if;
  if exists(select 1 from business_admin_invitations where lower(email)=lower(p_admin_email) and accepted_at is null) then
    raise exception 'Ya existe una invitación pendiente para ese correo';
  end if;
  v_slug:=trim(both '-' from regexp_replace(lower(p_name), '[^a-z0-9]+', '-', 'g'))||'-'||substr(replace(gen_random_uuid()::text,'-',''),1,6);
  v_modules:=case when p_industry='restaurant' then
    '{"pos":true,"inventory":true,"purchases":true,"customers":true,"cash":true,"reports":true,"branches":true,"tables":true,"recipes":true}'::jsonb
  else '{"pos":true,"inventory":true,"purchases":true,"customers":true,"cash":true,"reports":true,"branches":true,"returns":true}'::jsonb end;
  insert into businesses(name,legal_name,slug,industry,slogan,primary_color,accent_color,plan,status,modules,max_branches,max_users)
  values(trim(p_name),coalesce(nullif(trim(p_legal_name),''),trim(p_name)),v_slug,p_industry,nullif(trim(p_slogan),''),p_primary_color,p_accent_color,p_plan,'pending',v_modules,
    case p_plan when 'starter' then 1 when 'business' then 5 else 100 end,
    case p_plan when 'starter' then 5 when 'business' then 30 else 500 end)
  returning id into v_business;
  insert into branches(business_id,name) values(v_business,'Sucursal Central');
  insert into business_admin_invitations(business_id,email,full_name,invited_by)
  values(v_business,lower(trim(p_admin_email)),nullif(trim(p_admin_name),''),auth.uid());
  return v_business;
end $$;

create or replace function public.platform_update_business(
  p_business_id uuid,p_status text default null,p_plan text default null,p_name text default null,
  p_industry text default null,p_slogan text default null,p_modules jsonb default null
) returns void language plpgsql security definer set search_path=public as $$
begin
  if not is_platform_admin() then raise exception 'Acceso exclusivo del administrador de plataforma'; end if;
  if p_status is not null and p_status not in ('pending','active','suspended','cancelled') then raise exception 'Estado no válido'; end if;
  if p_plan is not null and p_plan not in ('starter','business','enterprise') then raise exception 'Plan no válido'; end if;
  if p_industry is not null and p_industry not in ('retail','minimarket','pharmacy','hardware','clothing','restaurant','services','other') then raise exception 'Nicho no válido'; end if;
  update businesses set
    status=coalesce(p_status,status),plan=coalesce(p_plan,plan),name=coalesce(nullif(trim(p_name),''),name),
    industry=coalesce(p_industry,industry),slogan=case when p_slogan is null then slogan else nullif(trim(p_slogan),'') end,
    modules=coalesce(p_modules,modules),
    max_branches=case coalesce(p_plan,plan) when 'starter' then 1 when 'business' then 5 else 100 end,
    max_users=case coalesce(p_plan,plan) when 'starter' then 5 when 'business' then 30 else 500 end,
    updated_at=now()
  where id=p_business_id;
  if not found then raise exception 'Empresa no encontrada'; end if;
end $$;

create or replace function public.platform_resend_business_invitation(p_business_id uuid,p_email text,p_full_name text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not is_platform_admin() then raise exception 'Acceso exclusivo del administrador de plataforma'; end if;
  delete from business_admin_invitations where business_id=p_business_id and accepted_at is null;
  insert into business_admin_invitations(business_id,email,full_name,invited_by)
  values(p_business_id,lower(trim(p_email)),nullif(trim(p_full_name),''),auth.uid());
  update businesses set status='pending',updated_at=now() where id=p_business_id;
end $$;

-- Nuevos usuarios: primero invitación de administrador de empresa, luego invitación
-- interna de equipo. Sin invitación no se crea una empresa fuera del panel general.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_admin_inv business_admin_invitations%rowtype; v_team_inv team_invitations%rowtype; v_branch uuid;
begin
  select * into v_admin_inv from business_admin_invitations
  where lower(email)=lower(new.email) and accepted_at is null and expires_at>now()
  order by created_at desc limit 1 for update;
  if found then
    select id into v_branch from branches where business_id=v_admin_inv.business_id order by created_at limit 1;
    insert into profiles(id,business_id,branch_id,full_name,role)
    values(new.id,v_admin_inv.business_id,v_branch,
      coalesce(nullif(new.raw_user_meta_data->>'full_name',''),v_admin_inv.full_name,split_part(new.email,'@',1)),'admin');
    update business_admin_invitations set accepted_at=now() where id=v_admin_inv.id;
    update businesses set status='active',updated_at=now() where id=v_admin_inv.business_id;
    return new;
  end if;
  select * into v_team_inv from team_invitations
  where lower(email)=lower(new.email) and accepted_at is null order by created_at desc limit 1 for update;
  if found then
    insert into profiles(id,business_id,branch_id,full_name,role)
    values(new.id,v_team_inv.business_id,v_team_inv.branch_id,
      coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1)),v_team_inv.role);
    update team_invitations set accepted_at=now() where id=v_team_inv.id;
    return new;
  end if;
  raise exception 'Necesitas una invitación válida para crear una cuenta';
end $$;

-- Bloquea la operación de empresas suspendidas incluso si el usuario conserva sesión.
create or replace function public.current_business_id() returns uuid
language sql stable security definer set search_path=public as $$
  select p.business_id from profiles p join businesses b on b.id=p.business_id
  where p.id=auth.uid() and p.active and b.status='active'
$$;

grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.platform_summary() to authenticated;
grant execute on function public.platform_list_businesses() to authenticated;
grant execute on function public.platform_create_business(text,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.platform_update_business(uuid,text,text,text,text,text,jsonb) to authenticated;
grant execute on function public.platform_resend_business_invitation(uuid,text,text) to authenticated;
