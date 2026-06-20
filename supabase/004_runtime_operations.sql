-- Operaciones atómicas de venta y compra.
create or replace function public.complete_sale(p_sale_id uuid, p_payments jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare item record; pay jsonb; v_branch uuid; v_business uuid; v_previous numeric; v_new numeric;
begin
  select branch_id,business_id into v_branch,v_business from sales
  where id=p_sale_id and business_id=current_business_id() and status='draft' for update;
  if not found then raise exception 'Venta no encontrada o ya procesada'; end if;
  for item in select * from sale_items where sale_id=p_sale_id loop
    update inventory set stock=stock-item.quantity,updated_at=now()
    where branch_id=v_branch and product_id=item.product_id and stock>=item.quantity
    returning stock+item.quantity,stock into v_previous,v_new;
    if not found then raise exception 'Existencia insuficiente para %',item.product_name; end if;
    insert into inventory_movements(business_id,branch_id,product_id,user_id,type,quantity,previous_stock,new_stock,reference_id)
    values(v_business,v_branch,item.product_id,auth.uid(),'sale',-item.quantity,v_previous,v_new,p_sale_id);
  end loop;
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into sale_payments(sale_id,method,amount,reference)
    values(p_sale_id,(pay->>'method')::payment_method,(pay->>'amount')::numeric,pay->>'reference');
  end loop;
  if (select coalesce(sum(amount),0) from sale_payments where sale_id=p_sale_id) < (select total from sales where id=p_sale_id)
  then raise exception 'Pago insuficiente'; end if;
  update sales set status='completed',completed_at=now() where id=p_sale_id;
end $$;

create or replace function public.receive_purchase(
  p_branch_id uuid, p_supplier_name text, p_invoice_number text,
  p_payment_status text, p_items jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_business uuid; v_supplier uuid; v_purchase uuid; v_total numeric:=0; item jsonb; v_previous numeric; v_new numeric;
begin
  select business_id into v_business from profiles where id=auth.uid();
  if v_business is null or not exists(select 1 from branches where id=p_branch_id and business_id=v_business)
  then raise exception 'Sucursal no autorizada'; end if;
  select id into v_supplier from suppliers where business_id=v_business and lower(name)=lower(trim(p_supplier_name)) limit 1;
  if v_supplier is null then insert into suppliers(business_id,name) values(v_business,trim(p_supplier_name)) returning id into v_supplier; end if;
  select coalesce(sum((x->>'quantity')::numeric*(x->>'unit_cost')::numeric),0) into v_total from jsonb_array_elements(p_items) x;
  insert into purchases(business_id,branch_id,supplier_id,user_id,invoice_number,total,subtotal,payment_status,status)
  values(v_business,p_branch_id,v_supplier,auth.uid(),nullif(p_invoice_number,''),v_total,v_total,p_payment_status,'received') returning id into v_purchase;
  for item in select * from jsonb_array_elements(p_items) loop
    insert into purchase_items(purchase_id,product_id,quantity,unit_cost,total)
    values(v_purchase,(item->>'product_id')::uuid,(item->>'quantity')::numeric,(item->>'unit_cost')::numeric,(item->>'quantity')::numeric*(item->>'unit_cost')::numeric);
    insert into inventory(branch_id,product_id,stock) values(p_branch_id,(item->>'product_id')::uuid,(item->>'quantity')::numeric)
    on conflict(branch_id,product_id) do update set stock=inventory.stock+excluded.stock,updated_at=now()
    returning stock-(item->>'quantity')::numeric,stock into v_previous,v_new;
    update products set cost=(item->>'unit_cost')::numeric,updated_at=now() where id=(item->>'product_id')::uuid and business_id=v_business;
    insert into inventory_movements(business_id,branch_id,product_id,user_id,type,quantity,previous_stock,new_stock,reference_id)
    values(v_business,p_branch_id,(item->>'product_id')::uuid,auth.uid(),'purchase',(item->>'quantity')::numeric,v_previous,v_new,v_purchase);
  end loop;
  return v_purchase;
end $$;

grant execute on function public.complete_sale(uuid,jsonb) to authenticated;
grant execute on function public.receive_purchase(uuid,text,text,text,jsonb) to authenticated;
