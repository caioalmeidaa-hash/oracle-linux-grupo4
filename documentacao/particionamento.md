# Esquema de particionamento — LVM sobre LUKS (Oracle Linux)

Disco principal de 60 GB. Segue o esquema de referência do trabalho, adaptado.

```
sda1   /boot/efi   1 GB    FAT32                    fora da criptografia
sda2   /boot       1 GB    xfs                      fora da criptografia

sda3   ~58 GB      LUKS2   container criptografado
  └── VG vg_sistema   (PV = /dev/mapper/cryptlvm)
        lv_root     15 G   /
        lv_var       8 G   /var
        lv_varlog    5 G   /var/log
        lv_vartmp    3 G   /var/tmp
        lv_home     10 G   /home
        lv_tmp       3 G   /tmp
        lv_swap      4 G   swap
        espaço livre ~9 G  reservado para snapshots
```

## Por que cada decisão

**Tudo dentro de um único LUKS container.** Um único container criptografado (`sda3`) com o volume group inteiro dentro. Só uma passphrase é pedida no boot, e qualquer LV novo criado depois já nasce criptografado — não precisamos criptografar disco por disco.

**`/boot` e `/boot/efi` ficam de fora da criptografia.** O GRUB precisa ler o kernel e o initramfs antes de existir qualquer chave — não dá pra criptografar o que o bootloader lê primeiro. Esse é o risco residual do esquema: um atacante com acesso físico pode alterar o `/boot` sem passar pela passphrase do LUKS. Mitigação possível (bônus, não obrigatório): assinar o boot com Secure Boot, ou usar `/boot` em outro storage protegido.

**Espaço livre (~9 GB) no VG é requisito, não sobra.** Sem espaço livre não dá pra tirar snapshot de LV nem socorrer um volume que encheu (`lvextend`). VG a 100% de uso não é otimização, é um problema esperando acontecer.

**Segundo disco de 20 GB, adicionado depois.** Exercício de ciclo de vida do LVM: `pvcreate` no disco novo → `vgextend vg_sistema /dev/sdb1` → escolher qual LV precisa crescer (ex.: `lv_home` ou `lv_var`) → `lvextend` → `xfs_growfs` a quente, sem desmontar.

## Opções de montagem por partição (bloqueiam ataques específicos)

| Ponto de montagem | Opções | O que impede |
|---|---|---|
| `/tmp` e `/var/tmp` | `nodev,nosuid,noexec` | Executar payload gravado em diretório mundialmente gravável — vetor clássico de escalonamento de privilégio |
| `/home` | `nodev,nosuid` | Usuário comum criar binário SUID dentro do próprio diretório |
| `/var/log` | `nodev,nosuid,noexec` | Protege integridade dos logs e impede que a área de log vire staging de ataque |
| `/boot` e `/var` | `nodev` (+ `nosuid` no `/boot`) | Isola crescimento de dados de serviço e protege a área de boot |

**Atenção:** `noexec` em `/var` pode quebrar containers (se o grupo rodar algo em `/var/lib/containers`); `noexec` em `/var/tmp` pode quebrar atualização de pacote que descompacta ali antes de instalar. Testem antes de entregar — se der conflito, documentem a decisão que tomaram (manter vs relaxar a opção) no guia de instalação. Documentar o trade-off vale mais nota do que só copiar a tabela sem testar.

## Comandos de evidência a coletar (colar saída real no INSTALL.md e no repositório)

```bash
lsblk -f
cryptsetup luksDump /dev/sda3
pvs; vgs; lvs
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
cat /etc/fstab
cat /etc/crypttab
```

## Extensão do disco secundário (exercício obrigatório, fazer depois da instalação)

```bash
# disco novo já anexado à VM como /dev/sdb (20 GB)
sudo parted /dev/sdb --script mklabel gpt mkpart primary 0% 100%
sudo pvcreate /dev/sdb1
sudo vgextend vg_sistema /dev/sdb1
sudo lvextend -L +15G /dev/vg_sistema/lv_home
sudo xfs_growfs /home
df -h /home
```
