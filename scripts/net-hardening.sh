#!/usr/bin/env bash
#
# net-hardening.sh — Hardening de rede e firewalld (Grupo 4 / Oracle Linux)
#
# O que faz:
#   1. Inventaria portas em escuta (ss -tulpn) e compara com uma lista de
#      portas autorizadas.
#   2. Aplica (ou reverte) um conjunto de parâmetros sysctl de rede,
#      persistidos em /etc/sysctl.d/.
#   3. Garante uma zona dedicada no firewalld com uma rich rule de limite
#      de taxa (rate limit), sem nunca remover a regra que sustenta a
#      sessão SSH atual de quem está rodando o script.
#
# Uso:
#   net-hardening.sh --audit [--config ARQUIVO]
#   net-hardening.sh --apply [--dry-run] [--config ARQUIVO]
#   net-hardening.sh --rollback [--dry-run]
#   net-hardening.sh -h | --help
#
# Códigos de saída:
#   0 sucesso (nenhum achado / aplicação concluída)
#   1 achado (porta não autorizada em escuta durante --audit)
#   2 erro de uso (argumento inválido)
#   3 pré-requisito não atendido (privilégio insuficiente ou dependência ausente)
#
# Idempotência:
#   Rodar --apply duas vezes seguidas produz o mesmo estado final: o script
#   só reescreve o drop-in de sysctl se o conteúdo mudou, e só recria a
#   zona/rich rule do firewalld se ainda não existirem.
#
# Reversibilidade:
#   --rollback restaura o backup do drop-in de sysctl e remove a zona e a
#   rich rule criadas por este script — exceto a rich rule que sustenta a
#   sessão SSH atual, que é preservada e reportada como ERROR (não como
#   falha fatal do rollback).

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Configuração padrão (pode ser sobrescrita por --config)
# ---------------------------------------------------------------------------
readonly SCRIPT_NAME="net-hardening.sh"
readonly LOG_FILE="/var/log/net-hardening.log"
readonly PORTAS_AUTORIZADAS_PADRAO="/etc/net-hardening/portas-autorizadas.txt"
readonly SYSCTL_DROPIN="/etc/sysctl.d/99-net-hardening.conf"
readonly BACKUP_DIR="/var/backups/net-hardening"
readonly FIREWALLD_ZONA="hardened-mgmt"
readonly LIMITE_TAXA="10/m"

readonly EXIT_OK=0
readonly EXIT_ACHADO=1
readonly EXIT_USO=2
readonly EXIT_DEPENDENCIA=3

# Parâmetros sysctl aplicados pelo hardening (chave -> valor)
readonly SYSCTL_PARAMS=(
  "net.ipv4.conf.all.accept_redirects=0"
  "net.ipv4.conf.default.accept_redirects=0"
  "net.ipv4.conf.all.send_redirects=0"
  "net.ipv4.conf.all.accept_source_route=0"
  "net.ipv4.conf.all.rp_filter=1"
  "net.ipv4.icmp_echo_ignore_broadcasts=1"
  "net.ipv4.tcp_syncookies=1"
  "net.ipv6.conf.all.accept_redirects=0"
  "net.ipv6.conf.all.accept_source_route=0"
)

MODO=""
DRY_RUN="false"
ARQUIVO_PORTAS="${PORTAS_AUTORIZADAS_PADRAO}"
TMP_FILES=()

# ---------------------------------------------------------------------------
# Funções
# ---------------------------------------------------------------------------

limpar_temporarios() {
  local f
  for f in "${TMP_FILES[@]}"; do
    [[ -e "${f}" ]] && rm -f "${f}"
  done
  return 0
}
trap limpar_temporarios EXIT

log() {
  local nivel="$1"; shift
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  local linha="[${ts}] [${nivel}] ${msg}"
  echo "${linha}"
  if [[ -w "$(dirname "${LOG_FILE}")" || -w "${LOG_FILE}" ]] 2>/dev/null; then
    echo "${linha}" >>"${LOG_FILE}" 2>/dev/null || true
  fi
}

