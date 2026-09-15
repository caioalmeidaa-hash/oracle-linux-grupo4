# Roteiro de apresentação — SSH endurecido (6 minutos)

Texto pra você praticar em voz alta antes da apresentação. Não precisa decorar palavra por palavra, mas fala com essas ideias na ordem.

---

## Abertura (30 segundos)

> "Por padrão, o SSH aceita três coisas perigosas ao mesmo tempo: login como root, login por senha, e fica sempre na porta 22, que todo mundo conhece. Isso é exatamente o que robôs na internet inteira ficam testando o dia inteiro, em qualquer IP que acharem. A gente eliminou as três coisas."

## As mudanças, uma por uma (3 minutos)

> "Primeiro, trocamos senha por par de chaves. Uma chave privada, que fica só no meu computador, e uma pública, que fica no servidor. Pra entrar, meu computador precisa provar que tem a chave privada certa — e isso não dá pra adivinhar por tentativa e erro, diferente de senha."

> "Segundo, desligamos o login direto do root. Root pode fazer qualquer coisa no sistema, então se alguém invadisse logando como root, já teria controle total na hora. Agora só dá pra entrar com usuário nominal, e virar root depois via sudo — o que fica registrado em log, com nome de quem fez."

> "Terceiro, mudamos a porta padrão de 22 pra 6767. Isso sozinho não é segurança de verdade — quem quiser escanear, acha — mas reduz muito o volume de tentativa automática de robô, que quase sempre mira só na porta 22."

> "Quarto, criamos um grupo específico, ssh-users, e só quem tá nesse grupo consegue logar — mesmo tendo chave válida. É uma segunda trava, uma lista de permissão explícita."

> "Quinto, limitamos tentativas: no máximo 3 erros de autenticação antes de derrubar a conexão, e só 30 segundos pra completar o login depois de conectar. E no firewall, limitamos a 10 conexões novas por minuto nessa porta — trava qualquer tentativa de força bruta continuada."

> "Por último, colocamos um aviso legal na tela de login, citando o Artigo 154-A do Código Penal — acesso não autorizado é crime, e isso fica explícito antes mesmo da pessoa tentar entrar."

## Demonstração ao vivo (2 minutos)

Narração enquanto você roda os comandos (numa janela de terminal já preparada, sem precisar digitar tudo na hora):

> "Vou mostrar primeiro um acesso normal, só com a chave."

```
ssh -p 6767 calmeida@<ip-da-vm>
```

> "Repara: não pediu senha nenhuma, e apareceu o aviso legal antes do login."

> "Agora vou tentar forçar só com senha, sem usar a chave."

```
ssh -p 6767 -o PreferredAuthentications=password calmeida@<ip-da-vm>
```

> "E foi recusado na hora — 'Permission denied (publickey)'. Ou seja, mesmo que alguém soubesse uma senha, não adiantaria: senha nem é uma opção de entrada aqui."

## Fechamento (30 segundos)

> "Resumindo: o SSH nosso só aceita chave, só aceita usuário nominal de um grupo específico, numa porta não padrão, com limite de tentativa em duas camadas diferentes (o próprio SSH e o firewall), e com log de tudo. Testamos os dois lados — quem deve entrar, entra; quem não deve, é barrado — e isso tá documentado com evidência em texto, não só print."

---

## Se alguém da turma perguntar

- **"Por que não bloquear IP direto?"** → IP é fácil de trocar (rede dinâmica, VPN). Limitar TAXA de conexão funciona não importa de onde venha a tentativa.
- **"Mudar a porta não é 'segurança por obscuridade', que não vale nada?"** → É, sozinha não vale muito. Mas combinada com as outras camadas (chave, grupo, limite de taxa), o ganho real é reduzir o RUÍDO de tentativa automática — sobra só ataque direcionado, que é raro.
- **"O que acontece se eu perder minha chave privada?"** → Não entra mais por aquele caminho. Por isso é importante ter um usuário administrador alternativo ou acesso ao console local da máquina como plano B (que é inclusive o que usamos quando precisamos autorizar um computador novo).
