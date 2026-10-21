-- Run once in Supabase > SQL Editor (after schema.sql)

alter table products add column if not exists category text not null default 'Club';
update products set category = 'National' where club in ('Argentina','India');

create table if not exists expenses (
  id uuid primary key default gen_random_uuid(),
  spent_on date not null default current_date,
  category text not null default 'General',
  amount numeric not null check (amount > 0),
  note text
);
alter table expenses enable row level security;
create policy "admin manages expenses" on expenses for all using (is_admin()) with check (is_admin());
