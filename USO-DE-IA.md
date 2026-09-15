# Declaração de uso de IA generativa

Conforme permitido pelo enunciado do CP 02 ("Uso de IA generativa é permitido como apoio, desde que declarado"), o Grupo 4 declara o uso da ferramenta **Claude (Anthropic)** durante a execução deste trabalho.

## Como foi usada

- Explicação de conceitos (LVM, LUKS, SELinux, autenticação por chave SSH, políticas de criptografia) em formato de perguntas e respostas, pra apoiar o aprendizado antes de aplicar cada mudança na VM.
- Orientação passo a passo durante a instalação do Oracle Linux (particionamento manual no Anaconda, criação de usuário, configuração de rede).
- Depuração de problemas reais encontrados durante a configuração da VM (detalhados em `documentacao/evidencias.md` e no troubleshooting do `documentacao/INSTALL.md`), incluindo:
  - Opções de montagem (`nodev`/`nosuid`/`noexec`) não aplicadas automaticamente pelo Anaconda, corrigidas manualmente no `/etc/fstab`
  - Nome incorreto do pacote de cabeçalhos de kernel para o kernel UEK da Oracle (`kernel-uek-devel` em vez de `kernel-devel`)
  - Erro de sintaxe numa rich rule do `firewalld` (`service` e `port` não podem coexistir na mesma regra)
  - Ajuste de redirecionamento de porta no VirtualBox após a mudança da porta do SSH
- Redação e revisão de textos de documentação (guia de instalação, roteiro de apresentação, evidências).
- Organização do repositório Git (estrutura de pastas, commit inicial).

## Responsabilidade

Todo o conteúdo técnico gerado com apoio da IA foi executado e verificado manualmente na VM do grupo, com evidência real coletada por comando (não simulada). A revisão final do conteúdo é de responsabilidade do grupo.
