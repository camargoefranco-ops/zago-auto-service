-- ============================================================
-- ZAGO AUTO SERVICE — Schema completo (DO ZERO)
-- Cole este arquivo INTEIRO no SQL Editor do Supabase e rode uma vez.
-- Reconstruído lendo todo o código do app (zago-auto-service.html),
-- já que o script original se perdeu na migração de aparelho.
--
-- ATENÇÃO: este script APAGA (se existirem) e recria as tabelas abaixo.
-- Só rode isso se você realmente quer perder os dados atuais do projeto.
-- ============================================================

-- ---------- LIMPEZA (permite rodar este script quantas vezes precisar) ----------
drop table if exists cupons cascade;
drop table if exists avaliacoes cascade;
drop table if exists galeria cascade;
drop table if exists orcamentos cascade;
drop table if exists agendamentos cascade;
drop table if exists clientes cascade;
drop table if exists profiles cascade;

drop function if exists is_staff() cascade;
drop function if exists get_public_stats() cascade;
drop function if exists resolver_indicacao(text) cascade;
drop function if exists contar_indicados(uuid) cascade;
drop function if exists handle_new_user() cascade;
drop trigger if exists on_auth_user_created on auth.users;

create extension if not exists pgcrypto;

-- ============================================================
-- PROFILES  (define quem é "equipe" e quem é "cliente")
-- ============================================================
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'cliente' check (role in ('cliente','equipe')),
  criado_em timestamptz not null default now()
);

alter table profiles enable row level security;

-- is_staff(): função auxiliar usada em quase todas as políticas abaixo.
-- security definer para não cair em recursão de RLS ao ler a própria tabela profiles.
create function is_staff()
returns boolean
language sql
security definer
stable
as $$
  select exists(
    select 1 from profiles where id = auth.uid() and role = 'equipe'
  );
$$;

create policy "profiles_select_own_or_staff" on profiles
  for select using (auth.uid() = id or is_staff());

-- Cria automaticamente um profile "cliente" toda vez que alguém se cadastra
-- (o app nunca insere direto em profiles, então isso é feito por trigger).
create function handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.profiles (id, role) values (new.id, 'cliente');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ============================================================
-- CLIENTES  (id = mesmo id do usuário em auth.users)
-- ============================================================
create table clientes (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  fone text not null,
  veiculos jsonb not null default '[]'::jsonb,
  indicado_por uuid references clientes(id) on delete set null,
  criado_em timestamptz not null default now()
);

alter table clientes enable row level security;

create policy "clientes_select" on clientes
  for select using (auth.uid() = id or is_staff());

create policy "clientes_insert" on clientes
  for insert with check (auth.uid() = id or is_staff());

create policy "clientes_update" on clientes
  for update using (auth.uid() = id or is_staff())
  with check (auth.uid() = id or is_staff());

create policy "clientes_delete" on clientes
  for delete using (is_staff());

-- ============================================================
-- AGENDAMENTOS
-- ============================================================
create table agendamentos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id) on delete cascade,
  fone text,
  veiculo text not null,
  servico text not null,
  tamanho text,
  data date not null,
  hora text not null,
  obs text,
  status text not null default 'Recebido',
  criado_em timestamptz not null default now()
);

alter table agendamentos enable row level security;

create policy "agendamentos_select" on agendamentos
  for select using (auth.uid() = cliente_id or is_staff());

create policy "agendamentos_insert" on agendamentos
  for insert with check (auth.uid() = cliente_id);

create policy "agendamentos_update" on agendamentos
  for update using (is_staff())
  with check (is_staff());

create policy "agendamentos_delete" on agendamentos
  for delete using (is_staff());

-- ============================================================
-- ORÇAMENTOS
-- ============================================================
create table orcamentos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id) on delete cascade,
  fone text,
  veiculo text not null,
  descricao text not null,
  valor numeric,
  status text not null default 'Pendente',
  criado_em timestamptz not null default now()
);

alter table orcamentos enable row level security;

create policy "orcamentos_select" on orcamentos
  for select using (auth.uid() = cliente_id or is_staff());

create policy "orcamentos_insert" on orcamentos
  for insert with check (auth.uid() = cliente_id);

create policy "orcamentos_update" on orcamentos
  for update using (is_staff())
  with check (is_staff());

