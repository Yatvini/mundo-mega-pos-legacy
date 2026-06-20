-- Mercadito POS · esquema inicial para Supabase/PostgreSQL
create extension if not exists "uuid-ossp";

create type public.user_role as enum ('admin','supervisor','cashier','warehouse');
create type public.sale_status as enum ('draft','completed','cancelled');
create type public.payment_method as enum ('cash','card','transfer','credit');
create type public.movement_type as enum ('purchase','sale','adjustment_in','adjustment_out','return_in','return_out');

create table public.businesses (
  id uuid primary key default uuid_generate_v4(), name text not null, legal_name text,
  tax_id text, phone text, address text, currency char(3) not null default 'GTQ',
  timezone text not null default 'America/Guatemala', created_at timestamptz not null default now()
);
create table public.branches (
  id uuid primary key default uuid_generate_v4(), business_id uuid not null references businesses on delete cascade,
  name text not null, address text, phone text, active boolean not null default true, created_at timestamptz not null default now()
);
create table public.profiles (
  id uuid primary key references auth.users on delete cascade, business_id uuid not null references businesses on delete cascade,
  branch_id uuid references branches, full_name text not null, role user_role not null default 'cashier', active boolean not null default true
);
create table public.categories (
  id uuid primary key default uuid_generate_v4(), business_id uuid not null references businesses on delete cascade,
  name text not null, color text, active boolean not null default true, unique(business_id,name)
);
create table public.products (
  id uuid primary key default uuid_generate_v4(), business_id uuid not null references businesses on delete cascade,
  category_id uuid references categories on delete set null, name text not null, sku text not null, barcode text,
  unit text not null default 'unidad', cost numeric(12,2) not null default 0 check(cost>=0),
  price numeric(12,2) not null check(price>=0), tax_rate numeric(5,2) not null default 0,
  min_stock numeric(12,3) not null default 0, active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(business_id,sku)
);
create unique index products_barcode_business_idx on products(business_id,barcode) where barcode is not null;
create table public.inventory (
  branch_id uuid references branches on delete cascade, product_id uuid references products on delete cascade,
  stock numeric(12,3) not null default 0, updated_at timestamptz not null default now(), primary key(branch_id,product_id)
);
create table public.customers (
  id uuid primary key default uuid_generate_v4(), business_id uuid not null references businesses on delete cascade,
  name text not null, tax_id text, phone text, email text, address text, points integer not null default 0,
  active boolean not null default true, created_at timestamptz not null default now()
);
create table public.suppliers (
  id uuid primary key default uuid_generate_v4(), business_id uuid not null references businesses on delete cascade,
  name text not null, tax_id text, phone text, email text, address text, contact_name text,
  active boolean not null default true, created_at timestamptz not null default now()
);
create table public.cash_sessions (
  id uuid primary key default uuid_generate_v4(), branch_id uuid not null references branches,
  user_id uuid not null references profiles, opened_at timestamptz not null default now(), closed_at timestamptz,
  opening_amount numeric(12,2) not null default 0, expected_amount numeric(12,2), closing_amount numeric(12,2), notes text
);
create table public.cash_movements (
  id uuid primary key default uuid_generate_v4(), session_id uuid not null references cash_sessions on delete cascade,
  user_id uuid not null references profiles, kind text not null check(kind in ('income','expense')),
  amount numeric(12,2) not null check(amount>0), description text not null, created_at timestamptz not null default now()
);
create table public.sales (
  id uuid primary key default uuid_generate_v4(), business_id uuid not null references businesses,
  branch_id uuid not null references branches, session_id uuid references cash_sessions, customer_id uuid references customers,
  cashier_id uuid not null references profiles, number bigint generated always as identity, status sale_status not null default 'draft',
  subtotal numeric(12,2) not null default 0, discount numeric(12,2) not null default 0,
  tax numeric(12,2) not null default 0, total numeric(12,2) not null default 0,
  created_at timestamptz not null default now(), completed_at timestamptz
);
create table public.sale_items (
  id uuid primary key default uuid_generate_v4(), sale_id uuid not null references sales on delete cascade,
  product_id uuid not null references products, product_name text not null, quantity numeric(12,3) not null check(quantity>0),
  unit_cost numeric(12,2) not null, unit_price numeric(12,2) not null,
  discount numeric(12,2) not null default 0, tax numeric(12,2) not null default 0, total numeric(12,2) not null
);
create table public.sale_payments (
  id uuid primary key default uuid_generate_v4(), sale_id uuid not null references sales on delete cascade,
  method payment_method not null, amount numeric(12,2) not null check(amount>0), reference text, created_at timestamptz not null default now()
);
create table public.purchases (
  id uuid primary key default uuid_generate_v4(), business_id uuid not null references businesses, branch_id uuid not null references branches,
  supplier_id uuid references suppliers, user_id uuid not null references profiles, invoice_number text,
  subtotal numeric(12,2) not null default 0, tax numeric(12,2) not null default 0, total numeric(12,2) not null default 0,
  status text not null default 'received' check(status in ('draft','ordered','received','cancelled')),
  payment_status text not null default 'paid' check(payment_status in ('paid','pending','partial')),
  purchased_at timestamptz not null default now(), due_date date
);
create table public.purchase_items (
  id uuid primary key default uuid_generate_v4(), purchase_id uuid not null references purchases on delete cascade,
  product_id uuid not null references products, quantity numeric(12,3) not null check(quantity>0),
  unit_cost numeric(12,2) not null, tax numeric(12,2) not null default 0, total numeric(12,2) not null
);
create table public.inventory_movements (
  id uuid primary key default uuid_generate_v4(), business_id uuid not null references businesses,
  branch_id uuid not null references branches, product_id uuid not null references products,
  user_id uuid references profiles, type movement_type not null, quantity numeric(12,3) not null,
  previous_stock numeric(12,3) not null, new_stock numeric(12,3) not null, reference_id uuid, notes text,
  created_at timestamptz not null default now()
);

