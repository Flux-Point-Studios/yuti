-- Address Book table for syncing contacts across devices
-- v1.5.0

create table if not exists address_book (
  id text primary key,
  user_id uuid not null references users(id) on delete cascade,
  name text not null,
  address text not null,
  handle text,
  description text,
  created_at timestamptz not null default now(),
  last_used timestamptz
);

create index if not exists idx_address_book_user on address_book(user_id);
create index if not exists idx_address_book_name on address_book(name);

alter table address_book enable row level security;

create policy "Users can view own contacts" on address_book
  for select using (auth.uid() = user_id);

create policy "Users can insert own contacts" on address_book
  for insert with check (auth.uid() = user_id);

create policy "Users can update own contacts" on address_book
  for update using (auth.uid() = user_id);

create policy "Users can delete own contacts" on address_book
  for delete using (auth.uid() = user_id); 