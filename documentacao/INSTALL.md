# INSTALL.md — Instalação segura do Oracle Linux (LVM sobre LUKS)

Guia reproduzível. Testem cada passo na VM real do grupo e substituam os prints/saídas de exemplo pelos de vocês — o professor confere se bate.

## 1. Pré-requisitos

- Hipervisor: VirtualBox, VMware, KVM/QEMU ou Proxmox
- ISO do Oracle Linux (baixar em oracle.com/linux/technologies/oracle-linux-downloads.html — peguem a versão mais recente estável, ex. Oracle Linux 9 ou 10)
- Conferir o hash antes de instalar:
  ```bash
  sha256sum OracleLinux-*.iso
  # comparar com o checksum publicado na página de download da Oracle
  ```

## 2. Criar a VM

| Parâmetro | Valor |
|---|---|
| Firmware | UEFI (nunca BIOS legado) |
| Disco principal | 60 GB |
| Disco secundário | 20 GB (adicionar só depois da instalação — ver `01-particionamento.md`) |
| Memória / vCPU | 4 GB / 2 vCPU |
| Rede | NAT ou Host-Only — nunca Bridge exposto |
| Modo de instalação | Server sem GUI / Minimal Install |

## 3. Particionamento manual no Anaconda

O instalador do Oracle Linux é o mesmo Anaconda do RHEL. Na tela de instalação:

1. **Installation Destination** → selecionar o disco de 60 GB → **Storage Configuration: Custom** → Done
2. Criar as partições **fora** do LVM primeiro:
   - `/boot/efi` — 1 GiB — FAT32 (tipo "EFI System Partition")
   - `/boot` — 1 GiB — xfs
3. Criar o volume group criptografado:
   - Clicar em `+` para o restante do disco (~58 GiB), **Mount point: deixar em branco por enquanto**, **Device type: LVM**
   - Marcar a caixa **Encrypt** — é isso que cria o container LUKS2 como PV único por baixo do VG (`vg_sistema`)
   - Definir a passphrase do LUKS agora — **anotem em lugar seguro, não existe recuperação sem ela**
4. Dentro do VG `vg_sistema`, criar cada Logical Volume com o tamanho e ponto de montagem da tabela do `01-particionamento.md`: `lv_root` (/), `lv_var` (/var), `lv_varlog` (/var/log), `lv_vartmp` (/var/tmp), `lv_home` (/home), `lv_tmp` (/tmp), `lv_swap` (swap). **Não usar os 58 GiB inteiros** — deixem ~9 GiB de espaço livre no VG.
5. Em cada LV que precisa de opções restritivas (`/tmp`, `/var/tmp`, `/home`, `/var/log`, `/boot`), usar **Customize** → aba de opções de montagem para acrescentar `nodev`, `nosuid`, `noexec` conforme a tabela do `01-particionamento.md`. Se o Anaconda não expuser essas opções na tela, editem `/etc/fstab` logo após a instalação e rodem `mount -o remount <ponto>` para aplicar sem reiniciar.
6. Confirmar o resumo de mudanças → voltar para a tela principal

### Evidência real (Grupo 4)

`lsblk -f` depois da instalação, confirmando `sda3` como membro do LVM (`ol`) e cada volume lógico com sua própria camada `crypto_LUKS` individual (não é um único LUKS container pra tudo — cada gaveta tem seu próprio cadeado):

```
NAME          FSTYPE       LABEL  UUID                                   MOUNTPOINTS
sda
├─sda1        vfat         BCE1-6130                                    /boot/efi
├─sda2        xfs          90e4a3a4-08f8-46ce-85aa-fa97117f7802          /boot
└─sda3        LVM2_member  uJ91sA-b9Sn-JEl1-ISZ9-95if-GyPh-T2uQTf
  ├─ol-root   crypto_LUKS  d404f2c3-d6ba-4a93-849f-067144d8ce18
  │ └─luks-d404f2c3...     xfs                                           /
  ├─ol-swap   crypto_LUKS  44a1cf78-a892-4ea6-9b4f-55129c702682
  │ └─luks-44a1cf78...     swap                                          [SWAP]
  ├─ol-tmp    crypto_LUKS  a3f61777-e4b6-4e16-8b36-85c978354fdf
  │ └─luks-a3f61777...     xfs                                           /tmp
  ├─ol-home   crypto_LUKS  45329b12-2968-4bc0-8828-1903f9ecad3b
  │ └─luks-45329b12...     xfs                                           /home
  ├─ol-var_log crypto_LUKS f553840f-dd81-4192-8d18-af9705802136
  │ └─luks-f553840f...     xfs                                           /var/log
  ├─ol-var    crypto_LUKS  41f8274d-3983-484b-a1a5-831c902d0d71
  │ └─luks-41f8274d...     xfs                                           /var
  └─ol-var_tmp crypto_LUKS a73bb823-861b-4ab8-9afc-0052c16be3a9
    └─luks-a73bb823...     xfs                                           /var/tmp
```

## 4. SELinux

Deixar o padrão do instalador: **Enforcing**. Não desliguem — vale -10 pontos na rubrica se o SELinux estiver desligado. Confirmar depois da instalação:

```bash
getenforce      # deve responder: Enforcing
sestatus
```

### Evidência real (Grupo 4)

```
$ getenforce
Enforcing

$ sestatus
SELinux status:                 enabled
Loaded policy name:             targeted
Current mode:                   enforcing
Mode from config file:          enforcing
Policy MLS status:              enabled
```

