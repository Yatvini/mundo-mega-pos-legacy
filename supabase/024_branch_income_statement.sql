-- Migration: 024_branch_income_statement
-- Objective: add a branch-level income statement RPC for Mundo Mega POS Legacy.
-- Execute after 023_fix_business_creation_invitation_atomicity.sql.

begin;

create or replace function public.branch_income_statements(
  p_from timestamptz,
  p_to timestamptz,
  p_branch_id uuid default null
)
returns table(
  branch_id uuid,
  branch_name text,
  period_from timestamptz,
  period_to timestamptz,
  gross_sales numeric,
  returns_total numeric,
  cancellations_total numeric,
  net_sales numeric,
  cost_of_sales numeric,
  gross_profit numeric,
  operating_expenses numeric,
  payroll_expenses numeric,
  cash_negative_differences numeric,
  cash_positive_differences numeric,
  operating_profit numeric,
  gross_margin numeric,
  operating_margin numeric,
  average_ticket numeric,
  transactions bigint,
  products_sold numeric,
  uses_cost_fallback boolean,
  notes text[]
)
language plpgsql
stable
security definer
set search_path=public
as $$
#variable_conflict use_column
declare
  v_profile public.profiles%rowtype;
  v_branch_filter uuid;
  v_period_days numeric;
