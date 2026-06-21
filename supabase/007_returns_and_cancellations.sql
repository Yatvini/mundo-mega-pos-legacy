-- Anulaciones completas y devoluciones parciales con reposición de inventario.
create table public.sale_cancellations (
  id uuid primary key default uuid_generate_v4(), sale_id uuid not null unique references sales,
  business_id uuid not null references businesses, branch_id uuid not null references branches,
  user_id uuid not null references profiles, reason text not null, created_at timestamptz not null default now()
);
create table public.sale_returns (
  id uuid primary key default uuid_generate_v4(), sale_id uuid not null references sales,
  business_id uuid not null references businesses, branch_id uuid not null references branches,
  user_id uuid not null references profiles, amount numeric(12,2) not null check(amount>0),
  reason text not null, created_at timestamptz not null default now()
);
create table public.sale_return_items (
  id uuid primary key default uuid_generate_v4(), return_id uuid not null references sale_returns on delete cascade,
  sale_item_id uuid not null references sale_items, product_id uuid not null references products,
  quantity numeric(12,3) not null check(quantity>0), amount numeric(12,2) not null check(amount>=0)
);
alter table sale_cancellations enable row level security;
alter table sale_returns enable row level security;
alter table sale_return_items enable row level security;
create policy "members_read_cancellations" on sale_cancellations for select using(business_id=current_business_id());
create policy "members_read_returns" on sale_returns for select using(business_id=current_business_id());
create policy "members_read_return_items" on sale_return_items for select using(exists(select 1 from sale_returns r where r.id=return_id and r.business_id=current_business_id()));

create or replace function public.cancel_sale(p_sale_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_sale sales%rowtype; item record; v_previous numeric; v_new numeric;
begin
  if not has_any_role(array['admin','supervisor']::user_role[]) then raise exception 'No autorizado para anular ventas'; end if;
  if length(trim(p_reason))<3 then raise exception 'Indica el motivo de la anulación'; end if;
  select * into v_sale from sales where id=p_sale_id and business_id=current_business_id() and status='completed' for update;
  if not found then raise exception 'La venta no existe o ya fue anulada'; end if;
  if exists(select 1 from sale_returns where sale_id=p_sale_id) then raise exception 'No puedes anular una venta que ya tiene devoluciones'; end if;
  for item in select * from sale_items where sale_id=p_sale_id loop
    update inventory set stock=stock+item.quantity,updated_at=now() where branch_id=v_sale.branch_id and product_id=item.product_id
    returning stock-item.quantity,stock into v_previous,v_new;
    insert into inventory_movements(business_id,branch_id,product_id,user_id,type,quantity,previous_stock,new_stock,reference_id,notes)
    values(v_sale.business_id,v_sale.branch_id,item.product_id,auth.uid(),'return_in',item.quantity,v_previous,v_new,p_sale_id,'Anulación: '||trim(p_reason));
  end loop;
  insert into sale_cancellations(sale_id,business_id,branch_id,user_id,reason)
  values(p_sale_id,v_sale.business_id,v_sale.branch_id,auth.uid(),trim(p_reason));
  update sales set status='cancelled' where id=p_sale_id;
end $$;

create or replace function public.return_sale(p_sale_id uuid,p_reason text,p_items jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_sale sales%rowtype; v_return uuid; req jsonb; item sale_items%rowtype; v_qty numeric; v_already numeric; v_amount numeric:=0; v_line_amount numeric; v_previous numeric; v_new numeric;
begin
  if not has_any_role(array['admin','supervisor']::user_role[]) then raise exception 'No autorizado para devolver ventas'; end if;
  if length(trim(p_reason))<3 then raise exception 'Indica el motivo de la devolución'; end if;
  select * into v_sale from sales where id=p_sale_id and business_id=current_business_id() and status='completed' for update;
  if not found then raise exception 'La venta no existe o está anulada'; end if;
  if jsonb_array_length(p_items)=0 then raise exception 'Selecciona al menos un producto'; end if;
  insert into sale_returns(sale_id,business_id,branch_id,user_id,amount,reason)
  values(p_sale_id,v_sale.business_id,v_sale.branch_id,auth.uid(),0.01,trim(p_reason)) returning id into v_return;
  for req in select * from jsonb_array_elements(p_items) loop
    v_qty:=(req->>'quantity')::numeric;
    select * into item from sale_items where id=(req->>'sale_item_id')::uuid and sale_id=p_sale_id;
    if not found or v_qty<=0 then raise exception 'Producto de devolución inválido'; end if;
    select coalesce(sum(ri.quantity),0) into v_already from sale_return_items ri join sale_returns r on r.id=ri.return_id where r.sale_id=p_sale_id and ri.sale_item_id=item.id;
    if v_already+v_qty>item.quantity then raise exception 'La cantidad devuelta supera la cantidad vendida de %',item.product_name; end if;
    v_line_amount:=round((item.total/item.quantity)*v_qty,2);v_amount:=v_amount+v_line_amount;
    insert into sale_return_items(return_id,sale_item_id,product_id,quantity,amount) values(v_return,item.id,item.product_id,v_qty,v_line_amount);
    update inventory set stock=stock+v_qty,updated_at=now() where branch_id=v_sale.branch_id and product_id=item.product_id
    returning stock-v_qty,stock into v_previous,v_new;
    insert into inventory_movements(business_id,branch_id,product_id,user_id,type,quantity,previous_stock,new_stock,reference_id,notes)
    values(v_sale.business_id,v_sale.branch_id,item.product_id,auth.uid(),'return_in',v_qty,v_previous,v_new,v_return,'Devolución: '||trim(p_reason));
  end loop;
  update sale_returns set amount=v_amount where id=v_return;
  return v_return;
exception when others then raise;
end $$;

grant execute on function cancel_sale(uuid,text) to authenticated;
grant execute on function return_sale(uuid,text,jsonb) to authenticated;
create index sale_returns_sale_idx on sale_returns(sale_id,created_at desc);
