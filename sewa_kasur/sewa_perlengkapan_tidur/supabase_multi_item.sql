-- Jalankan SEKALI di Supabase SQL Editor SEBELUM aplikasi versi baru dipasang.
-- Menambah fungsi transaksi dengan banyak barang. Data dan fungsi lama tidak berubah.
create or replace function public.create_rental_multi(
 p_customer_name text, p_customer_phone text, p_customer_address text,
 p_items jsonb, p_start_date date, p_end_date date,
 p_shipping_fee numeric default 0, p_pickup_fee numeric default 0,
 p_deposit_paid numeric default 0, p_notes text default null
) returns uuid language plpgsql security invoker set search_path=public as $$
declare it record; v_product public.products%rowtype; v_nights integer; v_subtotal numeric := 0;
        v_total numeric; v_customer uuid; v_rental uuid; v_reserved integer;
begin
 if auth.uid() is null then raise exception 'Silakan login terlebih dahulu'; end if;
 if p_end_date <= p_start_date then raise exception 'Tanggal kembali harus setelah tanggal mulai'; end if;
 if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Pilih minimal satu barang'; end if;
 v_nights := p_end_date - p_start_date;
 for it in
   select (x->>'product_id')::uuid as pid, sum((x->>'quantity')::int)::int as qty
   from jsonb_array_elements(p_items) x group by 1 order by 1
 loop
   if it.qty < 1 then raise exception 'Jumlah tidak valid'; end if;
   select * into v_product from public.products where id = it.pid and active = true for update;
   if not found then raise exception 'Barang tidak ditemukan atau nonaktif'; end if;
   select coalesce(sum(ri.quantity),0) into v_reserved
     from public.rental_items ri join public.rentals r on r.id = ri.rental_id
     where ri.product_id = it.pid and r.status <> 'Dibatalkan'
       and r.start_date < p_end_date and r.end_date > p_start_date;
   if v_product.stock - v_reserved < it.qty then
     raise exception 'Stok % tidak cukup pada periode tersebut. Tersedia: %', v_product.name, greatest(v_product.stock - v_reserved, 0);
   end if;
   v_subtotal := v_subtotal + v_product.price_per_night * it.qty * v_nights;
 end loop;
 v_total := v_subtotal + coalesce(p_shipping_fee,0) + coalesce(p_pickup_fee,0);
 if coalesce(p_deposit_paid,0) > v_total then raise exception 'DP melebihi total tagihan'; end if;
 insert into public.customers(name,phone,address) values (p_customer_name,p_customer_phone,p_customer_address) returning id into v_customer;
 insert into public.rentals(customer_id,customer_name,customer_phone,customer_address,start_date,end_date,shipping_fee,pickup_fee,subtotal,total,deposit_paid,status,notes,created_by)
 values (v_customer,p_customer_name,p_customer_phone,p_customer_address,p_start_date,p_end_date,coalesce(p_shipping_fee,0),coalesce(p_pickup_fee,0),v_subtotal,v_total,coalesce(p_deposit_paid,0),
         case when coalesce(p_deposit_paid,0) >= v_total then 'Lunas' else 'Belum lunas' end, p_notes, auth.uid())
 returning id into v_rental;
 insert into public.rental_items(rental_id,product_id,product_name,quantity,price_per_night,line_total)
 select v_rental, p.id, p.name, g.qty, p.price_per_night, p.price_per_night * g.qty * v_nights
 from (select (x->>'product_id')::uuid as pid, sum((x->>'quantity')::int)::int as qty from jsonb_array_elements(p_items) x group by 1) g
 join public.products p on p.id = g.pid;
 if coalesce(p_deposit_paid,0) > 0 then
   insert into public.payments(rental_id,amount,recorded_by,notes) values (v_rental,p_deposit_paid,auth.uid(),'DP awal');
 end if;
 return v_rental;
end; $$;
grant execute on function public.create_rental_multi(text,text,text,jsonb,date,date,numeric,numeric,numeric,text) to authenticated;
