# Evidências coletadas — Grupo 4 / Oracle Linux

Saída real da VM (texto, não print), coletada durante a configuração. Organizado por etapa, pronto pra colar no repositório/relatório.

---

## 1. SSH endurecido

Evidência coletada na instalação final (15/09/2026), na VM já com particionamento e SELinux confirmados.

### 1.1 Configuração efetiva (`sshd -T`, itens relevantes)

```
port 6767
logingracetime 30
maxauthtries 3
clientaliveinterval 300
clientalivecountmax 2
permitrootlogin no
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
authenticationmethods publickey
allowgroups ssh-users
banner /etc/issue.net
```

### 1.2 Política de criptografia do sistema (`update-crypto-policies`)

```
$ sudo update-crypto-policies --set DEFAULT
Setting system policy to DEFAULT
$ update-crypto-policies --show
DEFAULT
```

### 1.3 Firewall (`firewall-cmd --list-all`)

```
public (active)
  target: default
  icmp-block-inversion: no
  interfaces: enp0s3
  sources:
  services: cockpit dhcpv6-client
  ports: 6767/tcp
  protocols:
  forward: yes
  masquerade: no
  forward-ports:
  source-ports:
  icmp-blocks:
  rich rules:
        rule family="ipv4" port port="6767" protocol="tcp" accept limit value="10/m"
```

Nota: a porta 22 (padrão) não aparece em `services` nem em `ports` — foi removida deliberadamente (`--remove-service=ssh`), só a porta 6767 fica exposta. (Achado real: a primeira tentativa de rich rule usando `service name="ssh"` junto com `port port="6767"` foi recusada pelo firewalld — `INVALID_RULE: more than one element` — porque uma rich rule não aceita `service` e `port` ao mesmo tempo. Corrigido removendo o `service name="ssh"` e deixando só o `port`.)

### 1.4 Porta em escuta (`ss -tulpn`, filtrado pro sshd)

```
tcp   LISTEN 0      128          0.0.0.0:6767      0.0.0.0:*
tcp   LISTEN 0      128             [::]:6767         [::]:*
```

Só a 6767 — nenhum processo escutando na 22.

### 1.5 Rótulo SELinux da porta (`semanage port -l | grep ssh`)

```
ssh_port_t                     tcp      6767, 22
```

### 1.6 Log de autenticação (`journalctl -u sshd`)

Acesso aceito por chave, já com a configuração final aplicada:

```
set 15 15:54:43 localhost.localdomain sshd-session[2493]: Accepted publickey for calmeida from 10.0.2.2 port 32209 ssh2: ED25519 SHA256:RaqL2cNnFO075G7vTyVbocsGSC8ubQc+wffqdI/JxX8
```

Tentativa de autenticação só por senha, corretamente bloqueada (comando de teste: `ssh -p 6767 -o PreferredAuthentications=password calmeida@127.0.0.1`, resultado no cliente: `Permission denied (publickey)`):

```
set 15 16:02:03 localhost.localdomain sshd-session[2598]: Connection closed by authenticating user calmeida 127.0.0.1 port 39612 [preauth]
```

**Por que essa linha, e não "Failed password":** como `PasswordAuthentication no` e `AuthenticationMethods publickey` já removem a senha das opções oferecidas pelo servidor, um cliente que só oferece senha não consegue nem negociar um método de autenticação em comum — a conexão é encerrada antes de chegar a registrar uma tentativa de senha propriamente dita. É a evidência de bloqueio válida para esse cenário. (A mensagem exata varia entre versões do OpenSSH — "Connection reset by..." ou "Connection closed by..." — o significado é o mesmo: nenhum método em comum, conexão recusada.)

### 1.7 Teste de acesso pela porta antiga (22)

Confirmado indiretamente pelos itens 1.3 e 1.4: nem o serviço `ssh`/porta 22 aparece liberado no firewall, nem o `sshd` escuta nela — só a 6767.

---

## 2. Particionamento — LVM sobre LUKS (`lsblk -f`)

Confirma a árvore completa: `sda1`/`sda2` fora da criptografia (bootloader), `sda3` como membro LVM (`LVM2_member`), VG `ol`, e cada volume lógico com sua própria camada `crypto_LUKS` individual por cima antes do sistema de arquivos.

