-- Run this once in Supabase > SQL Editor

create table profiles (id uuid primary key references auth.users on delete cascade, is_admin boolean not null default false);

create table products (
  id uuid primary key default gen_random_uuid(),
  name text not null, club text not null, season text, kind text default 'Home',
  price numeric not null check (price >= 0), mrp numeric,
  sizes text[] not null default '{S,M,L,XL}', stock int not null default 0,
  color1 text default '#c1121f', color2 text default '#ffffff',
  image_url text, description text, active boolean not null default true,
  created_at timestamptz not null default now()
);

create table orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users,
  items jsonb not null, subtotal numeric not null, shipping numeric not null, total numeric not null,
  name text not null, phone text not null, address text not null, city text not null, pincode text not null,
  payment_method text not null check (payment_method in ('COD','UPI')),
  utr text, screenshot_url text,
  payment_status text not null default 'pending',
  status text not null default 'placed',
  created_at timestamptz not null default now()
);

create function is_admin() returns boolean language sql stable security definer set search_path = public
as $$ select coalesce((select is_admin from profiles where id = auth.uid()), false) $$;

create function handle_new_user() returns trigger language plpgsql security definer set search_path = public
as $$ begin insert into profiles (id) values (new.id); return new; end $$;
create trigger on_signup after insert on auth.users for each row execute function handle_new_user();

alter table profiles enable row level security;
alter table products enable row level security;
alter table orders enable row level security;

create policy "read own profile" on profiles for select using (id = auth.uid());
create policy "anyone sees active products" on products for select using (active or is_admin());
create policy "admin adds products" on products for insert with check (is_admin());
create policy "admin edits products" on products for update using (is_admin());
create policy "admin deletes products" on products for delete using (is_admin());
create policy "see own orders" on orders for select using (user_id = auth.uid() or is_admin());
create policy "admin updates orders" on orders for update using (is_admin());
-- Customers cannot insert orders directly; they must use place_order() below, which prices items on the server.

create function place_order(p_items jsonb, p_name text, p_phone text, p_address text, p_city text, p_pincode text,
  p_method text, p_utr text, p_shot text) returns uuid
language plpgsql security definer set search_path = public as $$
declare it jsonb; pr products; sub numeric := 0; ship numeric; lines jsonb := '[]'; oid uuid; q int;
begin
  if auth.uid() is null then raise exception 'Please log in first'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    q := (it->>'qty')::int;
    select * into pr from products where id = (it->>'id')::uuid and active for update;
    if not found or q < 1 or pr.stock < q then raise exception 'Not enough stock for %', coalesce(pr.name, 'an item'); end if;
    update products set stock = stock - q where id = pr.id;
    sub := sub + pr.price * q;
    lines := lines || jsonb_build_object('id', pr.id, 'name', pr.name, 'size', it->>'size', 'qty', q, 'price', pr.price);
  end loop;
  if sub = 0 then raise exception 'Cart is empty'; end if;
  ship := case when sub >= 2999 then 0 else 99 end;
  insert into orders (user_id, items, subtotal, shipping, total, name, phone, address, city, pincode, payment_method, utr, screenshot_url)
  values (auth.uid(), lines, sub, ship, sub + ship, p_name, p_phone, p_address, p_city, p_pincode, p_method, p_utr, p_shot)
  returning id into oid;
  return oid;
end $$;

-- Image storage
insert into storage.buckets (id, name, public) values ('payments','payments',true), ('products','products',true);
create policy "logged-in users upload payment proof" on storage.objects for insert to authenticated with check (bucket_id = 'payments');
create policy "anyone views images" on storage.objects for select using (bucket_id in ('payments','products'));
create policy "admin uploads product images" on storage.objects for insert to authenticated with check (bucket_id = 'products' and is_admin());

-- Sample products (edit or delete later from the admin panel)
insert into products (name, club, season, kind, price, mrp, stock, color1, color2, description) values
('Real Madrid Home Jersey','Real Madrid','2025/26','Home',3499,4999,25,'#f5f5f5','#2b3a8c','Official licensed home kit.'),
('FC Barcelona Home Jersey','FC Barcelona','2025/26','Home',3499,4999,20,'#a50044','#004d98','Official licensed home kit.'),
('Manchester United Home Jersey','Manchester United','2025/26','Home',3299,4599,18,'#da291c','#111111','Official licensed home kit.'),
('Argentina Home Jersey','Argentina','2026','Home',3799,5299,30,'#75aadb','#ffffff','Official licensed national team kit.'),
('India Away Jersey','India','2025/26','Away',2499,3299,40,'#f4a300','#0b3d91','Official licensed national team kit.');

-- AFTER you sign up on your site, make yourself admin (replace the email):
-- update profiles set is_admin = true where id = (select id from auth.users where email = 'you@example.com');
