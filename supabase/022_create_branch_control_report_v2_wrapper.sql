begin;

drop function if exists public.branch_control_report_v2(timestamptz, timestamptz);

create function public.branch_control_report_v2(
  p_from timestamptz,
  p_to timestamptz
)
returns table(
  branch_id uuid,
  branch_name text,
  active boolean,
  gross_sales numeric,
  refunds numeric,
  net_sales numeric,
  transactions bigint,
  average_ticket numeric,
  cost_of_sales numeric,
  gross_profit numeric,
  margin numeric,
  inventory_value numeric,
  low_stock bigint,
  out_of_stock bigint
)
language sql
security definer
set search_path to 'public'
as $$
  select *
  from public.branch_control_report(p_from, p_to);
$$;

grant execute on function public.branch_control_report_v2(timestamptz, timestamptz) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
