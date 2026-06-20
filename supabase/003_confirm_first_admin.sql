-- Confirma únicamente la cuenta administrativa inicial cuando el correo
-- de Supabase no fue entregado. No desactiva la verificación para otros usuarios.
update auth.users
set
  email_confirmed_at = coalesce(email_confirmed_at, now()),
  updated_at = now()
where email = 'yatdavid326@gmail.com'
  and email_confirmed_at is null;

-- El resultado debe mostrar la cuenta, su perfil y el rol admin.
select
  u.email,
  u.email_confirmed_at,
  p.full_name,
  p.role,
  b.name as business_name,
  br.name as branch_name
from auth.users u
left join public.profiles p on p.id = u.id
left join public.businesses b on b.id = p.business_id
left join public.branches br on br.id = p.branch_id
where u.email = 'yatdavid326@gmail.com';
