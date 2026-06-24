create or replace function public.attendance_seed_defaults(p_business_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  insert into attendance_categories(business_id,name,kind,sort_order)
  select p_business_id,'Inicio de jornada','start_shift',10
  where not exists(select 1 from attendance_categories where business_id=p_business_id and kind='start_shift');

  insert into attendance_categories(business_id,name,kind,sort_order)
  select p_business_id,'Ir a comer','lunch_out',20
  where not exists(select 1 from attendance_categories where business_id=p_business_id and kind='lunch_out');

  insert into attendance_categories(business_id,name,kind,sort_order)
  select p_business_id,'Regresando de comer','lunch_in',30
  where not exists(select 1 from attendance_categories where business_id=p_business_id and kind='lunch_in');

  insert into attendance_categories(business_id,name,kind,sort_order)
  select p_business_id,'Terminar dia','end_shift',40
  where not exists(select 1 from attendance_categories where business_id=p_business_id and kind='end_shift');

  insert into attendance_categories(business_id,name,kind,sort_order)
  select p_business_id,'Medio turno','custom',50
  where not exists(select 1 from attendance_categories where business_id=p_business_id and lower(name) in ('medio turno','medio dia','medio día'));
end $$;

insert into attendance_categories(business_id,name,kind,sort_order)
select b.id,'Medio turno','custom',50
from businesses b
where not exists(select 1 from attendance_categories c where c.business_id=b.id and lower(c.name) in ('medio turno','medio dia','medio día'));
