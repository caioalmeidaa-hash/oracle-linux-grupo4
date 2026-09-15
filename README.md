# CP 02 — Ambiente Linux (RHEL) — Grupo 4 — Oracle Linux

Trabalho da disciplina de Segurança/Linux (FIAP). O Grupo 4 ficou responsável pela distribuição **Oracle Linux**, com instalação segura (LVM sobre LUKS + SELinux), serviço SSH endurecido e script de hardening de rede.

## Status

🟡 Em andamento. Instalação do ambiente e SSH já concluídos e documentados com evidência real. Faltam: documento de pesquisa final, slides, 5 perguntas pra turma e revisão final do script.

## Estrutura do repositório

```
documentacao/
  INSTALL.md            → guia de instalação reproduzível (LVM sobre LUKS)
  particionamento.md    → esquema de particionamento e justificativas
  ssh-hardening.md      → passo a passo do hardening do SSH
  evidencias.md         → saídas reais de comando coletadas na VM (não são prints)
  pesquisa-notas.md     → notas de pesquisa (UEK vs RHCK, Ksplice, licenciamento)
  guia-explicativo.md   → material de apoio/explicação do grupo

apresentacao/
  outline.md                    → estrutura planejada dos slides
  roteiro-apresentacao-ssh.md   → roteiro de fala da parte de SSH

scripts/
  net-hardening.sh                  → script de hardening de rede/firewalld
  portas-autorizadas.txt.exemplo    → exemplo de lista de portas autorizadas
```

## Distribuição e recorte de pesquisa

- Distribuição: **Oracle Linux** (UEK vs RHCK, Ksplice, licenciamento)
- Particionamento: LVM sobre LUKS, com cada volume lógico (`/`, `/home`, `/var`, `/var/log`, `/var/tmp`, `/tmp`, swap) criptografado individualmente
- SSH: autenticação só por chave (ed25519), sem login root, porta não padrão (6767), grupo de acesso dedicado, limites de tentativa e taxa, banner legal
- Script: `net-hardening.sh` — inventário de portas, parâmetros sysctl, zona dedicada no firewalld com rich rule de limite de taxa

Veja `documentacao/evidencias.md` para a saída real de comandos comprovando cada item.

## Uso de IA

Este projeto usou apoio de IA generativa (Claude) durante configuração, depuração e documentação — declarado em [`USO-DE-IA.md`](./USO-DE-IA.md), conforme exigido pelo enunciado.