begin
  if auth.uid() is null then
    raise exception 'Sesion no encontrada';
  end if;

  if p_from is null or p_to is null or p_to <= p_from then
    raise exception 'Rango de fechas invalido';
  end if;

  select pr.*
  into v_profile
  from public.profiles pr
  where pr.id = auth.uid()
    and pr.active;

  if not found then
    raise exception 'Perfil activo no encontrado';
  end if;

  if v_profile.role not in ('admin', 'supervisor') then
    raise exception 'No autorizado para consultar estados de resultados';
  end if;

  if v_profile.role = 'supervisor' then
    if v_profile.branch_id is null then
      raise exception 'Supervisor sin sucursal asignada';
    end if;
    if p_branch_id is not null and p_branch_id <> v_profile.branch_id then
      raise exception 'No autorizado para consultar otra sucursal';
    end if;
    v_branch_filter := v_profile.branch_id;
  else
    v_branch_filter := p_branch_id;
    if v_branch_filter is not null and not exists (
      select 1
      from public.branches br
      where br.id = v_branch_filter
        and br.business_id = v_profile.business_id
    ) then
      raise exception 'Sucursal no encontrada para esta empresa';
    end if;
  end if;

  v_period_days := greatest(extract(epoch from (p_to - p_from)) / 86400, 0);

  return query
  with branch_scope as (
    select
      br.id as branch_id_internal,
      br.name as branch_name_internal
    from public.branches br
    where br.business_id = v_profile.business_id
      and (v_branch_filter is null or br.id = v_branch_filter)
  ), completed_sales as (
    select
      s.branch_id as branch_id_internal,
      sum(s.total)::numeric as gross_sales_internal,
      count(*)::bigint as transactions_internal
    from public.sales s
    join branch_scope bs on bs.branch_id_internal = s.branch_id
    where s.business_id = v_profile.business_id
      and s.status = 'completed'
      and coalesce(s.completed_at, s.created_at) >= p_from
      and coalesce(s.completed_at, s.created_at) < p_to
    group by s.branch_id
  ), sale_costs as (
    select
      s.branch_id as branch_id_internal,
      sum(si.quantity * coalesce(si.unit_cost, pr.cost, 0))::numeric as cost_of_sales_internal,
      sum(si.quantity)::numeric as sold_quantity_internal,
      bool_or(si.unit_cost is null)::boolean as uses_cost_fallback_internal
    from public.sales s
    join branch_scope bs on bs.branch_id_internal = s.branch_id
    join public.sale_items si on si.sale_id = s.id
    left join public.products pr on pr.id = si.product_id and pr.business_id = s.business_id
    where s.business_id = v_profile.business_id
      and s.status = 'completed'
      and coalesce(s.completed_at, s.created_at) >= p_from
      and coalesce(s.completed_at, s.created_at) < p_to
    group by s.branch_id
  ), returns_by_branch as (
    select
      sr.branch_id as branch_id_internal,
      sum(sr.amount)::numeric as returns_total_internal
    from public.sale_returns sr
    join branch_scope bs on bs.branch_id_internal = sr.branch_id
    where sr.business_id = v_profile.business_id
      and sr.created_at >= p_from
      and sr.created_at < p_to
    group by sr.branch_id
  ), returned_items as (
    select
      sr.branch_id as branch_id_internal,
      sum(sri.quantity)::numeric as returned_quantity_internal
    from public.sale_returns sr
    join branch_scope bs on bs.branch_id_internal = sr.branch_id
    join public.sale_return_items sri on sri.return_id = sr.id
    where sr.business_id = v_profile.business_id
      and sr.created_at >= p_from
      and sr.created_at < p_to
    group by sr.branch_id
  ), cancellations_by_branch as (
    select
      sc.branch_id as branch_id_internal,
      sum(s.total)::numeric as cancellations_total_internal
    from public.sale_cancellations sc
    join branch_scope bs on bs.branch_id_internal = sc.branch_id
    join public.sales s on s.id = sc.sale_id
    where sc.business_id = v_profile.business_id
      and sc.created_at >= p_from
      and sc.created_at < p_to
    group by sc.branch_id
  ), payroll_by_branch as (
    select
      ae.branch_id as branch_id_internal,
      (sum(ae.base_salary) * (v_period_days / 30))::numeric as payroll_expenses_internal
    from public.attendance_employees ae
    join branch_scope bs on bs.branch_id_internal = ae.branch_id
    where ae.business_id = v_profile.business_id
      and ae.active
    group by ae.branch_id
  ), cash_differences as (
    select
      cs.branch_id as branch_id_internal,
      sum(greatest(coalesce(cs.expected_amount, 0) - coalesce(cs.closing_amount, 0), 0))::numeric as cash_negative_internal,
      sum(greatest(coalesce(cs.closing_amount, 0) - coalesce(cs.expected_amount, 0), 0))::numeric as cash_positive_internal
    from public.cash_sessions cs
    join branch_scope bs on bs.branch_id_internal = cs.branch_id
    where cs.closed_at is not null
      and cs.closed_at >= p_from
      and cs.closed_at < p_to
    group by cs.branch_id
  ), base_rows as (
    select
      bs.branch_id_internal,
      bs.branch_name_internal,
      coalesce(cs.gross_sales_internal, 0) as gross_sales_internal,
      coalesce(rb.returns_total_internal, 0) as returns_total_internal,
      coalesce(cb.cancellations_total_internal, 0) as cancellations_total_internal,
      coalesce(sc.cost_of_sales_internal, 0) as cost_of_sales_internal,
      coalesce(pb.payroll_expenses_internal, 0) as payroll_expenses_internal,
      coalesce(cd.cash_negative_internal, 0) as cash_negative_internal,
      coalesce(cd.cash_positive_internal, 0) as cash_positive_internal,
      coalesce(cs.transactions_internal, 0) as transactions_internal,
      greatest(coalesce(sc.sold_quantity_internal, 0) - coalesce(ri.returned_quantity_internal, 0), 0) as products_sold_internal,
      coalesce(sc.uses_cost_fallback_internal, false) as uses_cost_fallback_internal
    from branch_scope bs
    left join completed_sales cs on cs.branch_id_internal = bs.branch_id_internal
    left join sale_costs sc on sc.branch_id_internal = bs.branch_id_internal
    left join returns_by_branch rb on rb.branch_id_internal = bs.branch_id_internal
    left join returned_items ri on ri.branch_id_internal = bs.branch_id_internal
    left join cancellations_by_branch cb on cb.branch_id_internal = bs.branch_id_internal
    left join payroll_by_branch pb on pb.branch_id_internal = bs.branch_id_internal
    left join cash_differences cd on cd.branch_id_internal = bs.branch_id_internal
  ), computed_rows as (
    select
      br.*,
      (br.gross_sales_internal - br.returns_total_internal) as net_sales_internal,
      (br.gross_sales_internal - br.returns_total_internal - br.cost_of_sales_internal) as gross_profit_internal
    from base_rows br
  ), final_rows as (
    select
      cr.*,
      0::numeric as operating_expenses_internal,
      (cr.gross_profit_internal - 0 - cr.payroll_expenses_internal - cr.cash_negative_internal + cr.cash_positive_internal) as operating_profit_internal
    from computed_rows cr
  )
  select
    fr.branch_id_internal as branch_id,
    fr.branch_name_internal as branch_name,
    p_from as period_from,
    p_to as period_to,
    fr.gross_sales_internal as gross_sales,
    fr.returns_total_internal as returns_total,
    fr.cancellations_total_internal as cancellations_total,
    fr.net_sales_internal as net_sales,
    fr.cost_of_sales_internal as cost_of_sales,
    fr.gross_profit_internal as gross_profit,
    fr.operating_expenses_internal as operating_expenses,
    fr.payroll_expenses_internal as payroll_expenses,
    fr.cash_negative_internal as cash_negative_differences,
    fr.cash_positive_internal as cash_positive_differences,
    fr.operating_profit_internal as operating_profit,
    case when fr.net_sales_internal > 0 then round((fr.gross_profit_internal / fr.net_sales_internal) * 100, 2) else 0 end as gross_margin,
    case when fr.net_sales_internal > 0 then round((fr.operating_profit_internal / fr.net_sales_internal) * 100, 2) else 0 end as operating_margin,
    case when fr.transactions_internal > 0 then round(fr.net_sales_internal / fr.transactions_internal, 2) else 0 end as average_ticket,
    fr.transactions_internal as transactions,
    fr.products_sold_internal as products_sold,
    fr.uses_cost_fallback_internal as uses_cost_fallback,
    array_remove(array[
      'Gastos operativos no configurados en esta version.',
      'Salarios estimados; no representan nomina contable definitiva.',
      'Anulaciones mostradas como referencia; no se restan de ventas netas porque las ventas anuladas no forman parte de ventas completadas.',
      case when fr.uses_cost_fallback_internal then 'Algunas lineas usaron costo actual del producto como fallback.' end
    ], null)::text[] as notes
  from final_rows fr
  order by fr.net_sales_internal desc, fr.branch_name_internal;
end
$$;

grant execute on function public.branch_income_statements(timestamptz,timestamptz,uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