```
NAME          FSTYPE       LABEL  UUID                                   MOUNTPOINTS
sda
├─sda1        vfat         BCE1-6130                                    /boot/efi
├─sda2        xfs          90e4a3a4-08f8-46ce-85aa-fa97117f7802          /boot
└─sda3        LVM2_member  u J91sA-b9Sn-JEl1-ISZ9-95if-GyPh-T2uQTf
  ├─ol-root   crypto_LUKS  d404f2c3-d6ba-4a93-849f-067144d8ce18
  │ └─luks-d404f2c3-d6ba-4a93-849f-067144d8ce18  xfs  08bb4419-4948-4c57-9b87-11de1372f18c  /
  ├─ol-swap   crypto_LUKS  44a1cf78-a892-4ea6-9b4f-55129c702682
  │ └─luks-44a1cf78-a892-4ea6-9b4f-55129c702682  swap 20ebdec1-de13-4b5a-abeb-92e9be9f7e25  [SWAP]
  ├─ol-tmp    crypto_LUKS  a3f61777-e4b6-4e16-8b36-85c978354fdf
  │ └─luks-a3f61777-e4b6-4e16-8b36-85c978354fdf  xfs  c2734d54-736a-4652-897d-3100b734ba73  /tmp
  ├─ol-home   crypto_LUKS  45329b12-2968-4bc0-8828-1903f9ecad3b
  │ └─luks-45329b12-2968-4bc0-8828-1903f9ecad3b  xfs  c598ced0-ee9d-4b31-9030-cf95fe029efd  /home
  ├─ol-var_log crypto_LUKS f553840f-dd81-4192-8d18-af9705802136
  │ └─luks-f553840f-dd81-4192-8d18-af9705802136  xfs  266c37db-b3ed-4df8-8550-1a84a01bd6de  /var/log
  ├─ol-var    crypto_LUKS  41f8274d-3983-484b-a1a5-831c902d0d71
  │ └─luks-41f8274d-3983-484b-a1a5-831c902d0d71  xfs  58347129-2814-4489-9f59-3d3ee208412a  /var
  └─ol-var_tmp crypto_LUKS a73bb823-861b-4ab8-9afc-0052c16be3a9
    └─luks-a73bb823-861b-4ab8-9afc-0052c16be3a9  xfs  7eadc866-a30e-40dd-bf0b-d3945384e472  /var/tmp
```

## 3. Opções de montagem (`findmnt`)

```
TARGET      SOURCE                                                    FSTYPE  OPTIONS (relevantes)
/boot       /dev/sda2                                                 xfs     rw,nosuid,nodev,relatime
/boot/efi   /dev/sda1                                                 vfat    rw,relatime (herdado do FAT32 — nosuid/nodev/noexec não se aplicam)
/var        luks-41f8274d-3983-484b-a1a5-831c902d0d71                 xfs     rw,nodev,relatime
/var/tmp    luks-a73bb823-861b-4ab8-9afc-0052c16be3a9                 xfs     rw,nosuid,nodev,noexec,relatime
/var/log    luks-f553840f-dd81-4192-8d18-af9705802136                 xfs     rw,nosuid,nodev,noexec,relatime
/home       luks-45329b12-2968-4bc0-8828-1903f9ecad3b                 xfs     rw,nosuid,nodev,relatime
/tmp        luks-a3f61777-e4b6-4e16-8b36-85c978354fdf                 xfs     rw,nosuid,nodev,noexec,relatime
```

**Achado real durante a instalação:** o Anaconda NÃO aplicou essas opções sozinho — o `/etc/fstab` gerado por ele só tinha `defaults,x-systemd.device-timeout=0` em todas as linhas. Corrigido manualmente depois do primeiro boot:

1. Backup: `sudo cp /etc/fstab /etc/fstab.bak-$(date +%F)`
2. Editado com `sed -i` (uma expressão por volume, usando o identificador único de cada `luks-<uuid>` pra não confundir `/var` com `/var/log`/`/var/tmp`) pra acrescentar `nodev`/`nosuid`/`noexec` conforme a tabela do `01-particionamento.md`
3. Aplicado sem reiniciar: `sudo systemctl daemon-reload` + `sudo mount -o remount <ponto>` em cada volume
4. Confirmado com `findmnt` (saída acima) — bate exatamente com a tabela planejada, sem precisar de reboot

Isso confirma o próprio aviso do guia de instalação (`02-INSTALL.md`, passo 3.5): "se o Anaconda não expuser essas opções, editem `/etc/fstab` e remontem depois."

---

## 4. Script `net-hardening.sh` — ciclo completo de testes

### 4.1 `--help` (não deve alterar nada, saída 0)

Confirmado: mostrou o texto de uso e saiu com código 0.

### 4.2 Bug real encontrado e corrigido durante o teste

O script usa `IFS=$'\n\t'` global (boa prática comum de hardening), mas isso quebrava silenciosamente a leitura da saída do `ss` dentro da função `inventario_portas` — o `while read -r proto local_addr` parava de separar por espaço, então a porta nunca era reconhecida e a auditoria sempre retornava "sem achados", mesmo com portas não autorizadas abertas.

**Antes da correção** (`--audit`, sem lista de portas configurada — deveria acusar todas como não autorizadas e não acusou):

```
[INFO] inventariando portas em escuta (ss -tulpn)...
[INFO] inventário concluído sem achados.
saída: 0
```

**Correção aplicada** (isolar o `IFS` só nessa leitura, sem mudar o padrão do resto do script):

```bash
# antes
while read -r proto local_addr; do

# depois
while IFS=' ' read -r proto local_addr; do
```

**Depois da correção**, mesmo cenário (sem lista de portas configurada):