create or replace function public.current_business_id() returns uuid language sql stable security definer
set search_path=public as $$ select business_id from profiles where id=auth.uid() $$;

alter table businesses enable row level security; alter table branches enable row level security;
alter table profiles enable row level security; alter table categories enable row level security;
alter table products enable row level security; alter table inventory enable row level security;
alter table customers enable row level security; alter table suppliers enable row level security;
alter table cash_sessions enable row level security; alter table cash_movements enable row level security;
alter table sales enable row level security; alter table sale_items enable row level security;
alter table sale_payments enable row level security; alter table purchases enable row level security;
alter table purchase_items enable row level security; alter table inventory_movements enable row level security;

create policy "business_members_read_products" on products for select using (business_id=current_business_id());
create policy "business_members_write_products" on products for all using (business_id=current_business_id()) with check (business_id=current_business_id());
create policy "business_members_categories" on categories for all using (business_id=current_business_id()) with check (business_id=current_business_id());
create policy "business_members_customers" on customers for all using (business_id=current_business_id()) with check (business_id=current_business_id());
create policy "business_members_suppliers" on suppliers for all using (business_id=current_business_id()) with check (business_id=current_business_id());
create policy "business_members_sales" on sales for all using (business_id=current_business_id()) with check (business_id=current_business_id());
create policy "business_members_purchases" on purchases for all using (business_id=current_business_id()) with check (business_id=current_business_id());
create policy "business_members_movements" on inventory_movements for select using (business_id=current_business_id());
create policy "profile_own_business" on profiles for select using (business_id=current_business_id());
create policy "business_branch_access" on branches for select using (business_id=current_business_id());
create policy "business_info_access" on businesses for select using (id=current_business_id());
create policy "inventory_access" on inventory for all using (exists(select 1 from branches b where b.id=branch_id and b.business_id=current_business_id()));
create policy "sale_items_access" on sale_items for all using (exists(select 1 from sales s where s.id=sale_id and s.business_id=current_business_id()));
create policy "sale_payments_access" on sale_payments for all using (exists(select 1 from sales s where s.id=sale_id and s.business_id=current_business_id()));
create policy "purchase_items_access" on purchase_items for all using (exists(select 1 from purchases p where p.id=purchase_id and p.business_id=current_business_id()));
create policy "cash_sessions_access" on cash_sessions for all using (exists(select 1 from branches b where b.id=branch_id and b.business_id=current_business_id()));
create policy "cash_movements_access" on cash_movements for all using (exists(select 1 from cash_sessions c join branches b on b.id=c.branch_id where c.id=session_id and b.business_id=current_business_id()));

create or replace function public.complete_sale(p_sale_id uuid, p_payments jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare item record; pay jsonb; v_branch uuid; v_business uuid;
begin
  select branch_id,business_id into v_branch,v_business from sales
  where id=p_sale_id and business_id=current_business_id() and status='draft' for update;
  if not found then raise exception 'Venta no encontrada o ya procesada'; end if;
  for item in select * from sale_items where sale_id=p_sale_id loop
    update inventory set stock=stock-item.quantity,updated_at=now()
    where branch_id=v_branch and product_id=item.product_id and stock>=item.quantity
    returning stock+item.quantity,stock into item.previous_stock,item.new_stock;
    if not found then raise exception 'Existencia insuficiente para %',item.product_name; end if;
    insert into inventory_movements(business_id,branch_id,product_id,user_id,type,quantity,previous_stock,new_stock,reference_id)
    values(v_business,v_branch,item.product_id,auth.uid(),'sale',-item.quantity,item.previous_stock,item.new_stock,p_sale_id);
  end loop;
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into sale_payments(sale_id,method,amount,reference) values(p_sale_id,(pay->>'method')::payment_method,(pay->>'amount')::numeric,pay->>'reference');
  end loop;
  if (select coalesce(sum(amount),0) from sale_payments where sale_id=p_sale_id) < (select total from sales where id=p_sale_id)
  then raise exception 'Pago insuficiente'; end if;
  update sales set status='completed',completed_at=now() where id=p_sale_id;
end $$;

create index sales_business_date_idx on sales(business_id,created_at desc);
create index inventory_movements_product_idx on inventory_movements(product_id,created_at desc);
create index products_search_idx on products using gin(to_tsvector('spanish',name||' '||sku));
