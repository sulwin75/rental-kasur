-- Jalankan sekali di Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'staff' check (role in ('admin','staff')),
  created_at timestamptz not null default now()
);
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  price_per_night numeric(12,2) not null default 0 check (price_per_night >= 0),
  stock integer not null default 0 check (stock >= 0),
  unit text not null default 'buah',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  address text,
  created_at timestamptz not null default now()
);
create table if not exists public.rentals (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers(id),
  customer_name text not null,
  customer_phone text,
  customer_address text,
  start_date date not null,
  end_date date not null,
  nights integer generated always as ((end_date - start_date)) stored,
  shipping_fee numeric(12,2) not null default 0 check (shipping_fee >= 0),
  pickup_fee numeric(12,2) not null default 0 check (pickup_fee >= 0),
  subtotal numeric(12,2) not null default 0 check (subtotal >= 0),
  total numeric(12,2) not null default 0 check (total >= 0),
  deposit_paid numeric(12,2) not null default 0 check (deposit_paid >= 0),
  status text not null default 'Belum lunas',
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check (end_date > start_date),
  check (deposit_paid <= total)
);
create table if not exists public.rental_items (
  id uuid primary key default gen_random_uuid(),
  rental_id uuid not null references public.rentals(id) on delete cascade,
  product_id uuid not null references public.products(id),
  product_name text not null,
  quantity integer not null check (quantity > 0),
  price_per_night numeric(12,2) not null check (price_per_night >= 0),
  line_total numeric(12,2) not null check (line_total >= 0)
);
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  rental_id uuid not null references public.rentals(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  payment_date timestamptz not null default now(),
  method text,
  notes text,
  recorded_by uuid references auth.users(id)
);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id, full_name, role) values(new.id, coalesce(new.raw_user_meta_data->>'full_name',''), 'staff') on conflict(id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.create_rental(
 p_customer_name text, p_customer_phone text, p_customer_address text,
 p_product_id uuid, p_quantity integer, p_start_date date, p_end_date date,
 p_shipping_fee numeric default 0, p_pickup_fee numeric default 0,
 p_deposit_paid numeric default 0, p_notes text default null
) returns uuid language plpgsql security invoker set search_path=public as $$
declare v_product public.products%rowtype; v_nights integer; v_subtotal numeric; v_total numeric; v_customer uuid; v_rental uuid; v_reserved integer;
begin
 if auth.uid() is null then raise exception 'Silakan login terlebih dahulu'; end if;
 if p_end_date <= p_start_date or p_quantity < 1 then raise exception 'Tanggal atau jumlah tidak valid'; end if;
 select * into v_product from public.products where id=p_product_id and active=true for update;
 if not found then raise exception 'Barang tidak ditemukan atau nonaktif'; end if;
 v_nights := p_end_date-p_start_date;
 select coalesce(sum(ri.quantity),0) into v_reserved from public.rental_items ri join public.rentals r on r.id=ri.rental_id
 where ri.product_id=p_product_id and r.status <> 'Dibatalkan' and r.start_date < p_end_date and r.end_date > p_start_date;
 if v_product.stock-v_reserved < p_quantity then raise exception 'Stok tidak mencukupi pada periode tersebut. Tersedia: %', greatest(v_product.stock-v_reserved,0); end if;
 v_subtotal := v_product.price_per_night*p_quantity*v_nights;
 v_total := v_subtotal+coalesce(p_shipping_fee,0)+coalesce(p_pickup_fee,0);
 if coalesce(p_deposit_paid,0)>v_total then raise exception 'DP melebihi total tagihan'; end if;
 insert into public.customers(name,phone,address) values(p_customer_name,p_customer_phone,p_customer_address) returning id into v_customer;
 insert into public.rentals(customer_id,customer_name,customer_phone,customer_address,start_date,end_date,shipping_fee,pickup_fee,subtotal,total,deposit_paid,status,notes,created_by)
 values(v_customer,p_customer_name,p_customer_phone,p_customer_address,p_start_date,p_end_date,p_shipping_fee,p_pickup_fee,v_subtotal,v_total,coalesce(p_deposit_paid,0),case when p_deposit_paid>=v_total then 'Lunas' else 'Belum lunas' end,p_notes,auth.uid()) returning id into v_rental;
 insert into public.rental_items(rental_id,product_id,product_name,quantity,price_per_night,line_total)
 values(v_rental,p_product_id,v_product.name,p_quantity,v_product.price_per_night,v_subtotal);
 if coalesce(p_deposit_paid,0)>0 then insert into public.payments(rental_id,amount,recorded_by,notes) values(v_rental,p_deposit_paid,auth.uid(),'DP awal'); end if;
 return v_rental;
end; $$;

create or replace function public.mark_rental_paid(p_rental_id uuid) returns void language plpgsql security invoker set search_path=public as $$
declare v_due numeric;
begin
 select total-deposit_paid into v_due from public.rentals where id=p_rental_id for update;
 if not found then raise exception 'Transaksi tidak ditemukan'; end if;
 if v_due>0 then insert into public.payments(rental_id,amount,recorded_by,notes) values(p_rental_id,v_due,auth.uid(),'Pelunasan'); end if;
 update public.rentals set deposit_paid=total,status='Lunas' where id=p_rental_id;
end; $$;

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.customers enable row level security;
alter table public.rentals enable row level security;
alter table public.rental_items enable row level security;
alter table public.payments enable row level security;
drop policy if exists profiles_read_own on public.profiles;
create policy profiles_read_own on public.profiles for select to authenticated using (id=auth.uid());
-- Data operasional hanya dapat diakses pengguna yang sudah login. Pengaturan admin/petugas dapat diperketat kemudian.
do $$ declare t text; begin foreach t in array array['products','customers','rentals','rental_items','payments'] loop
 execute format('drop policy if exists %I on public.%I',t||'_authenticated_access',t);
 execute format('create policy %I on public.%I for all to authenticated using (true) with check (true)',t||'_authenticated_access',t);
 end loop; end $$;
grant usage on schema public to authenticated;
grant select,insert,update,delete on public.profiles,public.products,public.customers,public.rentals,public.rental_items,public.payments to authenticated;
grant execute on function public.create_rental(text,text,text,uuid,integer,date,date,numeric,numeric,numeric,text) to authenticated;
grant execute on function public.mark_rental_paid(uuid) to authenticated;

-- Setelah membuat akun pertama, promosikan akun tersebut menjadi admin:
-- update public.profiles set role='admin' where id=(select id from auth.users where email='EMAIL_LOGIN_ANDA');
