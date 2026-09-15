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

## 4. SELinux

Deixar o padrão do instalador: **Enforcing**. Não desliguem — vale -10 pontos na rubrica se o SELinux estiver desligado. Confirmar depois da instalação:

```bash
getenforce      # deve responder: Enforcing
sestatus
```

## 5. Finalizar instalação

- Criar o usuário administrador (não usar `root` direto — o hardening do SSH vai exigir `PermitRootLogin no` e acesso nominal + `sudo`)
- Reiniciar, remover a mídia de instalação

## 6. Primeira verificação pós-instalação

```bash
cat /etc/os-release
uname -r
lsblk -f
cryptsetup luksDump /dev/sda3
pvs; vgs; lvs
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
cat /etc/fstab
cat /etc/crypttab
```

**Tirar snapshot da VM agora**, antes de mexer em qualquer configuração.

## 7. Extensão do disco secundário (depois de tudo funcionando)

Ver o passo a passo completo em `01-particionamento.md`, seção final (`pvcreate` → `vgextend` → `lvextend` → `xfs_growfs`).

## 8. Troubleshooting (preencham com o que o grupo realmente encontrar)

| Sintoma | Causa provável | Solução |
|---|---|---|
| VM não boota, cai em shell do GRUB | Firmware criado como BIOS em vez de UEFI | Recriar a VM com firmware UEFI antes de reinstalar |
| Anaconda não oferece opção "Encrypt" no LVM | Storage Configuration ainda em modo "Automatic" | Voltar e escolher **Custom** na tela de destino |
| Esqueci a passphrase do LUKS | — | Não há recuperação. Reinstalar. (Por isso o snapshot pré-configuração é obrigatório) |
| `lvextend`/`xfs_growfs` falha depois de adicionar o segundo disco | VG não foi estendido (`vgextend`) antes do `lvextend` | Rodar `vgs` para confirmar que o PV novo está no VG certo |
| _(preencher com problemas reais do grupo)_ | | |

> Completem esta seção com os erros que realmente baterem na instalação de vocês — é isso que o professor quer ver, não uma lista genérica.
