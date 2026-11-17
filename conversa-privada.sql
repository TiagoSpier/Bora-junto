-- BORA JUNTO: conversa privada (rodar UMA vez em Supabase > SQL Editor > Run)
-- Regras garantidas pelo banco:
--   1. Só dá para chamar quem está em um grupo com você.
--   2. A conversa só recebe mensagens depois que a outra pessoa aceita.
--   3. Quem foi recusado não consegue pedir de novo.
--   4. Bloqueio (de qualquer lado) esconde a conversa e impede novas mensagens.

create table if not exists dm_threads (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references profiles(id) on delete cascade,  -- quem pediu
  user_b uuid not null references profiles(id) on delete cascade,  -- quem recebeu o pedido
  activity_id uuid references activities(id) on delete set null,   -- grupo de onde saiu o pedido
  status text not null default 'pendente' check (status in ('pendente','aceita','recusada')),
  created_at timestamptz not null default now(),
  last_msg_at timestamptz,
  last_msg_by uuid,
  visto_a timestamptz,
  visto_b timestamptz,
  check (user_a <> user_b)
);
-- uma única conversa por par de pessoas
create unique index if not exists dm_threads_par on dm_threads (least(user_a, user_b), greatest(user_a, user_b));

create table if not exists dm_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references dm_threads(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists dm_messages_thread on dm_messages (thread_id, created_at);

-- Existe bloqueio entre as duas pessoas (em qualquer direção)?
create or replace function dm_bloqueado(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a));
$$;

-- Pedir conversa privada
create or replace function dm_pedir(outro uuid, atividade uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); t dm_threads; novo uuid; meu_nome text;
begin
  if eu is null then raise exception 'Entre na sua conta.'; end if;
  if outro is null or outro = eu then raise exception 'Pedido inválido.'; end if;
  if dm_bloqueado(eu, outro) then raise exception 'BLOQUEADO'; end if;
  if not exists (select 1 from interests i1 join interests i2 on i1.activity_id = i2.activity_id
                 where i1.user_id = eu and i2.user_id = outro) then
    raise exception 'SEM_GRUPO';
  end if;
  select * into t from dm_threads
    where least(user_a, user_b) = least(eu, outro) and greatest(user_a, user_b) = greatest(eu, outro);
  if found then
    -- quem recusou pode mudar de ideia e chamar; quem foi recusado não pode insistir
    if t.status = 'recusada' and t.user_b = eu then
      update dm_threads set user_a = eu, user_b = outro, status = 'pendente', created_at = now(), activity_id = atividade
        where id = t.id;
    else
      return t.id;
    end if;
    novo := t.id;
  else
    insert into dm_threads (user_a, user_b, activity_id) values (eu, outro, atividade) returning id into novo;
  end if;
  begin  -- aviso no sininho (se falhar, o pedido continua valendo)
    select name into meu_nome from profiles where id = eu;
    insert into notifications (user_id, text) values (outro, coalesce(meu_nome, 'Alguém') || ' quer conversar com você em privado.');
  exception when others then null;
  end;
  return novo;
end $$;

-- Aceitar ou recusar um pedido (só quem recebeu)
create or replace function dm_responder(conversa uuid, aceitar boolean) returns void
language plpgsql security definer set search_path = public as $$
declare eu uuid := auth.uid(); t dm_threads; meu_nome text;
begin
  update dm_threads set status = case when aceitar then 'aceita' else 'recusada' end
    where id = conversa and user_b = eu and status = 'pendente'
    returning * into t;
  if not found then raise exception 'Pedido não encontrado.'; end if;
  if aceitar then
    begin
      select name into meu_nome from profiles where id = eu;
      insert into notifications (user_id, text) values (t.user_a, coalesce(meu_nome, 'Alguém') || ' aceitou conversar com você em privado.');
    exception when others then null;
    end;
  end if;
end $$;

-- Marcar a conversa como lida
create or replace function dm_visto(conversa uuid) returns void
language sql security definer set search_path = public as $$
  update dm_threads set
    visto_a = case when user_a = auth.uid() then now() else visto_a end,
    visto_b = case when user_b = auth.uid() then now() else visto_b end
  where id = conversa and auth.uid() in (user_a, user_b);
$$;

-- A cada mensagem, atualiza "última mensagem" da conversa
create or replace function dm_apos_mensagem() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update dm_threads set last_msg_at = new.created_at, last_msg_by = new.user_id,
    visto_a = case when user_a = new.user_id then new.created_at else visto_a end,
    visto_b = case when user_b = new.user_id then new.created_at else visto_b end
  where id = new.thread_id;
  return new;
end $$;
drop trigger if exists dm_messages_apos on dm_messages;
create trigger dm_messages_apos after insert on dm_messages for each row execute function dm_apos_mensagem();

-- Segurança (RLS): cada pessoa só enxerga as próprias conversas
alter table dm_threads enable row level security;
alter table dm_messages enable row level security;

drop policy if exists dm_threads_ver on dm_threads;
create policy dm_threads_ver on dm_threads for select to authenticated
  using (auth.uid() in (user_a, user_b) and not dm_bloqueado(user_a, user_b));

drop policy if exists dm_messages_ver on dm_messages;
create policy dm_messages_ver on dm_messages for select to authenticated
  using (exists (select 1 from dm_threads t where t.id = thread_id and auth.uid() in (t.user_a, t.user_b)));

drop policy if exists dm_messages_enviar on dm_messages;
create policy dm_messages_enviar on dm_messages for insert to authenticated
  with check (user_id = auth.uid() and exists (
    select 1 from dm_threads t where t.id = thread_id and t.status = 'aceita'
      and auth.uid() in (t.user_a, t.user_b) and not dm_bloqueado(t.user_a, t.user_b)));

-- Pedidos e respostas só pelas funções acima (ninguém altera as tabelas direto)
revoke all on dm_threads, dm_messages from anon, authenticated;
grant select on dm_threads to authenticated;
grant select, insert on dm_messages to authenticated;
revoke all on function dm_pedir(uuid, uuid), dm_responder(uuid, boolean), dm_visto(uuid), dm_bloqueado(uuid, uuid) from public, anon;
grant execute on function dm_pedir(uuid, uuid), dm_responder(uuid, boolean), dm_visto(uuid), dm_bloqueado(uuid, uuid) to authenticated;

-- Atualização em tempo real
do $$ begin
  alter publication supabase_realtime add table dm_threads;
exception when others then null; end $$;
do $$ begin
  alter publication supabase_realtime add table dm_messages;
exception when others then null; end $$;

notify pgrst, 'reload schema';
