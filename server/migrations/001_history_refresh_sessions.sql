-- Opaque refresh credentials for the mobile History session.
-- Apply with the Supabase SQL editor before deploying the backend code.
create table if not exists public."HistoryRefreshSession" (
    token_hash text primary key check (length(token_hash) = 64),
    user_id bigint not null references public."user"(id) on delete cascade,
    created_at timestamptz not null default now(),
    expires_at timestamptz not null,
    revoked_at timestamptz
);

create index if not exists history_refresh_session_user_idx
    on public."HistoryRefreshSession" (user_id);

alter table public."HistoryRefreshSession" enable row level security;

-- The backend service key performs table operations. Clients cannot inspect hashes.
revoke all on public."HistoryRefreshSession" from anon, authenticated;
grant all on public."HistoryRefreshSession" to service_role;

-- Consume a valid refresh hash exactly once, rotate to a new hash, and return its
-- owner. Keeping this in one transaction prevents concurrent reuse of a token.
create or replace function public.refresh_history_session(
    p_token_hash text,
    p_new_token_hash text,
    p_new_expires_at timestamptz
)
returns table(user_id bigint)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_user_id bigint;
begin
    update public."HistoryRefreshSession" s
       set revoked_at = now()
     where s.token_hash = p_token_hash
       and s.revoked_at is null
       and s.expires_at > now()
    returning s.user_id into v_user_id;

    if v_user_id is null then
        return;
    end if;

    insert into public."HistoryRefreshSession" (token_hash, user_id, expires_at)
    values (p_new_token_hash, v_user_id, p_new_expires_at);

    return query select v_user_id;
end;
$$;

revoke all on function public.refresh_history_session(text, text, timestamptz)
    from public, anon, authenticated;
grant execute on function public.refresh_history_session(text, text, timestamptz)
    to service_role;
