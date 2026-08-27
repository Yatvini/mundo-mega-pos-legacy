-- 036_restrict_attendance_v3_internal_authenticated_grants.sql
-- Revoca EXECUTE de authenticated en RPC internas/publicas de Asistencia V3.
-- Ejecutar despues de 035_harden_attendance_v3_function_grants.sql.
-- El flujo publico debe pasar por Netlify Function con service_role server-side.

begin;

revoke execute on function public.attendance_v3_employee_token_context(text) from authenticated;
revoke execute on function public.attendance_v3_reader_context(text) from authenticated;
revoke execute on function public.attendance_v3_validate_employee(text,text) from authenticated;
revoke execute on function public.attendance_v3_record_movement(text,text,uuid,text) from authenticated;

grant execute on function public.attendance_v3_employee_token_context(text) to service_role;
grant execute on function public.attendance_v3_reader_context(text) to service_role;
grant execute on function public.attendance_v3_validate_employee(text,text) to service_role;
grant execute on function public.attendance_v3_record_movement(text,text,uuid,text) to service_role;

select pg_notify('pgrst','reload schema');

commit;
