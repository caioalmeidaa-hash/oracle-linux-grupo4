# Guia explicativo — o que fizemos e por quê (Grupo 4 / Oracle Linux)

Esse arquivo é pra você entender de verdade o que rodou na VM, não só pra copiar comando. Serve de base pra você conseguir explicar na apresentação e responder pergunta do professor sem travar.

---

## 1. O que o professor pediu, resumido

O trabalho pede um ambiente Linux "seguro" com três pilares:

1. **Disco criptografado** — se alguém roubar o HD/VM, não consegue ler os dados sem a senha (passphrase)
2. **SSH endurecido** — só quem tem a chave certa entra, sem senha, numa porta não óbvia, com limite de tentativas
3. **Um script próprio** que automatiza parte disso (no nosso caso, hardening de rede/firewall) e sabe se auto-auditar, aplicar e desfazer

Cada peça tem uma razão de existir: numa empresa de verdade, servidor exposto sem essas proteções é o primeiro alvo de ataque automatizado (bot varrendo a internet testando senha fraca em porta 22 é a coisa mais comum que existe).

---

## 2. Particionamento — LVM sobre LUKS

### O que é cada coisa

- **LUKS** = a camada de criptografia. Transforma um pedaço do disco num "cofre": sem a senha (passphrase), o conteúdo é só ruído ilegível.
- **LVM** = a camada de organização flexível. Em vez de particionar o disco de um jeito fixo (que depois é dor de cabeça pra redimensionar), o LVM cria um "pool" de espaço (**Volume Group**, ou VG) e você tira fatias dele (**Logical Volumes**, ou LVs) — `/home`, `/var`, `/tmp`, etc. Dá pra crescer um LV depois sem reinstalar nada.
- **"LVM sobre LUKS"** = primeiro criptografa, depois organiza por dentro. Assim qualquer LV que existir ali dentro já nasce protegido, sem precisar criptografar um por um.

### Por que `/boot` e `/boot/efi` ficam DE FORA da criptografia

Pensa na ordem de ligar o computador: a UEFI/BIOS liga → lê o `/boot/efi` → carrega o GRUB → o GRUB lê o `/boot` pra pegar o kernel do Linux → só DEPOIS disso o sistema consegue pedir a senha do LUKS pra abrir o resto. Ou seja, tem que existir uma parte legível ANTES de qualquer senha ser pedida, senão o computador nem sabe o que carregar. Por isso essas duas partições ficam fora do cofre.

### Por que sobrou espaço livre no VG (~9-10GB) de propósito

Isso não é desperdício — é reserva técnica. Duas coisas usam esse espaço livre:
- **Snapshot de LV**: uma "foto" do estado de um volume antes de mexer nele, pra poder voltar atrás se der ruim. Sem espaço livre, não dá pra tirar.
- **`lvextend`**: se um volume (tipo `/var/log`) encher, você aumenta ele puxando espaço do VG. Sem espaço livre, não tem de onde puxar.

### O erro que apareceu e como resolvemos

Quando criamos os LVs um por um com tamanho fixo, o instalador fez a partição física (`/dev/sda3`) do tamanho exato da soma dos LVs — sobrou ~10GB de disco que nem tinha virado partição ainda, ficou "solto". Resolvemos assim, comando por comando:

```bash
sudo parted /dev/sda --script mkpart primary 104921088s 125829086s
```
Cria uma partição NOVA (`/dev/sda4`) usando esse espaço que tava solto. Usamos número de setor em vez de GB porque o `parted` tava arredondando errado com vírgula decimal (problema de idioma/localização do sistema).

```bash
sudo parted /dev/sda --script set 4 lvm on
```
Marca essa partição nova como "pode ser usada por LVM" (é uma flag/etiqueta).

```bash
sudo pvcreate /dev/sda4
```
Transforma a partição num **Physical Volume** — a "matéria-prima" que o LVM usa. (PV → vira parte de um VG → vira LVs.)

```bash
sudo vgextend ol /dev/sda4
```
Junta esse PV novo ao Volume Group que já existia (`ol`), aumentando o espaço livre disponível nele.

---

## 3. SSH endurecido — cada linha explicada

Arquivo mexido: `/etc/ssh/sshd_config.d/99-hardening.conf`. Aqui vai o que cada linha faz:

