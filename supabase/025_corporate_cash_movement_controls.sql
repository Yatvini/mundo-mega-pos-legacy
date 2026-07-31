-- 025_corporate_cash_movement_controls.sql
-- Control corporativo V1 para editar/anular movimientos manuales de caja.
-- Ejecutar despues de 024. No borra movimientos financieros: usa anulacion logica y auditoria obligatoria.

begin;

alter table public.cash_movements
  add column if not exists status text not null default 'active',
  add column if not exists voided_at timestamptz,
  add column if not exists voided_by uuid references public.profiles(id),
  add column if not exists void_reason text,
  add column if not exists updated_by uuid references public.profiles(id),
  add column if not exists updated_at timestamptz,
  add column if not exists correction_reason text;

update public.cash_movements
set status = 'active'
where status is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'cash_movements_status_check'
      and conrelid = 'public.cash_movements'::regclass
  ) then
    alter table public.cash_movements
      add constraint cash_movements_status_check check (status in ('active','voided'));
  end if;
end $$;

create table if not exists public.cash_movement_audit_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  branch_id uuid not null references public.branches(id),
  cash_session_id uuid not null references public.cash_sessions(id),
  cash_movement_id uuid not null references public.cash_movements(id),
  action text not null check (action in ('update','void')),
  old_values jsonb not null,
  new_values jsonb,
  reason text not null,
  performed_by uuid not null references public.profiles(id),
  performed_at timestamptz not null default now(),
  ip_address text null,
  user_agent text null
);

alter table public.cash_movement_audit_logs enable row level security;

drop policy if exists "cash_movement_audit_logs_admin_read" on public.cash_movement_audit_logs;
create policy "cash_movement_audit_logs_admin_read" on public.cash_movement_audit_logs
for select
using (
  business_id = current_business_id()
  and has_any_role(array['admin']::user_role[])
);

create index if not exists cash_movement_audit_logs_business_branch_performed_idx
  on public.cash_movement_audit_logs(business_id, branch_id, performed_at desc);
create index if not exists cash_movement_audit_logs_movement_performed_idx
  on public.cash_movement_audit_logs(cash_movement_id, performed_at desc);
create index if not exists cash_movement_audit_logs_session_idx
  on public.cash_movement_audit_logs(cash_session_id);

