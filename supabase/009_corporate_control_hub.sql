-- Portal corporativo: auditoría de movimientos e inventario consolidado.
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
    where b.business_id=v_business and cm.created_at>=p_from and cm.created_at<p_to
  ) events where p_branch_id is null or events.branch_id=p_branch_id order by event_date desc limit 1000;
end $$;

create or replace function public.control_center_inventory()
returns table(product_id uuid,product_name text,sku text,category text,total_stock numeric,min_stock numeric,cost numeric,inventory_value numeric,stock_by_branch jsonb)
language plpgsql stable security definer set search_path=public as $$
declare v_business uuid;
begin
  select business_id into v_business from profiles where id=auth.uid() and active and role in ('admin','supervisor');
  if v_business is null then raise exception 'No autorizado'; end if;
  return query
  select p.id,p.name,p.sku,coalesce(c.name,'Sin categoría'),sum(coalesce(i.stock,0)),p.min_stock,p.cost,
    sum(coalesce(i.stock,0)*p.cost),jsonb_object_agg(b.name,coalesce(i.stock,0) order by b.name)
  from products p cross join branches b
  left join inventory i on i.product_id=p.id and i.branch_id=b.id
  left join categories c on c.id=p.category_id
  where p.business_id=v_business and p.active and b.business_id=v_business and b.active
  group by p.id,p.name,p.sku,c.name,p.min_stock,p.cost order by p.name;
end $$;
grant execute on function control_center_movements(timestamptz,timestamptz,uuid) to authenticated;
grant execute on function control_center_inventory() to authenticated;