create policy "orcamentos_delete" on orcamentos
  for delete using (is_staff());

-- ============================================================
-- GALERIA (fotos de trabalhos — pública para visitantes verem na home)
-- ============================================================
create table galeria (
  id uuid primary key default gen_random_uuid(),
  titulo text,
  imagem text not null,
  criado_por uuid references profiles(id) on delete set null,
  criado_em timestamptz not null default now()
);

alter table galeria enable row level security;

create policy "galeria_select_publica" on galeria
  for select using (true);

create policy "galeria_insert" on galeria
  for insert with check (is_staff());

create policy "galeria_delete" on galeria
  for delete using (is_staff());

-- ============================================================
-- AVALIAÇÕES (depoimentos — públicos na home)
-- ============================================================
create table avaliacoes (
  id uuid primary key default gen_random_uuid(),
  agendamento_id uuid references agendamentos(id) on delete set null,
  cliente_id uuid not null references clientes(id) on delete cascade,
  fone text,
  veiculo text,
  servico text,
  nota int not null check (nota between 1 and 5),
  comentario text,
  nome_cliente text,
  criado_em timestamptz not null default now()
);

alter table avaliacoes enable row level security;

create policy "avaliacoes_select_publica" on avaliacoes
  for select using (true);

create policy "avaliacoes_insert" on avaliacoes
  for insert with check (auth.uid() = cliente_id);

-- ============================================================
-- CUPONS DE DESCONTO
-- ============================================================
create table cupons (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id) on delete cascade,
  codigo text not null unique,
  percentual int not null check (percentual > 0 and percentual <= 100),
  usado boolean not null default false,
  criado_em timestamptz not null default now()
);

alter table cupons enable row level security;

create policy "cupons_select" on cupons
  for select using (auth.uid() = cliente_id or is_staff());

create policy "cupons_insert" on cupons
  for insert with check (is_staff());

create policy "cupons_update" on cupons
  for update using (is_staff())
  with check (is_staff());

create policy "cupons_delete" on cupons
  for delete using (is_staff());

-- ============================================================
-- FUNÇÕES USADAS PELO APP (RPC)
-- ============================================================

-- Estatísticas públicas mostradas na tela inicial (sem expor dados privados)
create function get_public_stats()
returns json
language sql
security definer
stable
as $$
  select json_build_object(
    'total_clientes', (select count(*) from clientes),
    'total_veiculos', (select coalesce(sum(jsonb_array_length(veiculos)), 0) from clientes)
  );
$$;

-- Resolve um código de indicação (ex: "ZAGO1234") para o id do cliente indicador
create function resolver_indicacao(codigo text)
returns uuid
language sql
security definer
stable
as $$
  select id from clientes
  where 'ZAGO' || right(regexp_replace(fone, '\D', '', 'g'), 4) = upper(codigo)
  limit 1;
$$;

-- Conta quantos clientes um determinado cliente já indicou
create function contar_indicados(indicador_id uuid)
returns int
language sql
security definer
stable
as $$
  select count(*)::int from clientes where indicado_por = indicador_id;
$$;

grant execute on function is_staff() to authenticated, anon;
grant execute on function get_public_stats() to authenticated, anon;
grant execute on function resolver_indicacao(text) to authenticated, anon;
grant execute on function contar_indicados(uuid) to authenticated, anon;

-- ============================================================
-- REALTIME (o app escuta mudanças ao vivo nessas tabelas)
-- ============================================================
alter publication supabase_realtime add table clientes;
alter publication supabase_realtime add table agendamentos;
alter publication supabase_realtime add table orcamentos;
alter publication supabase_realtime add table galeria;
alter publication supabase_realtime add table avaliacoes;
alter publication supabase_realtime add table cupons;

-- ============================================================
-- FIM. Depois de rodar:
-- 1) Confirme em Authentication > Settings que "Confirm email" está
--    DESLIGADO (o app faz login automático logo após o cadastro).
-- 2) Para criar uma conta de EQUIPE: cadastre-se normalmente pelo app
--    (fica como 'cliente') e depois rode no SQL Editor:
--      update profiles set role = 'equipe' where id = '<uuid-do-usuario>';
--    (o uuid aparece em Authentication > Users)
-- ============================================================
