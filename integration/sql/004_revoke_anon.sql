-- Defense in depth: Supabase's default table privileges may grant anon access.
-- RLS already denies it; revoke those grants as well.
revoke all on public.xbox_cameras, public.xbox_detection_events from public, anon;
revoke all on sequence public.xbox_detection_events_id_seq from public, anon;
revoke all on function public.xbox_event_before_insert(), public.xbox_event_after_insert(), public.xbox_touch_updated_at() from public, anon;
