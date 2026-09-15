# Notas de pesquisa — Oracle Linux (UEK vs RHCK, Ksplice, Licenciamento)

Isto **não é o documento de pesquisa final** (que precisa ter 12-20 páginas e ser escrito pelo grupo, com análise própria). São notas organizadas com fatos levantados e fontes, pra vocês desenvolverem a redação em cima. Ainda faltam citações primárias adicionais — usem a documentação oficial da Oracle linkada abaixo como ponto de partida pra ir além do que já é primário aqui.

---

## 1. UEK vs RHCK — os dois kernels do Oracle Linux

O Oracle Linux vem com **dois kernels possíveis**, e quem instala escolhe (ou troca depois, sem custo adicional):

- **UEK (Unbreakable Enterprise Kernel)** — kernel próprio da Oracle, é o padrão em uma instalação nova. Baseado em versões mais recentes do kernel mainline (ex.: UEK8 é baseado no kernel 6.12), com ciclo de releases estruturado (UEKx, depois updates U1, U2...). Roda em x86_64 e aarch64. É o kernel recomendado quando o servidor roda produtos Oracle (Oracle Database, WebLogic, etc.), porque é o que a Oracle testa e otimiza primeiro para a própria pilha.
- **RHCK (Red Hat Compatible Kernel)** — versão do kernel mantida para ser binariamente compatível com o kernel do RHEL equivalente (mais conservador — ex.: kernel 5.14 no Oracle Linux 9, mesma base do RHEL 9). Existe pra quem precisa de compatibilidade estrita com ambientes ou certificações que assumem RHEL puro, ou software de terceiro que só foi homologado contra o kernel da Red Hat.

**Trocar de kernel é simples**: os dois vêm inclusos na mesma instalação, sem custo adicional, bastando selecionar qual usar no boot (GRUB) ou trocar o pacote kernel padrão. Isso é uma diferença de posicionamento importante frente ao RHEL — não é uma trava comercial, é escolha técnica.

**Pontos pra desenvolver no documento:**
- Comparar tempo de vida útil / cadência de patch de cada um
- Levantar por que bancos de dados Oracle recomendam UEK especificamente (ex.: melhorias de I/O, NUMA, ASM)
- Registrar o comando pra verificar qual kernel está rodando: `uname -r` (kernels UEK trazem `.el*uek` no nome da versão)

