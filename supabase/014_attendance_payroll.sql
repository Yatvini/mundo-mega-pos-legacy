create extension if not exists pgcrypto;

create table if not exists public.attendance_employees (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  full_name text not null,
  position text,
  base_salary numeric(12,2) not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.attendance_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  kind text not null default 'custom' check(kind in ('start_shift','lunch_out','lunch_in','end_shift','custom')),
  sort_order int not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.attendance_kiosks (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  token text not null unique default encode(gen_random_bytes(18),'hex'),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.attendance_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  employee_id uuid not null references public.attendance_employees(id) on delete cascade,
  category_id uuid not null references public.attendance_categories(id) on delete restrict,
  marked_at timestamptz not null default now(),
  note text,
  source text not null default 'qr',
  created_at timestamptz not null default now()
);

alter table public.attendance_employees enable row level security;
alter table public.attendance_categories enable row level security;
alter table public.attendance_kiosks enable row level security;
alter table public.attendance_events enable row level security;

drop policy if exists attendance_employees_business on public.attendance_employees;
create policy attendance_employees_business on public.attendance_employees for all
using (business_id=public.current_business_id())
with check (business_id=public.current_business_id());

drop policy if exists attendance_categories_business on public.attendance_categories;
create policy attendance_categories_business on public.attendance_categories for all
using (business_id=public.current_business_id())
with check (business_id=public.current_business_id());

drop policy if exists attendance_kiosks_business on public.attendance_kiosks;
create policy attendance_kiosks_business on public.attendance_kiosks for all
using (business_id=public.current_business_id())
with check (business_id=public.current_business_id());

drop policy if exists attendance_events_business on public.attendance_events;
create policy attendance_events_business on public.attendance_events for all
using (business_id=public.current_business_id())
with check (business_id=public.current_business_id());

create or replace function public.attendance_seed_defaults(p_business_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from attendance_categories where business_id=p_business_id) then
    insert into attendance_categories(business_id,name,kind,sort_order) values
    (p_business_id,'Inicio de jornada','start_shift',10),
    (p_business_id,'Ir a comer','lunch_out',20),
    (p_business_id,'Regresando de comer','lunch_in',30),
    (p_business_id,'Terminar dia','end_shift',40);
  end if;
end $$;

create or replace function public.attendance_ensure_kiosk()
returns table(token text)
language plpgsql security definer set search_path=public as $$
declare
  v_business uuid:=public.current_business_id();
  v_branch uuid;
begin
  if v_business is null then raise exception 'Sesion no encontrada'; end if;
  if not exists(select 1 from profiles where id=auth.uid() and role in ('admin','supervisor')) then
    raise exception 'No tienes permiso para administrar asistencia';
  end if;
  perform public.attendance_seed_defaults(v_business);
  select branch_id into v_branch from profiles where id=auth.uid();
  insert into attendance_kiosks(business_id,branch_id)
  select v_business,v_branch
  where not exists(select 1 from attendance_kiosks where business_id=v_business and active=true);
  return query select k.token from attendance_kiosks k where k.business_id=v_business and k.active=true order by k.created_at limit 1;
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
  insert into attendance_events(business_id,branch_id,employee_id,category_id,note)
  values(v_kiosk.business_id,coalesce(v_employee.branch_id,v_kiosk.branch_id),v_employee.id,v_category.id,p_note)
  returning * into v_event;
  return jsonb_build_object('id',v_event.id,'markedAt',v_event.marked_at,'employeeName',v_employee.full_name,'categoryName',v_category.name);
end $$;

grant execute on function public.attendance_ensure_kiosk() to authenticated;
grant execute on function public.attendance_kiosk_data(text) to anon, authenticated;
grant execute on function public.attendance_mark(text,uuid,uuid,text) to anon, authenticated;
