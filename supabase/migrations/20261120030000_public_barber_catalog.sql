revoke all on public.barbers from anon, authenticated;
revoke select (id, display_name) on public.barbers from anon, authenticated;

create or replace view public.active_barber_catalog
with (security_barrier = true)
as
select id, display_name
from public.barbers
where is_active = true;

grant select on public.active_barber_catalog to anon, authenticated;
