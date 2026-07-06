-- Ejecuta esto en Supabase: Panel del proyecto > SQL Editor > New Query > pega y dale "Run"

create table pedidos (
  id bigint generated always as identity primary key,
  creado_en timestamptz default now(),
  cliente_nombre text not null,
  cliente_telefono text not null,
  cliente_direccion text not null,
  items jsonb not null,          -- lista de pizzas pedidas (nombre, tamaño, adicionales, precio)
  subtotal numeric not null,
  costo_domicilio numeric default 0,
  total numeric not null,
  metodo_pago text not null,     -- 'efectivo', 'transferencia', etc.
  notas text,
  estado text default 'nuevo'    -- 'nuevo' | 'preparando' | 'listo' | 'entregado'
);

-- Habilita Row Level Security
alter table pedidos enable row level security;

-- Permite que cualquiera (clientes desde la web) inserte pedidos
create policy "Cualquiera puede crear pedidos"
on pedidos for insert
to anon
with check (true);

-- Permite que cualquiera lea y actualice pedidos (para el panel de cocina)
-- Nota: esto es simple para empezar. Si más adelante quieres que el panel
-- requiera login, lo ajustamos con autenticación de Supabase.
create policy "Cualquiera puede leer pedidos"
on pedidos for select
to anon
using (true);

create policy "Cualquiera puede actualizar pedidos"
on pedidos for update
to anon
using (true);

-- Habilita Realtime para esta tabla (para que el panel se actualice solo)
alter publication supabase_realtime add table pedidos;


-- ===================== Tabla de configuración (abierto/cerrado) =====================

create table config (
  id int primary key default 1,
  abierto boolean default true,
  actualizado_en timestamptz default now(),
  constraint una_sola_fila check (id = 1)  -- garantiza que solo exista una fila
);

insert into config (id, abierto) values (1, true);

alter table config enable row level security;

create policy "Cualquiera puede leer config"
on config for select
to anon
using (true);

create policy "Cualquiera puede actualizar config"
on config for update
to anon
using (true);

alter publication supabase_realtime add table config;


-- ===================== Chat general con clientes =====================

create table conversaciones (
  id text primary key,               -- uuid generado en el navegador del cliente
  cliente_nombre text,
  creado_en timestamptz default now(),
  actualizado_en timestamptz default now(),
  no_leidos_negocio int default 0,    -- mensajes del cliente que el negocio no ha visto
  no_leidos_cliente int default 0     -- mensajes del negocio que el cliente no ha visto
);

create table mensajes (
  id bigint generated always as identity primary key,
  conversacion_id text references conversaciones(id) on delete cascade,
  remitente text not null,           -- 'cliente' | 'negocio'
  texto text not null,
  creado_en timestamptz default now()
);

alter table conversaciones enable row level security;
alter table mensajes enable row level security;

create policy "Cualquiera puede leer conversaciones"
on conversaciones for select to anon using (true);
create policy "Cualquiera puede crear conversaciones"
on conversaciones for insert to anon with check (true);
create policy "Cualquiera puede actualizar conversaciones"
on conversaciones for update to anon using (true);

create policy "Cualquiera puede leer mensajes"
on mensajes for select to anon using (true);
create policy "Cualquiera puede enviar mensajes"
on mensajes for insert to anon with check (true);

-- Cuando llega un mensaje nuevo, actualiza automáticamente la conversación
-- (fecha y contador de no-leídos del lado correspondiente)
create or replace function actualizar_conversacion() returns trigger as $$
begin
  if new.remitente = 'cliente' then
    update conversaciones
    set actualizado_en = now(),
        no_leidos_negocio = no_leidos_negocio + 1
    where id = new.conversacion_id;
  else
    update conversaciones
    set actualizado_en = now(),
        no_leidos_cliente = no_leidos_cliente + 1
    where id = new.conversacion_id;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trigger_actualizar_conversacion
after insert on mensajes
for each row execute function actualizar_conversacion();

alter publication supabase_realtime add table conversaciones;
alter publication supabase_realtime add table mensajes;
