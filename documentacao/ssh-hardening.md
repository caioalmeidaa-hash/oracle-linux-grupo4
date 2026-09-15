# SSH endurecido — Oracle Linux

**Regra de ouro: nunca fechem a sessão SSH atual antes de validar a nova config numa segunda sessão aberta em paralelo.** Em VM o custo do erro é um snapshot; documentem mesmo assim.

## 0. Antes de mudar qualquer coisa

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak-$(date +%F)
```

## 1. Gerar o par de chaves (na máquina cliente, não no servidor)

```bash
ssh-keygen -t ed25519 -C "grupo4-oracle-linux"
ssh-copy-id -i ~/.ssh/id_ed25519.pub usuario@ip-da-vm
```

## 2. Criar o grupo dedicado e adicionar o usuário administrador

```bash
sudo groupadd ssh-users
sudo usermod -aG ssh-users <seu_usuario>
```

## 3. Editar `/etc/ssh/sshd_config` (ou um drop-in em `/etc/ssh/sshd_config.d/99-hardening.conf`)

```
# Autenticação
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin no
AuthenticationMethods publickey

# Porta e escopo
Port 2222
AllowGroups ssh-users

# Limites contra brute force / abuso
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

# Banner de aviso legal
Banner /etc/issue.net
```

Criar o banner:

```bash
sudo tee /etc/issue.net <<'EOF'
Acesso restrito. Este sistema e monitorado. O uso nao autorizado e proibido
e pode ser processado nos termos do Art. 154-A do Codigo Penal (Lei 12.737/2012).
EOF
```

## 4. Ajustar SELinux para a porta não padrão

O SELinux por padrão só rotula a porta 22 como `ssh_port_t`. Trocar a porta sem isso quebra o serviço (SELinux bloqueia o bind), então:

```bash
sudo semanage port -a -t ssh_port_t -p tcp 2222
semanage port -l | grep ssh
```

(usar `-m` em vez de `-a` se a porta já existir em outra lista e precisar só adicionar o rótulo)

## 5. Firewall — liberar só a porta nova, com limite de taxa

```bash
sudo firewall-cmd --permanent --remove-service=ssh          # tira a regra da porta 22 padrão
sudo firewall-cmd --permanent --add-port=2222/tcp
sudo firewall-cmd --permanent --add-rich-rule='rule service name="ssh" port port="2222" protocol="tcp" accept limit value="10/m"'
sudo firewall-cmd --reload
```

## 6. Política de criptografia do sistema (remove cifras e MACs legados)

```bash
sudo update-crypto-policies --set DEFAULT
# ou FUTURE para uma postura ainda mais restritiva — testem que o SSH ainda conecta antes de fixar essa escolha
update-crypto-policies --show
```

## 7. Validar a sintaxe ANTES de recarregar

```bash
sudo sshd -t && echo "config OK"
```

## 8. Recarregar (não reiniciar, e só depois do `sshd -t` passar)

```bash
sudo systemctl reload sshd
```

## 9. Validar em uma SEGUNDA sessão, mantendo a primeira aberta

```bash
ssh -p 2222 usuario@ip-da-vm            # deve conectar só com a chave
ssh -p 2222 -o PreferredAuthentications=password usuario@ip-da-vm   # deve ser recusado
ssh usuario@ip-da-vm                    # porta 22 antiga: deve falhar (firewall/porta fechada)
```

## 10. Coletar evidências (colar no repositório / documento)

```bash
sshd -T                       # configuração efetiva completa
systemctl status sshd
firewall-cmd --list-all
ss -tulpn
semanage port -l | grep ssh
journalctl -u sshd --since "1 hour ago" | grep -i -E "accepted|failed"
```

Precisam aparecer nas evidências: pelo menos um acesso aceito **por chave** e pelo menos uma tentativa **corretamente bloqueada** (senha recusada, ou usuário fora do `AllowGroups`).

## Checklist final (bate com os 10 itens do slide)

- [ ] Par de chaves ed25519; autenticação por senha desabilitada
- [ ] `update-crypto-policies` aplicado; cifras e MACs legados removidos
- [ ] `PermitRootLogin no` — acesso sempre nominal, `sudo` depois
- [ ] `firewalld` liberando só a porta nova, com rich rule de limite de taxa
- [ ] Porta não padrão, com o rótulo SELinux ajustado via `semanage`
- [ ] Banner de aviso legal em `/etc/issue.net`
- [ ] `AllowGroups` com um grupo dedicado — lista de permissão explícita
- [ ] Registro de autenticação verificado no `journald`
- [ ] `MaxAuthTries 3`, `LoginGraceTime 30`, `ClientAliveInterval 300`
- [ ] Evidência de acesso por chave **e** de tentativa corretamente bloqueada