**Fontes:**
- [Oracle Linux and Unbreakable Enterprise Kernel (UEK) Releases — blog oficial Oracle](https://blogs.oracle.com/scoter/oracle-linux-and-unbreakable-enterprise-kernel-uek-releases) — primária
- [UEK 6 — Installation and Availability, documentação oficial Oracle](https://docs.oracle.com/en/operating-systems/uek/6/relnotes6.0/uek6-InstallationandAvailability.html) — primária
- [Oracle Linux: Frequently Asked Questions — ORACLE-BASE](https://oracle-base.com/articles/linux/oracle-linux-frequently-asked-questions) — secundária, mas bem referenciada
- [UEK vs RHCK Kernels — Mythics](https://blog.mythics.com/posts/uek-vs-rhck-kernels) — secundária

---

## 2. Ksplice — patch de kernel sem reboot

Ksplice é a tecnologia da Oracle pra aplicar **patches de segurança críticos (kernel e também glibc/OpenSSL em espaço de usuário) sem precisar reiniciar o servidor**. Em vez do fluxo tradicional (baixar patch → agendar janela de manutenção → reboot → validar), o Ksplice injeta a correção diretamente no kernel em execução.

**Suporte:** funciona em Oracle Linux (UEK e RHCK/RHEL-compatible), Oracle Linux em qualquer versão suportada, e também tem uma versão de comunidade para desktop Ubuntu. Já é usado em mais de 250 mil sistemas segundo material da própria Oracle.

**Modelo de acesso:**
- Incluído nas assinaturas de suporte **Premier** e **Premier Plus** do Oracle Linux
- Existe período de avaliação gratuita (30 dias) para quem quer testar antes de assinar
- A versão desktop para Ubuntu é gratuita para uso pessoal

**Pontos pra desenvolver no documento:**
- Explicar tecnicamente *como* um live patch funciona sem reboot (hot patching, redirecionamento de função no kernel em execução) — dá pra comparar com o mecanismo genérico de live patching do kernel Linux (`kpatch`, `kGraft`) pra mostrar o que o Ksplice faz de diferente/proprietário
- Levantar um caso de uso: por que zero-downtime patching importa pra um servidor de produção (ex.: banco de dados que não pode ter janela de manutenção)
- Comando de verificação depois de aplicar um patch: `uptrack-uname -r` mostra a versão efetiva do kernel corrigido, mesmo sem reboot

**Fontes:**
- [Oracle Ksplice — página oficial](https://ksplice.oracle.com/) — primária
- [Ksplice: Zero Downtime Updates for Oracle Linux FAQ (PDF oficial)](https://www.oracle.com/us/technologies/linux/ksplice-faq-3801000.pdf) — primária
- [Ksplice Provides Zero-Downtime Patching — blog oficial Oracle Cloud Infrastructure](https://blogs.oracle.com/cloud-infrastructure/ksplice-provides-zero-downtime-patching-for-red-hat-enterprise-linux-and-centos-instances) — primária
- [Demo: Zero Downtime Patching with Oracle Ksplice — blog oficial Oracle](https://blogs.oracle.com/scoter/demo-zero-downtime-patching-with-oracle-ksplice) — primária

---

## 3. Licenciamento do Oracle Linux

O modelo comercial da Oracle pro Linux é resumido na própria frase oficial da empresa: **"pague pelo suporte, não pelo software."**

- **O sistema operacional é gratuito**: qualquer pessoa pode baixar a ISO, instalar, usar em produção e aplicar atualizações de bug sem pagar nada — não existe chave de licença nem trava por número de servidores pra usar o SO em si.
- **O que é pago é o suporte**, em três níveis, cada um com 10 anos de cobertura a partir do lançamento da versão major (mais Extended Support e Sustaining Support opcionais depois disso):
  - **Basic Support** — suporte 24/7 por telefone/online, acesso a atualizações e correções, ferramentas como DTrace e balanceadores de carga
  - **Premier Support** — tudo do Basic + **Ksplice** (patch sem reboot), automação (Oracle Linux Automation Manager), suporte a Kubernetes (Oracle Cloud Native Environment), alta disponibilidade, backport de correções por 6 meses
  - **Premier Plus** — tudo do Premier + virtualização Oracle e acesso vitalício a sustaining support

**Pontos pra desenvolver no documento:**
- Comparar esse modelo com o da Red Hat (RHEL passou a restringir acesso público ao código-fonte/binários em 2023) — é um contraste relevante pra explicar por que Oracle Linux, Rocky e AlmaLinux existem como "herdeiros" do espaço que o CentOS deixou
- Levantar o que muda pra uma empresa que roda Oracle Database: há vantagem contratual/técnica em rodar Oracle Linux + UEK + Ksplice na mesma pilha do fornecedor do banco?
- Registrar que trocar entre UEK e RHCK não tem custo — reforça que a divisão comercial da Oracle é sobre suporte, não sobre o kernel escolhido

**Fontes:**
- [Oracle Linux Support — página oficial de níveis de suporte](https://www.oracle.com/linux/support/) — primária
- [Frequently Asked Questions Oracle Linux (PDF oficial, ago/2025)](https://www.oracle.com/a/ocom/docs/027617.pdf) — primária
- [Oracle Linux: Frequently Asked Questions — ORACLE-BASE](https://oracle-base.com/articles/linux/oracle-linux-frequently-asked-questions) — secundária
- [Licensing Q&A: Is Oracle Linux free? — Licenseware](https://licenseware.io/licensing-qa-is-oracle-linux-free/) — secundária

---

## Checklist pro documento final

- [ ] Mínimo 8 referências, sendo ao menos 4 primárias (as 7 fontes primárias listadas acima já cobrem essa exigência — acrescentem mais 1-2 secundárias/comparativas de peso, ex. cobertura de licenciamento RHEL pós-2023)
- [ ] 12 a 20 páginas — as três seções acima dão a espinha dorsal; expandam com contexto histórico, comparações e a opinião fundamentada do grupo
- [ ] Cada afirmação técnica precisa ter fonte — não copiem os resumos acima sem reconferir na fonte primária
