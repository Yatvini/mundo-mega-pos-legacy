-- Corrige la creación de empresas en instalaciones donde unaccent está en el
-- esquema extensions y no es visible dentro del search_path seguro de la RPC.
create or replace function public.platform_create_business(
  p_name text,p_legal_name text,p_industry text,p_admin_email text,p_admin_name text default null,
  p_plan text default 'starter',p_slogan text default null,p_primary_color text default '#155b3d',
  p_accent_color text default '#c9f45c'
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_business uuid; v_slug text; v_modules jsonb;
begin
  if not is_platform_admin() then raise exception 'Acceso exclusivo del administrador de plataforma'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'El nombre de la empresa es obligatorio'; end if;
  if p_admin_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then raise exception 'Correo del administrador inválido'; end if;
  if p_industry not in ('retail','minimarket','pharmacy','hardware','clothing','restaurant','services','other') then raise exception 'Nicho no válido'; end if;
  if p_plan not in ('starter','business','enterprise') then raise exception 'Plan no válido'; end if;
  if exists(select 1 from auth.users where lower(email)=lower(p_admin_email)) then
    raise exception 'Ese correo ya tiene una cuenta. Use otro correo para el administrador de la empresa.';
  end if;
  if exists(select 1 from business_admin_invitations where lower(email)=lower(p_admin_email) and accepted_at is null) then
    raise exception 'Ya existe una invitación pendiente para ese correo';
  end if;

  -- La parte aleatoria garantiza unicidad incluso cuando el nombre lleva tildes.
  v_slug:=trim(both '-' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g'));
  if v_slug='' then v_slug:='empresa'; end if;
  v_slug:=v_slug||'-'||substr(replace(gen_random_uuid()::text,'-',''),1,6);

  v_modules:=case when p_industry='restaurant' then
    '{"pos":true,"inventory":true,"purchases":true,"customers":true,"cash":true,"reports":true,"branches":true,"tables":true,"recipes":true}'::jsonb
  else '{"pos":true,"inventory":true,"purchases":true,"customers":true,"cash":true,"reports":true,"branches":true,"returns":true}'::jsonb end;

  insert into businesses(name,legal_name,slug,industry,slogan,primary_color,accent_color,plan,status,modules,max_branches,max_users)
  values(trim(p_name),coalesce(nullif(trim(p_legal_name),''),trim(p_name)),v_slug,p_industry,nullif(trim(p_slogan),''),p_primary_color,p_accent_color,p_plan,'pending',v_modules,
    case p_plan when 'starter' then 1 when 'business' then 5 else 100 end,
    case p_plan when 'starter' then 5 when 'business' then 30 else 500 end)
  returning id into v_business;

  insert into branches(business_id,name) values(v_business,'Sucursal Central');
  insert into business_admin_invitations(business_id,email,full_name,invited_by)
  values(v_business,lower(trim(p_admin_email)),nullif(trim(p_admin_name),''),auth.uid());
  return v_business;
end $$;

grant execute on function public.platform_create_business(text,text,text,text,text,text,text,text,text) to authenticated;