usage() {
  cat <<EOF
${SCRIPT_NAME} — hardening de rede e firewalld (Grupo 4 / Oracle Linux)

Uso:
  ${SCRIPT_NAME} --audit [--config ARQUIVO]
  ${SCRIPT_NAME} --apply [--dry-run] [--config ARQUIVO]
  ${SCRIPT_NAME} --rollback [--dry-run]
  ${SCRIPT_NAME} -h | --help

Opções:
  --audit           Só inventaria portas em escuta e compara com a lista
                     de portas autorizadas. Não altera nada no sistema.
  --apply           Aplica os parâmetros sysctl e a zona/rich rule do
                     firewalld.
  --rollback        Restaura o backup do sysctl e remove a zona e a
                     rich rule criadas (preserva a regra da sessão atual).
  --dry-run         Mostra o que seria feito, sem alterar o sistema.
                     Só é válido com --apply ou --rollback.
  --config ARQUIVO  Caminho da lista de portas autorizadas
                     (padrão: ${PORTAS_AUTORIZADAS_PADRAO}).
  -h, --help        Mostra esta ajuda e sai.

Códigos de saída: 0 sucesso · 1 achado · 2 erro de uso · 3 dependência/privilégio
EOF
}

verificar_privilegio() {
  if [[ "${EUID}" -ne 0 ]]; then
    log "ERROR" "este script precisa ser executado como root (EUID atual: ${EUID})."
    exit "${EXIT_DEPENDENCIA}"
  fi
}

verificar_dependencias() {
  local dep faltando=0
  local deps=(ss awk sed date mktemp sysctl firewall-cmd)
  for dep in "${deps[@]}"; do
    if ! command -v "${dep}" >/dev/null 2>&1; then
      log "ERROR" "dependência ausente: ${dep}"
      faltando=1
    fi
  done
  if [[ "${faltando}" -ne 0 ]]; then
    exit "${EXIT_DEPENDENCIA}"
  fi
}

analisar_argumentos() {
  if [[ "$#" -eq 0 ]]; then
    usage
    exit "${EXIT_USO}"
  fi
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --audit)
        MODO="audit"
        shift
        ;;
      --apply)
        MODO="apply"
        shift
        ;;
      --rollback)
        MODO="rollback"
        shift
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --config)
        [[ "$#" -ge 2 ]] || { log "ERROR" "--config exige um argumento"; exit "${EXIT_USO}"; }
        ARQUIVO_PORTAS="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit "${EXIT_OK}"
        ;;
      *)
        log "ERROR" "argumento desconhecido: $1"
        usage
        exit "${EXIT_USO}"
        ;;
    esac
  done

  if [[ -z "${MODO}" ]]; then
    log "ERROR" "escolha um modo: --audit, --apply ou --rollback"
    exit "${EXIT_USO}"
  fi
}

# Retorna, via stdout, a porta local usada pela sessão SSH atual (se houver).
porta_sessao_atual() {
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    # SSH_CONNECTION="ip_cliente porta_cliente ip_servidor porta_servidor"
    awk '{print $4}' <<<"${SSH_CONNECTION}"
  fi
}

# Compara uma porta/protocolo candidata à remoção contra a sessão SSH atual.
regra_protege_sessao_atual() {
  local porta_candidata="$1"
  local porta_atual
  porta_atual="$(porta_sessao_atual)"
  [[ -n "${porta_atual}" && "${porta_candidata}" == "${porta_atual}" ]]
}

