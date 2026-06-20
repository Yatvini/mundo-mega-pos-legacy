-- Crea automáticamente negocio, sucursal y perfil al registrar un usuario.
-- Ejecutar después de schema.sql.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_business_id uuid;
  v_branch_id uuid;
begin
  insert into public.businesses(name, legal_name)
  values(
    coalesce(nullif(new.raw_user_meta_data->>'business_name',''), 'Mi minimarket'),
    coalesce(nullif(new.raw_user_meta_data->>'business_name',''), 'Mi minimarket')
  ) returning id into v_business_id;

  insert into public.branches(business_id, name)
  values(v_business_id, 'Sucursal Central') returning id into v_branch_id;

  insert into public.profiles(id, business_id, branch_id, full_name, role)
  values(
    new.id,
    v_business_id,
    v_branch_id,
    coalesce(nullif(new.raw_user_meta_data->>'full_name',''), split_part(new.email,'@',1)),
    'admin'
  );

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Permite al usuario consultar su propio perfil inmediatamente después de iniciar sesión.
drop policy if exists "profile_own_business" on public.profiles;
create policy "profiles_same_business" on public.profiles
for select using (
  id = auth.uid()
  or business_id = public.current_business_id()
);

grant execute on function public.current_business_id() to authenticated;
