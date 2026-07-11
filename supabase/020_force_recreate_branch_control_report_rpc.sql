-- Migracion: 020_force_recreate_branch_control_report_rpc
-- Objetivo: forzar la recreacion completa de la RPC branch_control_report.
-- Causa: PostgREST sigue respondiendo con error 42702 despues de CREATE OR REPLACE.
-- Ejecutar despues de 019_rewrite_branch_control_report_avoid_output_conflicts.sql.

begin;

drop function if exists public.branch_control_report(timestamptz, timestamptz);

create function public.branch_control_report(p_from timestamptz,p_to timestamptz)
returns table(
  branch_id uuid,branch_name text,active boolean,gross_sales numeric,refunds numeric,net_sales numeric,
  transactions bigint,average_ticket numeric,cost_of_sales numeric,gross_profit numeric,margin numeric,
  inventory_value numeric,low_stock bigint,out_of_stock bigint
) language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare v_business uuid;
begin
  select pr.business_id into v_business
  from public.profiles pr
  where pr.id = auth.uid()
    and pr.active
    and pr.role in ('admin','supervisor');
  if v_business is null then raise exception 'No autorizado para consultar el centro de control'; end if;
  return query
  with sale_totals as (
    select
      s.branch_id as branch_id_internal,
      sum(s.total)::numeric as gross_sales_internal,
      count(*)::bigint as transactions_internal
    from public.sales s
    where s.business_id=v_business and s.status='completed' and s.created_at>=p_from and s.created_at<p_to
    group by s.branch_id
  ), costs as (
    select
      s.branch_id as branch_id_internal,
      sum(si.quantity*si.unit_cost)::numeric as cost_of_sales_internal
    from public.sales s
    join public.sale_items si on si.sale_id=s.id
    where s.business_id=v_business and s.status='completed' and s.created_at>=p_from and s.created_at<p_to
    group by s.branch_id
  ), returned as (
    select
      r.branch_id as branch_id_internal,
      sum(r.amount)::numeric as refunds_internal
    from public.sale_returns r
    where r.business_id=v_business and r.created_at>=p_from and r.created_at<p_to
    group by r.branch_id
  ), inv as (
    select
      i.branch_id as branch_id_internal,
      sum(i.stock*p.cost)::numeric as inventory_value_internal,
      count(*) filter(where i.stock<=p.min_stock and i.stock>0)::bigint as low_stock_internal,
      count(*) filter(where i.stock<=0)::bigint as out_of_stock_internal
    from public.inventory i
    join public.products p on p.id=i.product_id
    where p.business_id=v_business and p.active
    group by i.branch_id
  ), report_rows as (
    select
      b.id as branch_id_internal,
      b.name as branch_name_internal,
      b.active as branch_active_internal,
      coalesce(st.gross_sales_internal,0) as gross_sales_internal,
      coalesce(rt.refunds_internal,0) as refunds_internal,
      coalesce(st.gross_sales_internal,0)-coalesce(rt.refunds_internal,0) as net_sales_internal,
      coalesce(st.transactions_internal,0) as transactions_internal,
      case when coalesce(st.transactions_internal,0)>0 then round((coalesce(st.gross_sales_internal,0)-coalesce(rt.refunds_internal,0))/st.transactions_internal,2) else 0 end as average_ticket_internal,
      coalesce(c.cost_of_sales_internal,0) as cost_of_sales_internal,
      (coalesce(st.gross_sales_internal,0)-coalesce(rt.refunds_internal,0))-coalesce(c.cost_of_sales_internal,0) as gross_profit_internal,
      case when coalesce(st.gross_sales_internal,0)-coalesce(rt.refunds_internal,0)>0 then round((((coalesce(st.gross_sales_internal,0)-coalesce(rt.refunds_internal,0))-coalesce(c.cost_of_sales_internal,0))/(coalesce(st.gross_sales_internal,0)-coalesce(rt.refunds_internal,0)))*100,1) else 0 end as margin_internal,
      coalesce(i.inventory_value_internal,0) as inventory_value_internal,
      coalesce(i.low_stock_internal,0) as low_stock_internal,
      coalesce(i.out_of_stock_internal,0) as out_of_stock_internal
    from public.branches b
    left join sale_totals st on st.branch_id_internal=b.id
    left join costs c on c.branch_id_internal=b.id
    left join returned rt on rt.branch_id_internal=b.id
    left join inv i on i.branch_id_internal=b.id
    where b.business_id=v_business
  )
  select
    rr.branch_id_internal as branch_id,
    rr.branch_name_internal as branch_name,
    rr.branch_active_internal as active,
    rr.gross_sales_internal as gross_sales,
    rr.refunds_internal as refunds,
    rr.net_sales_internal as net_sales,
    rr.transactions_internal as transactions,
    rr.average_ticket_internal as average_ticket,
    rr.cost_of_sales_internal as cost_of_sales,
    rr.gross_profit_internal as gross_profit,
    rr.margin_internal as margin,
    rr.inventory_value_internal as inventory_value,
    rr.low_stock_internal as low_stock,
    rr.out_of_stock_internal as out_of_stock
  from report_rows rr
  order by rr.net_sales_internal desc,rr.branch_name_internal;
end $$;

grant execute on function public.branch_control_report(timestamptz,timestamptz) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