inventario_portas() {
  local achados=0
  local linha proto local_addr porta chave
  local -A autorizadas=()

  if [[ -f "${ARQUIVO_PORTAS}" ]]; then
    while IFS= read -r linha; do
      linha="${linha%%#*}"
      linha="$(echo "${linha}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "${linha}" ]] && continue
      autorizadas["${linha}"]=1
    done <"${ARQUIVO_PORTAS}"
  else
    log "WARN" "lista de portas autorizadas não encontrada em ${ARQUIVO_PORTAS}; tratando todas as portas como não autorizadas."
  fi

  log "INFO" "inventariando portas em escuta (ss -tulpn)..."
  while IFS=' ' read -r proto local_addr; do
    [[ "${proto}" == "tcp" || "${proto}" == "udp" ]] || continue
    porta="${local_addr##*:}"
    [[ "${porta}" =~ ^[0-9]+$ ]] || continue
    chave="${porta}/${proto}"
    if [[ -n "${autorizadas[${chave}]:-}" ]]; then
      log "INFO" "porta autorizada em escuta: ${chave}"
    else
      log "WARN" "porta NÃO autorizada em escuta: ${chave}"
      achados=$((achados + 1))
    fi
  done < <(ss -H -tulpn 2>/dev/null | awk '{print $1, $5}')

  if [[ "${achados}" -gt 0 ]]; then
    log "WARN" "inventário concluído com ${achados} porta(s) não autorizada(s)."
    return "${EXIT_ACHADO}"
  fi
  log "INFO" "inventário concluído sem achados."
  return "${EXIT_OK}"
}

aplicar_sysctl() {
  local tmp param
  tmp="$(mktemp)"
  TMP_FILES+=("${tmp}")

  {
    echo "# Gerado por ${SCRIPT_NAME} — não editar manualmente."
    echo "# Backup do arquivo anterior (se existia) em ${BACKUP_DIR}/"
    for param in "${SYSCTL_PARAMS[@]}"; do
      echo "${param}"
    done
  } >"${tmp}"

  if [[ -f "${SYSCTL_DROPIN}" ]] && cmp -s "${tmp}" "${SYSCTL_DROPIN}"; then
    log "INFO" "sysctl já aplicado, nenhuma mudança necessária (idempotente)."
    return 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "INFO" "[dry-run] escreveria ${SYSCTL_DROPIN} com $(( ${#SYSCTL_PARAMS[@]} )) parâmetro(s) e rodaria 'sysctl --system'."
    return 0
  fi

  mkdir -p "${BACKUP_DIR}"
  if [[ -f "${SYSCTL_DROPIN}" ]]; then
    cp -p "${SYSCTL_DROPIN}" "${BACKUP_DIR}/$(basename "${SYSCTL_DROPIN}").bak-$(date +%s)"
  fi
  install -m 0644 "${tmp}" "${SYSCTL_DROPIN}"
  sysctl --system >/dev/null
  log "INFO" "parâmetros sysctl aplicados e persistidos em ${SYSCTL_DROPIN}."
}

aplicar_firewall() {
  local porta_atual regra

  if ! firewall-cmd --state >/dev/null 2>&1; then
    log "ERROR" "firewalld não está em execução."
    exit "${EXIT_DEPENDENCIA}"
  fi

  if firewall-cmd --get-zones 2>/dev/null | grep -qw "${FIREWALLD_ZONA}"; then
    log "INFO" "zona '${FIREWALLD_ZONA}' já existe (idempotente)."
  else
    if [[ "${DRY_RUN}" == "true" ]]; then
      log "INFO" "[dry-run] criaria a zona '${FIREWALLD_ZONA}'."
    else
      firewall-cmd --permanent --new-zone="${FIREWALLD_ZONA}" >/dev/null
      log "INFO" "zona '${FIREWALLD_ZONA}' criada."
    fi
  fi

  porta_atual="$(porta_sessao_atual)"
  if [[ -z "${porta_atual}" ]]; then
    log "WARN" "não foi possível detectar a porta da sessão atual (SSH_CONNECTION vazio); usando porta 22 como referência."
    porta_atual="22"
  fi

  regra="rule family=\"ipv4\" port port=\"${porta_atual}\" protocol=\"tcp\" accept limit value=\"${LIMITE_TAXA}\""

  if firewall-cmd --permanent --zone="${FIREWALLD_ZONA}" --list-rich-rules 2>/dev/null | grep -qF "port=\"${porta_atual}\""; then
    log "INFO" "rich rule de limite de taxa para a porta ${porta_atual} já existe (idempotente)."
  else
    if [[ "${DRY_RUN}" == "true" ]]; then
      log "INFO" "[dry-run] adicionaria rich rule: ${regra}"
    else
      firewall-cmd --permanent --zone="${FIREWALLD_ZONA}" --add-rich-rule="${regra}" >/dev/null
      log "INFO" "rich rule de limite de taxa (${LIMITE_TAXA}) aplicada para a porta ${porta_atual}."
    fi
  fi

  if [[ "${DRY_RUN}" != "true" ]]; then
    firewall-cmd --reload >/dev/null
    log "INFO" "firewalld recarregado."
  fi
}

