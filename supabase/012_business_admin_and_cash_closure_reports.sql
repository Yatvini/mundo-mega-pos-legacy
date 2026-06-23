-- Administracion avanzada de empresas y reportes de cierre de caja.
-- Ejecutar en Supabase SQL Editor despues de la migracion 011.

create or replace function public.platform_summary()
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  if not is_platform_admin() then raise exception 'Acceso exclusivo del administrador de plataforma'; end if;
  select jsonb_build_object(
    'businesses',count(*) filter(where status <> 'cancelled'),
    'activeBusinesses',count(*) filter(where status='active'),
    'pendingBusinesses',count(*) filter(where status='pending'),
    'suspendedBusinesses',count(*) filter(where status='suspended'),
    'branches',(select count(*) from branches br join businesses b on b.id=br.business_id where b.status <> 'cancelled'),
    'users',(select count(*) from profiles p join businesses b on b.id=p.business_id where p.active and b.status <> 'cancelled'),
    'salesToday',(select coalesce(sum(total),0) from sales s join businesses b on b.id=s.business_id where s.status='completed' and b.status <> 'cancelled' and s.completed_at>=current_date)
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
  from businesses b
  where b.status <> 'cancelled'
  order by b.created_at desc;
end $$;

create or replace function public.platform_update_business(
  p_business_id uuid,p_status text default null,p_plan text default null,p_name text default null,
  p_industry text default null,p_slogan text default null,p_modules jsonb default null,
  p_legal_name text default null,p_primary_color text default null,p_accent_color text default null
) returns void language plpgsql security definer set search_path=public as $$
begin
  if not is_platform_admin() then raise exception 'Acceso exclusivo del administrador de plataforma'; end if;
  if p_status is not null and p_status not in ('pending','active','suspended','cancelled') then raise exception 'Estado no valido'; end if;
  if p_plan is not null and p_plan not in ('starter','business','enterprise') then raise exception 'Plan no valido'; end if;
  if p_industry is not null and p_industry not in ('retail','minimarket','pharmacy','hardware','clothing','restaurant','services','other') then raise exception 'Nicho no valido'; end if;

  update businesses set
    status=coalesce(p_status,status),
    plan=coalesce(p_plan,plan),
    name=coalesce(nullif(trim(p_name),''),name),
    legal_name=case when p_legal_name is null then legal_name else coalesce(nullif(trim(p_legal_name),''),name) end,
    industry=coalesce(p_industry,industry),
    slogan=case when p_slogan is null then slogan else nullif(trim(p_slogan),'') end,
    primary_color=coalesce(nullif(trim(p_primary_color),''),primary_color),
    accent_color=coalesce(nullif(trim(p_accent_color),''),accent_color),
    modules=coalesce(p_modules,modules),
    max_branches=case coalesce(p_plan,plan) when 'starter' then 1 when 'business' then 5 else 100 end,
    max_users=case coalesce(p_plan,plan) when 'starter' then 5 when 'business' then 30 else 500 end,
    updated_at=now()
  where id=p_business_id;
  if not found then raise exception 'Empresa no encontrada'; end if;
end $$;

create or replace function public.platform_delete_business(p_business_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not is_platform_admin() then raise exception 'Acceso exclusivo del administrador de plataforma'; end if;
  if exists(select 1 from profiles where id=auth.uid() and business_id=p_business_id) then
    raise exception 'No puedes eliminar la empresa desde la cual administras la plataforma';
  end if;
  update businesses set status='cancelled', updated_at=now() where id=p_business_id;
  if not found then raise exception 'Empresa no encontrada'; end if;
  update profiles set active=false where business_id=p_business_id;
  update branches set active=false where business_id=p_business_id;
  delete from business_admin_invitations where business_id=p_business_id and accepted_at is null;
end $$;

create or replace function public.cash_closure_reports(p_from timestamptz,p_to timestamptz,p_branch_id uuid default null)
returns table(
  session_id uuid, branch_id uuid, branch_name text, opened_at timestamptz, closed_at timestamptz,
  user_name text, opening_amount numeric, expected_amount numeric, closing_amount numeric, difference numeric,
  cash_sales numeric, card_sales numeric, transfer_sales numeric, credit_sales numeric,
  manual_income numeric, manual_expense numeric, refunds numeric, total_sales numeric
) language plpgsql security definer set search_path=public as $$
begin
  return query
  select
    cs.id, b.id, b.name, cs.opened_at, cs.closed_at,
    p.full_name,
    cs.opening_amount,
    coalesce(cs.expected_amount,0),
    coalesce(cs.closing_amount,0),
    coalesce(cs.closing_amount,0)-coalesce(cs.expected_amount,0),
    coalesce((select sum(sp.amount) from sale_payments sp join sales s on s.id=sp.sale_id where s.session_id=cs.id and s.status='completed' and sp.method='cash'),0),
    coalesce((select sum(sp.amount) from sale_payments sp join sales s on s.id=sp.sale_id where s.session_id=cs.id and s.status='completed' and sp.method='card'),0),
    coalesce((select sum(sp.amount) from sale_payments sp join sales s on s.id=sp.sale_id where s.session_id=cs.id and s.status='completed' and sp.method='transfer'),0),
    coalesce((select sum(sp.amount) from sale_payments sp join sales s on s.id=sp.sale_id where s.session_id=cs.id and s.status='completed' and sp.method='credit'),0),
    coalesce((select sum(cm.amount) from cash_movements cm where cm.session_id=cs.id and cm.kind='income'),0),
    coalesce((select sum(cm.amount) from cash_movements cm where cm.session_id=cs.id and cm.kind='expense'),0),
    coalesce((select sum(sr.amount) from sale_returns sr join sales s on s.id=sr.sale_id where s.session_id=cs.id),0),
    coalesce((select sum(s.total) from sales s where s.session_id=cs.id and s.status='completed'),0)
  from cash_sessions cs
  join branches b on b.id=cs.branch_id
  join profiles p on p.id=cs.user_id
  where b.business_id=current_business_id()
    and cs.closed_at is not null
    and cs.closed_at >= p_from and cs.closed_at <= p_to
    and (p_branch_id is null or cs.branch_id=p_branch_id)
  order by cs.closed_at desc;
end $$;

grant execute on function public.platform_update_business(uuid,text,text,text,text,text,jsonb,text,text,text) to authenticated;
grant execute on function public.platform_delete_business(uuid) to authenticated;
grant execute on function public.cash_closure_reports(timestamptz,timestamptz,uuid) to authenticated;
