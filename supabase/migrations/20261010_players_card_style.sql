-- Players pick their own trading-card style (Players page / player profile).
-- Additive: nullable column; null = default style. Players may set it on their own
-- record, so it joins the self-service list in private.players_guard.
alter table public.players add column if not exists card_style text
  check (card_style is null or card_style ~ '^[a-z0-9-]{1,20}$');

create or replace function private.players_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  editable constant text[] := array['position', 'bats', 'throws', 'photo', 'card_style', 'updated_at'];
begin
  if auth.uid() is null or private.is_staff() then
    return new;
  end if;
  if (to_jsonb(new) - editable) is distinct from (to_jsonb(old) - editable) then
    raise exception 'Players can only update position, bats, throws, photo and card style'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function private.players_guard() from public, anon, authenticated;
