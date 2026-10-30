-- Spec 12 helpers: updated_at trigger, delete blocker, and the owner check used by row-level security.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Payment records, matches and audit rows are never deleted (CLAUDE.md), for every role.
create or replace function public.block_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'rows of % are never deleted', tg_table_name;
end;
$$;

-- Matches and audit rows are never changed either.
create or replace function public.block_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'rows of % are never changed', tg_table_name;
end;
$$;

-- TrxIDs are stored trimmed and upper case (CLAUDE.md).
create or replace function public.normalize_trx_id()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.trx_id is not null then
    new.trx_id := upper(btrim(new.trx_id));
  end if;
  return new;
end;
$$;
