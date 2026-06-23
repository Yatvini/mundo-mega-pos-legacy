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
  order by cm.created_at asc;
end $$;

grant execute on function public.cash_closure_movement_details(uuid) to authenticated;