create or replace function public.corporate_cash_movements(
  p_branch_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table(
  movement_id uuid,
  business_id uuid,
  branch_id uuid,
  branch_name text,
  cash_session_id uuid,
  session_opened_at timestamptz,
  session_closed_at timestamptz,
  is_session_open boolean,
  movement_created_at timestamptz,
  created_by uuid,
  created_by_name text,
  kind text,
  amount numeric,
  description text,
  status text,
  editable boolean,
  voidable boolean,
  voided_at timestamptz,
  void_reason text,
  updated_at timestamptz,
  correction_reason text,
  last_audit_at timestamptz
)
language plpgsql stable security definer set search_path=public as $$
declare
  v_profile public.profiles%rowtype;
begin
  select *
  into v_profile
  from public.profiles
  where id = auth.uid()
    and active
    and role = 'admin';

  if v_profile.id is null then
    raise exception 'No autorizado para controlar caja corporativa';
  end if;

  if p_branch_id is null then
    raise exception 'Selecciona una sucursal';
  end if;

  if p_to <= p_from then
    raise exception 'El rango de fechas no es valido';
  end if;

  if not exists (
    select 1
    from public.branches b
    where b.id = p_branch_id
      and b.business_id = v_profile.business_id
  ) then
    raise exception 'Sucursal no autorizada';
  end if;

  return query
  select
    cm.id,
    b.business_id,
    b.id,
    b.name,
    cs.id,
    cs.opened_at,
    cs.closed_at,
    cs.closed_at is null,
    cm.created_at,
    cm.user_id,
    coalesce(p.full_name, 'Sin usuario'),
    cm.kind::text,
    cm.amount,
    cm.description,
    coalesce(cm.status, 'active')::text,
    (coalesce(cm.status, 'active') = 'active' and cs.closed_at is null and cm.kind in ('income','expense')) as editable,
    (coalesce(cm.status, 'active') = 'active' and cs.closed_at is null and cm.kind in ('income','expense')) as voidable,
    cm.voided_at,
    cm.void_reason,
    cm.updated_at,
    cm.correction_reason,
    (
      select max(al.performed_at)
      from public.cash_movement_audit_logs al
      where al.cash_movement_id = cm.id
    ) as last_audit_at
  from public.cash_movements cm
  join public.cash_sessions cs on cs.id = cm.session_id
  join public.branches b on b.id = cs.branch_id
  left join public.profiles p on p.id = cm.user_id
  where b.business_id = v_profile.business_id
    and b.id = p_branch_id
    and cm.created_at >= p_from
    and cm.created_at < p_to
  order by cm.created_at desc;
end $$;

create or replace function public.corporate_update_cash_movement(
  p_movement_id uuid,
  p_amount numeric,
  p_description text,
  p_reason text
)
returns table(
  movement_id uuid,
  status text,
  amount numeric,
  description text,
  updated_at timestamptz
)
language plpgsql security definer set search_path=public as $$
declare
  v_profile public.profiles%rowtype;
  v_row record;
  v_reason text := trim(coalesce(p_reason, ''));
  v_description text := trim(coalesce(p_description, ''));
  v_old jsonb;
  v_new jsonb;
  v_now timestamptz := now();
begin
  select *
  into v_profile
  from public.profiles
  where id = auth.uid()
    and active
    and role = 'admin';

  if v_profile.id is null then
    raise exception 'No autorizado para editar movimientos de caja';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'El monto debe ser mayor a cero';
  end if;

  if length(v_description) = 0 then
    raise exception 'La descripcion es obligatoria';
  end if;

  if length(v_reason) < 10 then
    raise exception 'El motivo debe tener al menos 10 caracteres';
  end if;

  select
    cm.*,
    cs.branch_id,
    cs.closed_at,
    b.business_id
  into v_row
  from public.cash_movements cm
  join public.cash_sessions cs on cs.id = cm.session_id
  join public.branches b on b.id = cs.branch_id
  where cm.id = p_movement_id
  for update of cm;

  if v_row.id is null then
    raise exception 'El movimiento de caja no existe';
  end if;

  if v_row.business_id <> v_profile.business_id then
    raise exception 'Movimiento no autorizado';
  end if;

  if coalesce(v_row.status, 'active') <> 'active' then
    raise exception 'Solo se pueden editar movimientos activos';
  end if;

  if v_row.kind not in ('income','expense') then
    raise exception 'Solo se pueden editar movimientos manuales';
  end if;

  if v_row.closed_at is not null then
    raise exception 'Las cajas cerradas son solo lectura en esta version';
  end if;

  v_old := jsonb_build_object(
    'amount', v_row.amount,
    'description', v_row.description,
    'status', coalesce(v_row.status, 'active'),
    'kind', v_row.kind,
    'updated_at', v_row.updated_at,
    'correction_reason', v_row.correction_reason
  );

  update public.cash_movements
  set amount = p_amount,
      description = v_description,
      updated_by = auth.uid(),
      updated_at = v_now,
      correction_reason = v_reason
  where id = p_movement_id;

  v_new := jsonb_build_object(
    'amount', p_amount,
    'description', v_description,
    'status', 'active',
    'kind', v_row.kind,
    'updated_at', v_now,
    'correction_reason', v_reason
  );

  insert into public.cash_movement_audit_logs(
    business_id, branch_id, cash_session_id, cash_movement_id, action,
    old_values, new_values, reason, performed_by, performed_at
  )
  values(
    v_row.business_id, v_row.branch_id, v_row.session_id, v_row.id, 'update',
    v_old, v_new, v_reason, auth.uid(), v_now
  );

  return query
  select cm.id, cm.status::text, cm.amount, cm.description, cm.updated_at
  from public.cash_movements cm
  where cm.id = p_movement_id;
end $$;

create or replace function public.corporate_void_cash_movement(
  p_movement_id uuid,
  p_reason text
)
returns table(
  movement_id uuid,
  status text,
  voided_at timestamptz
)
language plpgsql security definer set search_path=public as $$
declare
  v_profile public.profiles%rowtype;
  v_row record;
  v_reason text := trim(coalesce(p_reason, ''));
  v_old jsonb;
  v_new jsonb;
  v_now timestamptz := now();
begin
  select *
  into v_profile
  from public.profiles
  where id = auth.uid()
    and active
    and role = 'admin';

  if v_profile.id is null then
    raise exception 'No autorizado para anular movimientos de caja';
  end if;

  if length(v_reason) < 10 then
    raise exception 'El motivo debe tener al menos 10 caracteres';
  end if;

  select
    cm.*,
    cs.branch_id,
    cs.closed_at,
    b.business_id
  into v_row
  from public.cash_movements cm
  join public.cash_sessions cs on cs.id = cm.session_id
  join public.branches b on b.id = cs.branch_id
  where cm.id = p_movement_id
  for update of cm;

  if v_row.id is null then
    raise exception 'El movimiento de caja no existe';
  end if;

  if v_row.business_id <> v_profile.business_id then
    raise exception 'Movimiento no autorizado';
  end if;

  if coalesce(v_row.status, 'active') <> 'active' then
    raise exception 'Solo se pueden anular movimientos activos';
  end if;

  if v_row.kind not in ('income','expense') then
    raise exception 'Solo se pueden anular movimientos manuales';
  end if;

  if v_row.closed_at is not null then
    raise exception 'Las cajas cerradas son solo lectura en esta version';
  end if;

  v_old := jsonb_build_object(
    'amount', v_row.amount,
    'description', v_row.description,
    'status', coalesce(v_row.status, 'active'),
    'kind', v_row.kind,
    'voided_at', v_row.voided_at,
    'void_reason', v_row.void_reason
  );

  update public.cash_movements
  set status = 'voided',
      voided_at = v_now,
      voided_by = auth.uid(),
      void_reason = v_reason
  where id = p_movement_id;

  v_new := jsonb_build_object(
    'amount', v_row.amount,
    'description', v_row.description,
    'status', 'voided',
    'kind', v_row.kind,
    'voided_at', v_now,
    'void_reason', v_reason
  );

  insert into public.cash_movement_audit_logs(
    business_id, branch_id, cash_session_id, cash_movement_id, action,
    old_values, new_values, reason, performed_by, performed_at
  )
  values(
    v_row.business_id, v_row.branch_id, v_row.session_id, v_row.id, 'void',
    v_old, v_new, v_reason, auth.uid(), v_now
  );

  return query
  select cm.id, cm.status::text, cm.voided_at
  from public.cash_movements cm
  where cm.id = p_movement_id;
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
    coalesce((select sum(cm.amount) from cash_movements cm where cm.session_id=cs.id and cm.kind='income' and coalesce(cm.status,'active')='active'),0),
    coalesce((select sum(cm.amount) from cash_movements cm where cm.session_id=cs.id and cm.kind='expense' and coalesce(cm.status,'active')='active'),0),
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

create or replace function public.cash_closure_movement_details(p_session_id uuid)
returns table(
  movement_id uuid,
  created_at timestamptz,
  user_name text,
  payment_method text,
  kind text,
  amount numeric,
  description text
) language plpgsql security definer set search_path=public as $$
begin
  return query
  select
    cm.id,
    cm.created_at,
    coalesce(p.full_name,'Sin usuario') as user_name,
    'Efectivo'::text as payment_method,
    cm.kind::text,
    cm.amount,
    coalesce(cm.description,'') as description
  from cash_movements cm
  join cash_sessions cs on cs.id=cm.session_id
  join branches b on b.id=cs.branch_id
  left join profiles p on p.id=cm.user_id
  where cm.session_id=p_session_id
    and b.business_id=current_business_id()
    and coalesce(cm.status,'active')='active'
  order by cm.created_at asc;
end $$;

create or replace function public.control_center_movements(p_from timestamptz,p_to timestamptz,p_branch_id uuid default null)
returns table(event_id uuid,event_date timestamptz,branch_id uuid,branch_name text,event_type text,description text,user_name text,amount numeric)
language plpgsql stable security definer set search_path=public as $$
declare v_business uuid;
begin
  select business_id into v_business from profiles where id=auth.uid() and active and role in ('admin','supervisor');
  if v_business is null then raise exception 'No autorizado'; end if;
  return query
  select * from (
    select s.id,s.created_at,s.branch_id,b.name,'Venta'::text,'Venta #'||lpad(s.number::text,5,'0'),p.full_name,s.total
    from sales s join branches b on b.id=s.branch_id join profiles p on p.id=s.cashier_id
    where s.business_id=v_business and s.status='completed' and s.created_at>=p_from and s.created_at<p_to
    union all
    select pu.id,pu.purchased_at,pu.branch_id,b.name,'Compra','Compra '||coalesce(pu.invoice_number,'sin factura'),p.full_name,-pu.total
    from purchases pu join branches b on b.id=pu.branch_id join profiles p on p.id=pu.user_id
    where pu.business_id=v_business and pu.status='received' and pu.purchased_at>=p_from and pu.purchased_at<p_to
    union all
    select r.id,r.created_at,r.branch_id,b.name,'Devolución','Devolución de venta #'||lpad(s.number::text,5,'0'),p.full_name,-r.amount
    from sale_returns r join sales s on s.id=r.sale_id join branches b on b.id=r.branch_id join profiles p on p.id=r.user_id
    where r.business_id=v_business and r.created_at>=p_from and r.created_at<p_to
    union all
    select c.id,c.created_at,c.branch_id,b.name,'Anulación','Anulación de venta #'||lpad(s.number::text,5,'0'),p.full_name,-s.total
    from sale_cancellations c join sales s on s.id=c.sale_id join branches b on b.id=c.branch_id join profiles p on p.id=c.user_id
    where c.business_id=v_business and c.created_at>=p_from and c.created_at<p_to
    union all
    select cm.id,cm.created_at,cs.branch_id,b.name,case when cm.kind='income' then 'Ingreso de caja' else 'Retiro de caja' end,cm.description,p.full_name,case when cm.kind='income' then cm.amount else -cm.amount end
    from cash_movements cm join cash_sessions cs on cs.id=cm.session_id join branches b on b.id=cs.branch_id join profiles p on p.id=cm.user_id
    where b.business_id=v_business and cm.created_at>=p_from and cm.created_at<p_to and coalesce(cm.status,'active')='active'
  ) events where p_branch_id is null or events.branch_id=p_branch_id order by event_date desc limit 1000;
end $$;

grant execute on function public.corporate_cash_movements(uuid,timestamptz,timestamptz) to authenticated;
grant execute on function public.corporate_update_cash_movement(uuid,numeric,text,text) to authenticated;
grant execute on function public.corporate_void_cash_movement(uuid,text) to authenticated;
grant execute on function public.cash_closure_reports(timestamptz,timestamptz,uuid) to authenticated;
grant execute on function public.cash_closure_movement_details(uuid) to authenticated;
grant execute on function public.control_center_movements(timestamptz,timestamptz,uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
