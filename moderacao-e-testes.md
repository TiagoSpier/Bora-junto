# BORA JUNTO — Moderação e plano de testes

## 1. SQL para rodar UMA vez (Supabase > SQL Editor)
```sql
create or replace function delete_my_account() returns void
language sql security definer set search_path = public, auth as $$
  delete from auth.users where id = auth.uid();
$$;
revoke all on function delete_my_account() from public, anon;
grant execute on function delete_my_account() to authenticated;
notify pgrst, 'reload schema';
```
(Se a exclusão der erro de "foreign key", me mande a mensagem que eu ajusto.)

## 2. Rotina de denúncias (1x por dia, 5 minutos)
Cole no SQL Editor e clique Run:
```sql
select r.created_at, r.reason, r.target_type, r.target_id,
       p1.name as denunciante, p2.name as denunciado
from reports r
left join profiles p1 on p1.id = r.reporter_id
left join profiles p2 on p2.id = r.reported_user_id
order by r.created_at desc limit 50;
```
(Se aparecer erro de coluna inexistente, rode `select * from reports limit 5;` e me envie o resultado.)

Checklist diário:
1. Rodar a consulta e olhar as denúncias novas.
2. Ofensa, ameaça, golpe ou risco a pessoas: remova a atividade (Table Editor > activities > apagar linha) e, se for grave, o usuário (Authentication > Users > Delete).
3. Dúvida ou briga entre dois usuários: não apague, observe; aconselhe bloquear.
4. Responder em até 48h quem denunciou, por e-mail.
5. Anotar o que decidiu (planilha simples: data, caso, decisão).

## 3. Plano de teste com pessoas reais (5 a 10, Gramado/Canela)
Quem: amigos/família de 18+ com perfis variados (celular Android e iPhone).
Tarefas (peça que façam sozinhos, sem ajuda):
1. Abrir o link, criar conta e confirmar o e-mail.
2. Instalar na tela inicial.
3. Completar perfil (cidade, interesses).
4. Criar uma atividade com foto de capa (uma com data, outra "a combinar").
5. Pessoa B demonstra interesse na atividade da pessoa A e entra no grupo.
6. Conversar no chat, sugerir datas e votar.
7. Receber notificações no sininho.
8. Avaliar depois de passada a atividade.
9. Denunciar e bloquear um usuário de teste.
10. Excluir a conta de teste.

Perguntas depois (anote respostas): Onde travou? O que não entendeu? Usaria de verdade? O que faltou? Algum texto confuso?
Critério para lançar: todos completam 1 a 7 sem ajuda e nenhum erro grave aparece.
Duração sugerida: 1 semana. Corrija o que mais se repetir primeiro.
