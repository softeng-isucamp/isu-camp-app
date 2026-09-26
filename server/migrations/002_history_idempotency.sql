-- Optional client-generated identity makes queued History writes safe to retry.
alter table public."UserHistory"
    add column if not exists client_event_id uuid;

create unique index if not exists user_history_owner_client_event_uidx
    on public."UserHistory" ("User_id", client_event_id)
    where client_event_id is not null;