| Linha | O que faz | Por quê |
|---|---|---|
| `PubkeyAuthentication yes` | Permite entrar com chave criptográfica | Base de tudo |
| `PasswordAuthentication no` | Desliga entrada por senha | Senha pode ser adivinhada/forçada por tentativa; chave, não |
| `PermitRootLogin no` | Root não pode logar direto | Fica registrado QUEM entrou (usuário nominal), depois usa `sudo` pra virar root — rastreabilidade |
| `AuthenticationMethods publickey` | Reforça que só chave é aceita como método | Fecha qualquer brecha de método alternativo |
| `Port 6767` | Muda a porta padrão (22) | Bots que varrem a internet testam a porta 22 primeiro; mudar não é segurança de verdade sozinho, mas reduz MUITO o ruído de tentativas automáticas |
| `AllowGroups ssh-users` | Só quem tá nesse grupo do Linux pode logar por SSH | Lista de permissão explícita — mesmo quem tem senha/chave válida mas não tá no grupo, não entra |
| `MaxAuthTries 3` | Derruba a conexão depois de 3 tentativas erradas | Trava força bruta na conexão atual |
| `LoginGraceTime 30` | Você tem só 30 segundos pra se autenticar depois de conectar | Não deixa conexão "pendurada" esperando |
| `ClientAliveInterval 300` + `ClientAliveCountMax 2` | Servidor manda um "ping" a cada 300s, derruba se não responder 2 vezes | Fecha sessão esquecida/travada |
| `Banner /etc/issue.net` | Mostra um aviso legal antes do login | Exigência jurídica: avisa que acesso não autorizado é crime (Art. 154-A) |

### Os comandos usados, por etapa

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak-$(date +%F)
```
Backup antes de mexer — regra básica: nunca edita config crítica sem ter como voltar atrás.

```bash
ssh-keygen -t ed25519 -C "grupo4-oracle-linux"
```
Gera o **par de chaves**: uma privada (fica só no seu computador, NUNCA compartilha) e uma pública (essa pode circular, é tipo um cadeado que só a privada abre). `ed25519` é o algoritmo — moderno, rápido, seguro.

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub usuario@ip-da-vm
```
Copia a chave PÚBLICA pra dentro da VM, no arquivo `~/.ssh/authorized_keys` — é isso que diz "essa chave pode entrar aqui".

```bash
sudo groupadd ssh-users
sudo usermod -aG ssh-users calmeida
```
Cria o grupo e coloca seu usuário dentro — é o grupo que o `AllowGroups` da tabela acima usa como filtro.

```bash
sudo semanage port -a -t ssh_port_t -p tcp 6767
```
O SELinux (sistema de segurança extra do Linux) só deixa o SSH "morar" na porta 22 por padrão — qualquer outra porta ele bloqueia, mesmo que o firewall deixe passar. Esse comando avisa o SELinux "essa porta 6767 agora também pode ser usada por SSH".

```bash
sudo firewall-cmd --permanent --remove-service=ssh
sudo firewall-cmd --permanent --add-port=6767/tcp
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" port port="6767" protocol="tcp" accept limit value="10/m"'
sudo firewall-cmd --reload
```
- Tira a porta 22 da lista de portas liberadas
- Libera a 6767
- Cria uma regra "rica" (rich rule) que além de liberar, **limita a 10 conexões novas por minuto** — mesmo que alguém tente forçar entrada, o firewall já derruba na velocidade
- Recarrega o firewall pra aplicar

```bash
sudo sshd -t
```
Testa se o arquivo de configuração tá com sintaxe correta ANTES de aplicar de verdade — evita quebrar o SSH por um erro de digitação.

```bash
sudo systemctl reload sshd
```
Aplica a configuração nova SEM derrubar as conexões já abertas (diferente de "restart", que fecharia tudo).

---

## 4. Opções de montagem (`/etc/fstab`)

Cada ponto de montagem (`/tmp`, `/home`, etc.) pode ter "regras extras" de como o sistema trata ele. As três que usamos:

