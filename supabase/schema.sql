create table if not exists settings (
  user_id uuid primary key references auth.users on delete cascade,
  rate numeric not null default 0 check (rate >= 0),
  cycle_start_day smallint not null default 1 check (cycle_start_day between 1 and 28)
);
create table if not exists absences (
  user_id uuid not null references auth.users on delete cascade,
  day date not null,
  meals smallint not null check (meals in (1,2)),
  primary key (user_id, day)
);
create table if not exists paid_cycles (
  user_id uuid not null references auth.users on delete cascade,
  cycle_start date not null,
  is_paid boolean not null default false,
  paid_at timestamptz,
  amount numeric check (amount >= 0),
  primary key (user_id, cycle_start)
);
alter table paid_cycles add column if not exists amount numeric check (amount >= 0);
alter table settings enable row level security;
alter table absences enable row level security;
alter table paid_cycles enable row level security;
drop policy if exists "own settings" on settings;
drop policy if exists "own absences" on absences;
drop policy if exists "own paid cycles" on paid_cycles;
create policy "own settings" on settings for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own absences" on absences for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own paid cycles" on paid_cycles for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