reverter() {
  local backup_mais_recente porta_atual regra

  # --- sysctl ---
  backup_mais_recente="$(find "${BACKUP_DIR}" -maxdepth 1 -name "$(basename "${SYSCTL_DROPIN}").bak-*" 2>/dev/null | sort | tail -n1 || true)"
  if [[ -n "${backup_mais_recente}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      log "INFO" "[dry-run] restauraria ${SYSCTL_DROPIN} a partir de ${backup_mais_recente}."
    else
      cp -p "${backup_mais_recente}" "${SYSCTL_DROPIN}"
      sysctl --system >/dev/null
      log "INFO" "sysctl revertido a partir de ${backup_mais_recente}."
    fi
  elif [[ -f "${SYSCTL_DROPIN}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      log "INFO" "[dry-run] removeria ${SYSCTL_DROPIN} (nenhum backup anterior encontrado)."
    else
      rm -f "${SYSCTL_DROPIN}"
      sysctl --system >/dev/null
      log "INFO" "${SYSCTL_DROPIN} removido (nenhum backup anterior existia)."
    fi
  else
    log "INFO" "nada a reverter em sysctl."
  fi

  # --- firewalld: remover a rich rule, exceto se sustenta a sessão atual ---
  porta_atual="$(porta_sessao_atual)"
  if firewall-cmd --state >/dev/null 2>&1 && \
     firewall-cmd --permanent --zone="${FIREWALLD_ZONA}" --list-rich-rules 2>/dev/null | grep -q .; then
    while IFS= read -r regra; do
      [[ -z "${regra}" ]] && continue
      if [[ -n "${porta_atual}" ]] && grep -qF "port=\"${porta_atual}\"" <<<"${regra}" && regra_protege_sessao_atual "${porta_atual}"; then
        log "ERROR" "regra preservada por sustentar a sessão SSH atual (porta ${porta_atual}): ${regra}"
        continue
      fi
      if [[ "${DRY_RUN}" == "true" ]]; then
        log "INFO" "[dry-run] removeria rich rule: ${regra}"
      else
        firewall-cmd --permanent --zone="${FIREWALLD_ZONA}" --remove-rich-rule="${regra}" >/dev/null
        log "INFO" "rich rule removida: ${regra}"
      fi
    done < <(firewall-cmd --permanent --zone="${FIREWALLD_ZONA}" --list-rich-rules 2>/dev/null)

    if [[ "${DRY_RUN}" != "true" ]]; then
      firewall-cmd --reload >/dev/null
      log "INFO" "firewalld recarregado após rollback."
    fi
  else
    log "INFO" "nada a reverter em firewalld."
  fi
}

main() {
  analisar_argumentos "$@"
  verificar_privilegio
  verificar_dependencias

  case "${MODO}" in
    audit)
      inventario_portas
      exit $?
      ;;
    apply)
      aplicar_sysctl
      aplicar_firewall
      log "INFO" "hardening de rede aplicado com sucesso."
      exit "${EXIT_OK}"
      ;;
    rollback)
      reverter
      log "INFO" "rollback concluído."
      exit "${EXIT_OK}"
      ;;
  esac
}

main "$@"