## 5. Finalizar instalação

- Criar o usuário administrador (não usar `root` direto — o hardening do SSH vai exigir `PermitRootLogin no` e acesso nominal + `sudo`)
- Reiniciar, remover a mídia de instalação

## 6. Primeira verificação pós-instalação

```bash
cat /etc/os-release
uname -r
lsblk -f
cryptsetup luksDump /dev/mapper/ol-<nome-do-volume>   # ver nota abaixo sobre o /dev/sda3
pvs; vgs; lvs
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
cat /etc/fstab
cat /etc/crypttab
```

**Atenção — achado real do grupo:** `cryptsetup luksDump /dev/sda3` dá erro ("não é um dispositivo LUKS válido"). Isso é esperado nesse esquema: o LUKS não fica no `sda3` inteiro, fica em cada volume lógico individualmente. Rodem o `luksDump` num volume específico, tipo `/dev/mapper/ol-home`.

### Evidência real (Grupo 4) — `getenforce`/`sestatus` já mostrados acima. Restante:

```
$ cat /etc/os-release
NAME="Oracle Linux Server"
VERSION="9.8"
PLATFORM_ID="platform:el9"
PRETTY_NAME="Oracle Linux Server 9.8"

$ uname -r
6.12.0-203.76.7.3.el9uek.x86_64
```

`/etc/crypttab` — seis volumes com LUKS individual (`ol-root`, `ol-swap`, `ol-tmp`, `ol-home`, `ol-var_log`, `ol-var_tmp`), cada um referenciado pelo próprio UUID:

```
luks-d404f2c3-... UUID=d404f2c3-... none discard
luks-41f8274d-... UUID=41f8274d-... none discard
luks-f553840f-... UUID=f553840f-... none discard
luks-45329b12-... UUID=45329b12-... none discard
luks-a3f61777-... UUID=a3f61777-... none discard
luks-a73bb823-... UUID=a73bb823-... none discard
```

`findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS` (depois de corrigir o `fstab`, ver troubleshooting):

```
TARGET      OPTIONS (relevantes)
/boot       rw,nosuid,nodev,relatime
/boot/efi   rw,relatime (FAT32 não suporta nodev/nosuid/noexec)
/var        rw,nodev,relatime
/var/tmp    rw,nosuid,nodev,noexec,relatime
/var/log    rw,nosuid,nodev,noexec,relatime
/home       rw,nosuid,nodev,relatime
/tmp        rw,nosuid,nodev,noexec,relatime
```

Evidência completa (com UUIDs e saída bruta de cada comando) em [`evidencias.md`](./evidencias.md).

**Tirar snapshot da VM agora**, antes de mexer em qualquer configuração.

## 7. Extensão do disco secundário (depois de tudo funcionando)

Ver o passo a passo completo em `01-particionamento.md`, seção final (`pvcreate` → `vgextend` → `lvextend` → `xfs_growfs`).

## 8. Troubleshooting (problemas reais que o Grupo 4 encontrou)

| Sintoma | Causa provável | Solução |
|---|---|---|
| VM não boota, cai em shell do GRUB | Firmware criado como BIOS em vez de UEFI | Recriar a VM com firmware UEFI antes de reinstalar |
| Anaconda não oferece opção "Encrypt" no LVM | Storage Configuration ainda em modo "Automatic" | Voltar e escolher **Custom** na tela de destino |
| Esqueci a passphrase do LUKS | — | Não há recuperação. Reinstalar. (Por isso o snapshot pré-configuração é obrigatório) |
| `lvextend`/`xfs_growfs` falha depois de adicionar o segundo disco | VG não foi estendido (`vgextend`) antes do `lvextend` | Rodar `vgs` para confirmar que o PV novo está no VG certo |
| `cryptsetup luksDump /dev/sda3` diz "não é um dispositivo LUKS válido" | Nesse esquema o LUKS fica em cada volume lógico, não no `sda3` inteiro (que é só o PV do LVM) | Rodar o `luksDump` no volume específico, ex.: `/dev/mapper/ol-home` |
| `/etc/fstab` só tem `defaults`, sem `nodev`/`nosuid`/`noexec` mesmo configurando isso no Anaconda | O instalador não aplicou as opções customizadas de montagem | `cp /etc/fstab /etc/fstab.bak-$(date +%F)`, editar as linhas dos volumes com `sed`/editor de texto acrescentando as opções da tabela do `01-particionamento.md`, depois `systemctl daemon-reload` + `mount -o remount <ponto>` em cada um — não precisa reiniciar |
| Instalação do Guest Additions falha com pacote `kernel-devel` não encontrado | A VM roda o kernel **UEK** (Unbreakable Enterprise Kernel) da Oracle, não o RHCK — o pacote de cabeçalhos tem nome diferente | Instalar `kernel-uek-devel-$(uname -r)` em vez de `kernel-devel` |
| `firewall-cmd --add-rich-rule` com limite de taxa dá `Error: INVALID_RULE: more than one element` | Uma rich rule não aceita `service name="ssh"` e `port port="..."` ao mesmo tempo | Usar só `port`, sem o `service`, já que a porta foi liberada separadamente |

> Seção completa com os erros reais encontrados na instalação do Grupo 4 — inclui também o bug do `IFS` no `net-hardening.sh`, documentado em [`evidencias.md`](./evidencias.md).
