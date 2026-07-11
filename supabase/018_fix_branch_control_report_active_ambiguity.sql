-- Migracion: 018_fix_branch_control_report_active_ambiguity
-- Causa: la funcion branch_control_report declara una columna de retorno active
--        y tambien consultaba profiles.active sin alias dentro de PL/pgSQL.
-- Error corregido: 42702 column reference "active" is ambiguous.
-- Ejecutar despues de 017_restore_previous_attendance.sql.

create or replace function public.branch_control_report(p_from timestamptz,p_to timestamptz)
returns table(
  branch_id uuid,branch_name text,active boolean,gross_sales numeric,refunds numeric,net_sales numeric,
  transactions bigint,average_ticket numeric,cost_of_sales numeric,gross_profit numeric,margin numeric,
  inventory_value numeric,low_stock bigint,out_of_stock bigint
) language plpgsql stable security definer set search_path=public as $$
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
    select s.branch_id,sum(s.total)::numeric gross,count(*)::bigint tx
    from sales s where s.business_id=v_business and s.status='completed' and s.created_at>=p_from and s.created_at<p_to group by s.branch_id
  ), costs as (
    select s.branch_id,sum(si.quantity*si.unit_cost)::numeric cost
    from sales s join sale_items si on si.sale_id=s.id
    where s.business_id=v_business and s.status='completed' and s.created_at>=p_from and s.created_at<p_to group by s.branch_id
  ), returned as (
    select r.branch_id,sum(r.amount)::numeric amount
    from sale_returns r where r.business_id=v_business and r.created_at>=p_from and r.created_at<p_to group by r.branch_id
  ), inv as (
    select i.branch_id,sum(i.stock*p.cost)::numeric value,
      count(*) filter(where i.stock<=p.min_stock and i.stock>0)::bigint low,
      count(*) filter(where i.stock<=0)::bigint empty
    from inventory i join products p on p.id=i.product_id
    where p.business_id=v_business and p.active group by i.branch_id
  )
  select b.id,b.name,b.active,coalesce(st.gross,0),coalesce(r.amount,0),
    coalesce(st.gross,0)-coalesce(r.amount,0),coalesce(st.tx,0),
    case when coalesce(st.tx,0)>0 then round((coalesce(st.gross,0)-coalesce(r.amount,0))/st.tx,2) else 0 end,
    coalesce(c.cost,0),(coalesce(st.gross,0)-coalesce(r.amount,0))-coalesce(c.cost,0),
    case when coalesce(st.gross,0)-coalesce(r.amount,0)>0 then round((((coalesce(st.gross,0)-coalesce(r.amount,0))-coalesce(c.cost,0))/(coalesce(st.gross,0)-coalesce(r.amount,0)))*100,1) else 0 end,
    coalesce(i.value,0),coalesce(i.low,0),coalesce(i.empty,0)
  from branches b left join sale_totals st on st.branch_id=b.id left join costs c on c.branch_id=b.id
  left join returned r on r.branch_id=b.id left join inv i on i.branch_id=b.id
  where b.business_id=v_business order by net_sales desc,b.name;
end $$;
grant execute on function branch_control_report(timestamptz,timestamptz) to authenticated;
