# Estrutura da apresentação — 30 minutos (Grupo 4 / Oracle Linux)

| Tempo | Bloco | Conteúdo | Baseado em |
|---|---|---|---|
| 4 min | Abertura e distribuição | Quem mantém o Oracle Linux, ciclo de vida, quando escolher (vs RHEL/Rocky/Alma), e a distribuição de tarefas dentro do grupo | `05-pesquisa-notas.md` |
| 5 min | Esquema de particionamento | Diagrama LVM sobre LUKS e a justificativa de cada decisão (por que /boot fica de fora, por que espaço livre é requisito) | `01-particionamento.md` |
| 7 min | Instalação com LVM e LUKS | Vídeo acelerado ou demonstração ao vivo, comentando os pontos críticos (Encrypt no Anaconda, SELinux enforcing) | `02-INSTALL.md` |
| 6 min | Serviço SSH endurecido | Mostrar acesso por chave funcionando e uma tentativa bloqueada, ao vivo | `03-ssh-hardening.md` |
| 5 min | Script em shell | Arquitetura do `net-hardening.sh` (funções, modos, --dry-run) e execução ao vivo com saída real | `04-net-hardening.sh` |
| 3 min | Cinco perguntas | Aplicar o questionário à turma | abaixo |

**Total: 30 min, cronometrado.** Descontam 2 pontos por minuto excedido. Todo mundo do grupo precisa apresentar uma parte — quem não apresenta não recebe a nota de apresentação.

## Slides sugeridos por bloco (referência, não obrigatório)

1. Capa (grupo, integrantes, distro)
2. Por que Oracle Linux — panorama (UEK vs RHCK, Ksplice, licenciamento)
3. Diagrama de particionamento
4. Justificativa das opções de montagem (nodev/nosuid/noexec)
5-7. Passos-chave da instalação (screenshots reais da VM de vocês)
8. Evidências: lsblk -f, cryptsetup luksDump, pvs/vgs/lvs
9. Config do sshd (itens endurecidos)
10. Evidência: acesso por chave + tentativa bloqueada
11. Arquitetura do net-hardening.sh (funções, fluxo)
12. Execução ao vivo / saída real do script
13-17. As 5 perguntas (1 slide pergunta + 1 slide resposta comentada, cada)
18. Referências

---

# Rascunho das 5 perguntas para a turma

Regras: toda pergunta precisa ser respondível só com o que foi apresentado (pergunta sobre conteúdo não apresentado é anulada). Gabarito comentado entregue ao professor 48h antes.

> Ajustem a redação depois que os slides finais estiverem prontos — o conteúdo abaixo é um ponto de partida, não o texto final.

### Múltipla escolha 1

**Por que, no esquema de particionamento deste trabalho, `/boot` e `/boot/efi` ficam de fora do container LUKS?**

a) Porque XFS não suporta criptografia
b) Porque o GRUB precisa ler o kernel e o initramfs antes de existir qualquer chave de descriptografia — não há como o bootloader ler algo que já está criptografado
c) Porque a UEFI exige que toda a partição de boot esteja sem criptografia por lei
d) Porque o LUKS não suporta partições menores que 2 GB

**Resposta: b**

### Múltipla escolha 2

**Qual é a função da rich rule com limite de taxa (`limit value="10/m"`) aplicada pelo `net-hardening.sh` no firewalld?**

a) Bloquear permanentemente qualquer IP que tente se conectar
b) Limitar a banda total disponível para a porta SSH
c) Restringir a quantidade de novas conexões aceitas por minuto naquela porta, mitigando tentativas de força bruta
d) Impedir que o próprio administrador se reconecte depois de um tempo de inatividade

**Resposta: c**

### Múltipla escolha 3

**No modelo comercial da Oracle para o Oracle Linux, o que exatamente é pago?**

a) O download e a instalação do sistema operacional
b) A licença por número de servidores em produção
c) Apenas os níveis de suporte (Basic, Premier, Premier Plus) — o sistema operacional em si é gratuito
d) Somente o uso do kernel UEK; o RHCK é pago à parte

**Resposta: c**

### Dissertativa 1

**Por que o `net-hardening.sh` se recusa a remover a regra de firewall que sustenta a sessão SSH atual de quem está executando o rollback? O que aconteceria se ele não tivesse essa proteção?**

*Resposta esperada (até 3 linhas):* Porque removê-la derrubaria a própria conexão de quem está administrando o servidor remotamente, deixando o sistema potencialmente inacessível (é preciso outro caminho de acesso, como console físico/virtual, para corrigir). O script detecta a porta da sessão atual via `SSH_CONNECTION` e pula a remoção dessa regra específica, registrando um erro em vez de aplicar a mudança.

### Dissertativa 2

**Por que "espaço livre no volume group" é tratado como requisito no esquema de particionamento, e não como desperdício de disco?**

*Resposta esperada (até 3 linhas):* Sem espaço livre no VG não é possível tirar snapshot de um LV nem estender (`lvextend`) um volume que ficou cheio — o LVM precisa desse espaço reservado para essas operações. Um VG ocupado a 100% não é eficiência, é a ausência de qualquer margem para manutenção ou recuperação.
