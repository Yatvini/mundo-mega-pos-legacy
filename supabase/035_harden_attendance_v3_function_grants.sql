-- 035_harden_attendance_v3_function_grants.sql
-- Endurece permisos RPC de Asistencia V3.
-- Ejecutar despues de 034_attendance_custom_movements_v3.sql.
-- No modifica tablas, datos, RLS ni logica funcional.

begin;

revoke all on function public.attendance_v3_admin_actor() from public, anon;
revoke all on function public.attendance_v3_admin_initialize_defaults() from public, anon;
revoke all on function public.attendance_v3_admin_list_movements() from public, anon;
revoke all on function public.attendance_v3_admin_create_movement(text,text,text,integer,text,text,boolean) from public, anon;
revoke all on function public.attendance_v3_admin_update_movement(uuid,text,text,text,boolean,integer,text,text,boolean) from public, anon;
revoke all on function public.attendance_v3_create_reader_token(uuid,text) from public, anon;
revoke all on function public.attendance_v3_employee_token_context(text) from public, anon;
revoke all on function public.attendance_v3_reader_context(text) from public, anon;
revoke all on function public.attendance_v3_validate_employee(text,text) from public, anon;
revoke all on function public.attendance_v3_record_movement(text,text,uuid,text) from public, anon;
revoke all on function public.attendance_v3_report(date,date,uuid) from public, anon;

grant execute on function public.attendance_v3_admin_actor() to authenticated, service_role;
grant execute on function public.attendance_v3_admin_initialize_defaults() to authenticated, service_role;
grant execute on function public.attendance_v3_admin_list_movements() to authenticated, service_role;
grant execute on function public.attendance_v3_admin_create_movement(text,text,text,integer,text,text,boolean) to authenticated, service_role;
grant execute on function public.attendance_v3_admin_update_movement(uuid,text,text,text,boolean,integer,text,text,boolean) to authenticated, service_role;
grant execute on function public.attendance_v3_create_reader_token(uuid,text) to authenticated, service_role;
grant execute on function public.attendance_v3_report(date,date,uuid) to authenticated, service_role;

grant execute on function public.attendance_v3_employee_token_context(text) to service_role;
grant execute on function public.attendance_v3_reader_context(text) to service_role;

grant execute on function public.attendance_v3_validate_employee(text,text) to service_role;
grant execute on function public.attendance_v3_record_movement(text,text,uuid,text) to service_role;

select pg_notify('pgrst','reload schema');

commit;