```
[WARN] lista de portas autorizadas não encontrada em /etc/net-hardening/portas-autorizadas.txt; tratando todas as portas como não autorizadas.
[INFO] inventariando portas em escuta (ss -tulpn)...
[WARN] porta NÃO autorizada em escuta: 323/udp
[WARN] porta NÃO autorizada em escuta: 323/udp
[WARN] porta NÃO autorizada em escuta: 6767/tcp
[WARN] porta NÃO autorizada em escuta: 6767/tcp
[WARN] inventário concluído com 4 porta(s) não autorizada(s).
saída: 1
```

### 4.3 `--audit` com a lista de portas autorizadas configurada (`/etc/net-hardening/portas-autorizadas.txt` com `6767/tcp` e `323/udp`)

```
[INFO] inventariando portas em escuta (ss -tulpn)...
[INFO] porta autorizada em escuta: 323/udp
[INFO] porta autorizada em escuta: 323/udp
[INFO] porta autorizada em escuta: 6767/tcp
[INFO] porta autorizada em escuta: 6767/tcp
[INFO] inventário concluído sem achados.
saída: 0
```

### 4.4 `--apply --dry-run`

```
[INFO] [dry-run] escreveria /etc/sysctl.d/99-net-hardening.conf com 9 parâmetro(s) e rodaria 'sysctl --system'.
[INFO] [dry-run] criaria a zona 'hardened-mgmt'.
[WARN] não foi possível detectar a porta da sessão atual (SSH_CONNECTION vazio); usando porta 22 como referência.
[INFO] [dry-run] adicionaria rich rule: rule family="ipv4" port port="22" protocol="tcp" accept limit value="10/m"
[INFO] hardening de rede aplicado com sucesso.
```

Nota: o teste foi feito direto no console da VM (login local), não por SSH — por isso `SSH_CONNECTION` estava vazio e o script usou a porta 22 como referência de segurança (comportamento de fallback esperado e documentado no próprio script).

### 4.5 `--apply` (execução real)

```
[INFO] parâmetros sysctl aplicados e persistidos em /etc/sysctl.d/99-net-hardening.conf.
[INFO] zona 'hardened-mgmt' criada.
[WARN] não foi possível detectar a porta da sessão atual (SSH_CONNECTION vazio); usando porta 22 como referência.
[INFO] rich rule de limite de taxa (10/m) aplicada para a porta 22.
[INFO] firewalld recarregado.
[INFO] hardening de rede aplicado com sucesso.
```

Confirmado no sistema depois de aplicado:

```
$ sudo firewall-cmd --permanent --zone=hardened-mgmt --list-all
hardened-mgmt
  target: default
  ...
  rich rules:
        rule family="ipv4" port port="22" protocol="tcp" accept limit value="10/m"

$ sudo sysctl net.ipv4.tcp_syncookies net.ipv4.conf.all.rp_filter
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
```

### 4.6 Idempotência — rodando `--apply` de novo

```
[INFO] sysctl já aplicado, nenhuma mudança necessária (idempotente).
[INFO] zona 'hardened-mgmt' já existe (idempotente).
[WARN] não foi possível detectar a porta da sessão atual (SSH_CONNECTION vazio); usando porta 22 como referência.
[INFO] rich rule de limite de taxa para a porta 22 já existe (idempotente).
[INFO] firewalld recarregado.
[INFO] hardening de rede aplicado com sucesso.
```

Rodar duas vezes seguidas não duplicou nada — confirma a idempotência descrita no cabeçalho do script.

### 4.7 `--rollback --dry-run`

```
[INFO] [dry-run] removeria /etc/sysctl.d/99-net-hardening.conf (nenhum backup anterior encontrado).
[INFO] [dry-run] removeria rich rule: rule family="ipv4" port port="22" protocol="tcp" accept limit value="10/m"
[INFO] rollback concluído.
```

---

## 5. Verificação pós-instalação — SELinux

Primeiro login na VM recém-instalada, confirmando que o SELinux não foi desligado (item avaliado na rubrica).

### 5.1 `getenforce`

```
Enforcing
```

### 5.2 `sestatus`

```
SELinux status:                 enabled
SELinuxfs mount:                /sys/fs/selinux
SELinux root directory:         /etc/selinux
Loaded policy name:             targeted
Current mode:                   enforcing
Mode from config file:          enforcing
Policy MLS status:              enabled
Policy deny_unknown status:     allowed
Memory protection checking:     actual (secure)
Max kernel policy version:      33
```

---

## Resumo dos códigos de saída observados

| Comando | Código de saída | Esperado |
|---|---|---|
| `--help` | 0 | ✅ |
| `--audit` (sem lista configurada, com portas abertas) | 1 | ✅ |
| `--audit` (com lista configurada, tudo autorizado) | 0 | ✅ |
| `--apply` / `--apply --dry-run` | 0 | ✅ |
| `--rollback --dry-run` | 0 | ✅ |
