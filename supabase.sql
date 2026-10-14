-- =====================================================================
-- Associação Mastodonte — banco do app (Supabase / Postgres)
-- Rodar inteiro no SQL Editor de um projeto NOVO. Pode rodar de novo sem quebrar.
-- =====================================================================

-- ---------- Usuários com acesso ----------
-- Só entra no app quem estiver nesta lista. O adm cadastra o e-mail aqui
-- (pela tela Configurações) e a pessoa cria a própria senha no "Primeiro acesso".
create table if not exists public.usuarios (
  email      text primary key,
  nome       text not null,
  papel      text not null default 'membro' check (papel in ('adm','membro')),
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

insert into public.usuarios (email, nome, papel)
values ('mastodontesjrp2017@gmail.com', 'Carlos Eduardo Moreno', 'adm')
on conflict (email) do update set papel = 'adm', ativo = true, nome = excluded.nome;

create or replace function public.eh_usuario() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.usuarios
                 where email = lower(auth.jwt()->>'email') and ativo);
$$;

create or replace function public.eh_adm() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.usuarios
                 where email = lower(auth.jwt()->>'email') and ativo and papel = 'adm');
$$;

-- Bloqueia cadastro de conta de quem não está na lista
create or replace function public.trava_cadastro() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.usuarios where email = lower(new.email) and ativo) then
    raise exception 'E-mail sem permissão. Peça ao administrador para liberar o acesso.';
  end if;
  return new;
end $$;
drop trigger if exists trava_cadastro on auth.users;
create trigger trava_cadastro before insert on auth.users
  for each row execute function public.trava_cadastro();

-- ---------- Afiliados ----------
create table if not exists public.afiliados (
  id             bigint generated always as identity primary key,
  nome           text not null,
  cpf            text,                       -- só números
  telefone       text,
  endereco       text,
  valor_mensal   numeric(12,2) not null default 0,  -- valor da doação/mensalidade
  dia_vencimento int  not null default 10 check (dia_vencimento between 1 and 31),
  inicio         date not null default date_trunc('month', now())::date, -- 1ª competência cobrada
  ativo          boolean not null default true,
  obs            text,
  criado_em      timestamptz not null default now()
);
create unique index if not exists afiliados_cpf_uk on public.afiliados (cpf) where cpf is not null and cpf <> '';

-- ---------- Eventos ----------
create table if not exists public.eventos (
  id         bigint generated always as identity primary key,
  nome       text not null,
  data       date,
  hora       text,
  local      text,
  descricao  text,
  orcamento  numeric(12,2) default 0,
  status     text not null default 'planejado' check (status in ('planejado','confirmado','realizado','cancelado')),
  criado_em  timestamptz not null default now()
);

create table if not exists public.evento_tarefas (
  id           bigint generated always as identity primary key,
  evento_id    bigint not null references public.eventos(id) on delete cascade,
  descricao    text not null,
  responsavel  text,
  prazo        date,
  feito        boolean not null default false,
  criado_em    timestamptz not null default now()
);

-- ---------- Movimentos (entradas e saídas: manuais ou do extrato) ----------
create table if not exists public.movimentos (
  id          bigint generated always as identity primary key,
  data        date not null,
  descricao   text not null,
  nome        text,             -- razão social do extrato
  documento   text,             -- CPF/CNPJ só números
  valor       numeric(12,2) not null,   -- + entrada / - saída
  categoria   text,
  afiliado_id bigint references public.afiliados(id) on delete set null,  -- baixa de mensalidade
  evento_id   bigint references public.eventos(id) on delete set null,
  origem      text not null default 'manual' check (origem in ('manual','extrato')),
  chave       text unique,      -- impede importar a mesma linha duas vezes
  criado_por  text default lower(auth.jwt()->>'email'),
  criado_em   timestamptz not null default now()
);
create index if not exists movimentos_data_ix on public.movimentos (data);
create index if not exists movimentos_afiliado_ix on public.movimentos (afiliado_id);

-- ---------- Segurança (RLS) ----------
alter table public.usuarios       enable row level security;
alter table public.afiliados      enable row level security;
alter table public.eventos        enable row level security;
alter table public.evento_tarefas enable row level security;
alter table public.movimentos     enable row level security;

do $$
declare t text;
begin
  foreach t in array array['afiliados','eventos','evento_tarefas','movimentos'] loop
    execute format('drop policy if exists acesso on public.%I', t);
    execute format('create policy acesso on public.%I for all to authenticated using (public.eh_usuario()) with check (public.eh_usuario())', t);
  end loop;
end $$;

drop policy if exists ler on public.usuarios;
create policy ler on public.usuarios for select to authenticated using (public.eh_usuario());
drop policy if exists adm on public.usuarios;
create policy adm on public.usuarios for all to authenticated using (public.eh_adm()) with check (public.eh_adm());

-- ---------- Keep-alive (evita pausa do plano grátis) ----------
create or replace function public.keepalive() returns text
language sql security definer set search_path = public as $$ select 'ok'::text $$;
grant execute on function public.keepalive() to anon;