- **`nodev`** — não deixa criar "arquivos de dispositivo" ali (tipo simular um HD falso). Serve pra área que só devia guardar arquivo normal.
- **`nosuid`** — ignora a permissão especial "SUID" em qualquer binário ali dentro. SUID é o que deixa um programa rodar com permissão de outro usuário (tipo rodar como root mesmo sendo usuário comum) — é um vetor clássico de ataque se alguém conseguir colocar um binário malicioso numa pasta gravável.
- **`noexec`** — não deixa RODAR nenhum programa que esteja dentro dessa pasta (só ler/escrever arquivo, não executar).

Por que cada pasta recebeu um conjunto diferente: `/tmp`, `/var/tmp`, `/var/log` recebem as três (ninguém deveria estar executando programa nem criando dispositivo ali, é só área de arquivo temporário/log). `/home` só recebe `nodev`+`nosuid` porque usuário comum PRECISA poder rodar programa (script próprio, etc.) dentro da própria pasta. `/var` só recebe `nodev` porque serviços do sistema às vezes precisam executar coisa de lá.

---

## 5. O script `net-hardening.sh`

### O que ele resolve, na prática

Automatiza três coisas que dariam pra fazer na mão (a gente já fez SSH na mão), mas de um jeito que pode rodar de novo sem quebrar nada:

1. **Auditoria** (`--audit`): olha quais portas tão abertas na máquina (`ss -tulpn`) e compara com uma lista de portas que DEVERIAM estar abertas. Se achar algo fora da lista, avisa.
2. **Aplicação** (`--apply`): ajusta parâmetros do kernel relacionados a rede (`sysctl`) e cria uma regra de firewall com limite de taxa — sem nunca remover a regra que sustenta a SUA PRÓPRIA sessão SSH atual (ele detecta isso lendo a variável `SSH_CONNECTION`).
3. **Reversão** (`--rollback`): desfaz o que o `--apply` fez, restaurando backup.

### Conceitos-chave usados na programação dele (isso é o tipo de coisa que o professor pode perguntar)

- **`set -euo pipefail`** — trava o script inteiro se qualquer comando falhar, se usar variável não definida, ou se um comando no meio de um "pipe" (`|`) falhar. Sem isso, um erro no meio passaria batido e o script continuaria rodando com o sistema em estado inconsistente.
- **`trap ... EXIT`** — registra uma função de limpeza que roda sempre que o script termina (com sucesso OU com erro), garantindo que arquivos temporários sejam apagados.
- **Idempotência** — rodar o comando várias vezes seguidas dá sempre o mesmo resultado final (não duplica regra, não reescreve arquivo à toa). Testamos isso rodando `--apply` duas vezes.
- **Exit codes com significado** — `0` sucesso, `1` achou algo na auditoria, `2` uso errado do comando, `3` faltou permissão/dependência. Isso permite outros scripts/sistemas de monitoramento saberem o que aconteceu só olhando o número, sem precisar ler o texto.

### O bug real que encontramos rodando de verdade

`IFS=$'\n\t'` no topo do script (linha global, prática comum) quebrou um `read` específico lá dentro, que dependia do espaço como separador. Resultado: a auditoria SEMPRE dizia "sem achados", mesmo com portas erradas abertas — um bug silencioso, sem mensagem de erro nenhuma, só o resultado errado. Corrigimos isolando o `IFS` só naquele comando (`while IFS=' ' read -r proto local_addr`). Isso é ótimo de mencionar na apresentação: mostra que vocês testaram de verdade, não só rodaram uma vez e confiaram.

---

## Perguntas que o professor pode fazer (e a resposta curta)

- **"Por que não criptografar cada LV separado, em vez de um container só?"** → Um container só pede a senha uma vez no boot; LV separado pediria senha pra cada volume, e qualquer LV novo criado depois nasceria SEM criptografia (teria que lembrar de criptografar toda vez).
- **"Por que limitar taxa de conexão em vez de só bloquear IP?"** → Bloquear IP fixo é fácil de contornar (IP dinâmico, VPN). Limitar TAXA (quantas conexões por minuto) freia qualquer origem, sem precisar saber de antemão quem é o atacante.
- **"O que acontece se o script tentar remover a regra da sua própria sessão SSH no rollback?"** → Ele detecta a porta da sessão atual e PULA a remoção dessa regra específica, registrando isso como erro — proteção contra se autoexcluir do próprio servidor remotamente.
