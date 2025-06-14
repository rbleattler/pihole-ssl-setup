#!/usr/bin/env bash
set -euo pipefail

# Defaults – override via CLI flags
DOMAIN="pihole.example.com"
CERT_PROVIDER="zerossl" # or 'letsencrypt'
DNS_PROVIDER="cloudflare" # cloudflare, namecheap, godaddy, route53, digitalocean, linode, gcloud, desec
ZEROSSL_EMAIL="you@yourdomain.com"
CF_EMAIL="your@yourdomain.com"
CF_TOKEN="CF_API_TOKEN_HERE"
ZEROSSL_KEY="ZEROSSL_API_KEY_HERE"
DOCKER_MODE=false
DOCKER_CONTAINER_NAME="pihole"
KEY_LENGTH="ec-256" # ec-256, 2048, 4096
DRY_RUN=false

# DNS Provider credentials
NAMECHEAP_USERNAME=""
NAMECHEAP_API_KEY=""
NAMECHEAP_SOURCEIP=""
GODADDY_API_KEY=""
GODADDY_API_SECRET=""
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_REGION="us-east-1"
DO_API_TOKEN=""
LINODE_API_TOKEN=""
GCP_SERVICE_ACCOUNT_FILE=""
DESEC_API_TOKEN=""

BACKUP_DIR="/etc/lighttpd/backup_$(date +%Y%m%d_%H%M%S)"
CERT_BASE="/etc/lighttpd/certs"
CRON_PATH="/etc/cron.d/pihole_ssl_renew"

# Color support
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  ncolors=$(tput colors)
else
  ncolors=0
fi

if [ "$ncolors" -ge 8 ]; then
  RED="$(tput setaf 1)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"
  MAGENTA="$(tput setaf 5)"
  CYAN="$(tput setaf 6)"
  BOLD="$(tput bold)"
  NC="$(tput sgr0)"
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; BOLD=""; NC=""
fi

color_echo() {
  # Usage: color_echo "${RED}Error${NC}: ${YELLOW}Something failed${NC}"
  echo -e "$1"
}

highlight_var() {
  # Usage: highlight_var "$VAR"
  echo -e "${BOLD}${CYAN}$1${NC}"
}

usage() {
  color_echo "${BOLD}${GREEN}Configures SSL for Pi-hole using multiple DNS providers and certificate authorities${NC}\n"
  color_echo "${BOLD}${YELLOW}Usage:${NC} $0 [OPTIONS]\n"
  color_echo "${BOLD}${BLUE}Required Options:${NC}"
  color_echo "  ${CYAN}--domain${NC} DOMAIN            Fully qualified domain name to secure\n"
  color_echo "${BOLD}${BLUE}Certificate Options:${NC}"
  color_echo "  ${CYAN}--cert-provider${NC} PROVIDER   Certificate provider: '${GREEN}zerossl${NC}' (default) or '${GREEN}letsencrypt${NC}'"
  color_echo "  ${CYAN}--zerossl-email${NC} EMAIL      Email used for ZeroSSL account (required if provider is zerossl)"
  color_echo "  ${CYAN}--zerossl-key${NC} KEY          API key for ZeroSSL (required if provider is zerossl)"
  color_echo "  ${CYAN}--key-length${NC} LENGTH        Certificate key length: '${GREEN}ec-256${NC}' (default), '${GREEN}2048${NC}', '${GREEN}4096${NC}'\n"
  color_echo "${BOLD}${BLUE}DNS Provider Options:${NC}"
  color_echo "  ${CYAN}--dns-provider${NC} PROVIDER    DNS provider: '${GREEN}cloudflare${NC}' (default), '${GREEN}namecheap${NC}', '${GREEN}godaddy${NC}',"
  color_echo "                             '${GREEN}route53${NC}', '${GREEN}digitalocean${NC}', '${GREEN}linode${NC}', '${GREEN}gcloud${NC}', '${GREEN}desec${NC}'\n"
  color_echo "${BOLD}${BLUE}Cloudflare DNS:${NC}"
  color_echo "  ${CYAN}--cf-email${NC} EMAIL           Cloudflare account email"
  color_echo "  ${CYAN}--cf-token${NC} TOKEN           Cloudflare API token\n"
  color_echo "${BOLD}${BLUE}Namecheap DNS:${NC}"
  color_echo "  ${CYAN}--namecheap-username${NC} USER  Namecheap username"
  color_echo "  ${CYAN}--namecheap-key${NC} KEY        Namecheap API key"
  color_echo "  ${CYAN}--namecheap-sourceip${NC} IP    Namecheap source IP (current IP if not specified)\n"
  color_echo "${BOLD}${BLUE}GoDaddy DNS:${NC}"
  color_echo "  ${CYAN}--godaddy-key${NC} KEY          GoDaddy API key"
  color_echo "  ${CYAN}--godaddy-secret${NC} SECRET    GoDaddy API secret\n"
  color_echo "${BOLD}${BLUE}AWS Route53 DNS:${NC}"
  color_echo "  ${CYAN}--aws-access-key${NC} KEY       AWS Access Key ID"
  color_echo "  ${CYAN}--aws-secret-key${NC} SECRET    AWS Secret Access Key"
  color_echo "  ${CYAN}--aws-region${NC} REGION        AWS region (default: us-east-1)\n"
  color_echo "${BOLD}${BLUE}DigitalOcean DNS:${NC}"
  color_echo "  ${CYAN}--do-token${NC} TOKEN           DigitalOcean API token\n"
  color_echo "${BOLD}${BLUE}Linode DNS:${NC}"
  color_echo "  ${CYAN}--linode-token${NC} TOKEN       Linode API token\n"
  color_echo "${BOLD}${BLUE}Google Cloud DNS:${NC}"
  color_echo "  ${CYAN}--gcp-service-file${NC} PATH    Path to GCP service account JSON file\n"
  color_echo "${BOLD}${BLUE}deSEC DNS:${NC}"
  color_echo "  ${CYAN}--desec-token${NC} TOKEN        deSEC API token\n"
  color_echo "${BOLD}${BLUE}Docker Options:${NC}"
  color_echo "  ${CYAN}--docker${NC}                   Enable Docker mode for containerized Pi-hole"
  color_echo "  ${CYAN}--docker-container${NC} NAME    Docker container name (default: pihole)\n"
  color_echo "${BOLD}${BLUE}General Options:${NC}"
  color_echo "  ${CYAN}--dry-run${NC}                  Show what would be done without executing commands"
  color_echo "  ${CYAN}--revert${NC}                   Revert to last known good configuration"
  color_echo "  ${CYAN}--help${NC}                     Show this help message and exit\n"
  color_echo "${BOLD}${MAGENTA}Examples:${NC}"
  color_echo "  # Basic setup with Cloudflare and ZeroSSL"
  color_echo "  $0 --domain $(highlight_var "pihole.example.com") --cf-email $(highlight_var "user@example.com") --cf-token $(highlight_var "YOUR_TOKEN")\n"
  color_echo "  # Setup with Let's Encrypt and Namecheap"
  color_echo "  $0 --domain $(highlight_var "pihole.example.com") --cert-provider letsencrypt --dns-provider namecheap --namecheap-username $(highlight_var "user") --namecheap-key $(highlight_var "API_KEY")\n"
  color_echo "  # Docker setup with DigitalOcean"
  color_echo "  $0 --domain $(highlight_var "pihole.example.com") --docker --dns-provider digitalocean --do-token $(highlight_var "TOKEN")\n"
  color_echo "  # Dry run to see what would happen"
  color_echo "  $0 --domain $(highlight_var "pihole.example.com") --cf-email $(highlight_var "user@example.com") --cf-token $(highlight_var "YOUR_TOKEN") --dry-run\n"
  color_echo "  # Revert to previous configuration"
  color_echo "  $0 --revert\n"
  exit 0
}

REVERT_MODE=0
INIT_MODE=0
# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --domain) DOMAIN="$2"; shift 2 ;;
    --cert-provider) CERT_PROVIDER="$2"; shift 2 ;;
    --dns-provider) DNS_PROVIDER="$2"; shift 2 ;;
    --zerossl-email) ZEROSSL_EMAIL="$2"; shift 2 ;;
    --zerossl-key) ZEROSSL_KEY="$2"; shift 2 ;;
    --key-length) KEY_LENGTH="$2"; shift 2 ;;
    --cf-email) CF_EMAIL="$2"; shift 2 ;;
    --cf-token) CF_TOKEN="$2"; shift 2 ;;
    --namecheap-username) NAMECHEAP_USERNAME="$2"; shift 2 ;;
    --namecheap-key) NAMECHEAP_API_KEY="$2"; shift 2 ;;
    --namecheap-sourceip) NAMECHEAP_SOURCEIP="$2"; shift 2 ;;
    --godaddy-key) GODADDY_API_KEY="$2"; shift 2 ;;
    --godaddy-secret) GODADDY_API_SECRET="$2"; shift 2 ;;
    --aws-access-key) AWS_ACCESS_KEY_ID="$2"; shift 2 ;;
    --aws-secret-key) AWS_SECRET_ACCESS_KEY="$2"; shift 2 ;;
    --aws-region) AWS_REGION="$2"; shift 2 ;;
    --do-token) DO_API_TOKEN="$2"; shift 2 ;;
    --linode-token) LINODE_API_TOKEN="$2"; shift 2 ;;
    --gcp-service-file) GCP_SERVICE_ACCOUNT_FILE="$2"; shift 2 ;;
    --desec-token) DESEC_API_TOKEN="$2"; shift 2 ;;
    --docker) DOCKER_MODE=true; shift ;;
    --docker-container) DOCKER_CONTAINER_NAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --revert) REVERT_MODE=1; shift ;;
    --init) INIT_MODE=1; shift ;;
    --help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

if (( INIT_MODE )); then
  # Color variables: use white/gray for padlock, green for leaf, red for drop
  # If WHITE or GRAY not defined, fallback to BOLD only for padlock
  PADLOCK_BAR="${BOLD}${WHITE:-${BOLD}}"
  PADLOCK_BODY="${BOLD}${YELLOW}"
  PIHOLE_LEAF="${BOLD}${GREEN}"
  PIHOLE_DROP="${BOLD}${RED}"
  NC="${NC}"

  # Padlock starts lower, plus sign is ASCII art, Pi-hole logo is original
  color_echo "${PIHOLE_LEAF}********                          ${NC}"
  color_echo "${PIHOLE_LEAF} ***********                       ${NC}"
  color_echo "${PIHOLE_LEAF}  ***********+           +++       ${NC}"
  color_echo "${PIHOLE_LEAF}  ************+     ++++++++       ${NC}"
  color_echo "${PIHOLE_LEAF}   ***********++   +++++++++       ${NC}     ${PADLOCK_BAR}             @@@@@@@@${NC}"
  color_echo "${PIHOLE_LEAF}    **********+++ +++++++++        ${NC}     ${PADLOCK_BAR}            @@@@@@@@@@${NC}"
  color_echo "${PIHOLE_LEAF}      ********++++++++++++         ${NC}     ${PADLOCK_BAR}           @@@@    @@@@${NC}"
  color_echo "${PIHOLE_LEAF}        *******++++++++            ${NC}     ${PADLOCK_BAR}           @@@      @@@${NC}"
  color_echo "${PIHOLE_DROP}             +#######              ${NC}     ${PADLOCK_BAR}           @@@      @@@${NC}"
  color_echo "${PIHOLE_DROP}            ###########            ${NC}     ${PADLOCK_BAR}           @@@      @@@${NC}"
  color_echo "${PIHOLE_DROP}          #############%%          ${NC}     ${PADLOCK_BAR}           @@@      @@@${NC}"
  color_echo "${PIHOLE_DROP}        ################%%%        ${NC}     ${PADLOCK_BODY}          @@@@@@@@@@@@@@${NC}"
  color_echo "${PIHOLE_DROP}      ##################%%%%%      ${NC}     ${PADLOCK_BODY}          @@@@@@@@@@@@@@${NC}"
  color_echo "${PIHOLE_DROP}    ####################%%%%%%%    ${NC}     ${PADLOCK_BODY}          @@@@@@@@@@@@@@${NC}"
  color_echo "${PIHOLE_DROP}  %%%%%%%%#############%%%%%%%%%%  ${NC}        +${PADLOCK_BODY}      @@@@@@@@@@@@@@${NC}"
  color_echo "${PIHOLE_DROP} %%%%%%%%%%%%######## %%%%%%%%%%%% ${NC}      +++++${PADLOCK_BODY}    @@@@@@@@@@@@@@${NC}"
  color_echo "${PIHOLE_DROP}%%%%%%%%%%%%%%       %%%%%%%%%%%%%%${NC}        +${PADLOCK_BODY}      @@@@@@@@@@@@@@${NC}"
  color_echo "${PIHOLE_DROP}%%%%%%%%%%%%%%       %%%%%%%%%%%%%%${NC}     ${PADLOCK_BODY}          @@@@@@@@@@@@@@${NC}"
  color_echo "${PIHOLE_DROP}%%%%%%%%%%%%%%       %%%%%%%%%%%%%%${NC}     ${PADLOCK_BODY}          @@@@@@@@@@@@@@${NC}"
  color_echo "${PIHOLE_DROP} %%%%%%%%%%%%%  ###   %%%%%%%%%%%% ${NC}     ${PADLOCK_BODY}          @@@@@@@@@@@@@@${NC}"
  color_echo "${PIHOLE_DROP}  %%%%%%%%%%%##########%%%%%%%%%%  ${NC}"
  color_echo "${PIHOLE_DROP}    %%%%%%%%###############%%##    ${NC}"
  color_echo "${PIHOLE_DROP}     %%%%%%###################     ${NC}"
  color_echo "${PIHOLE_DROP}       %%%%#################       ${NC}"
  color_echo "${PIHOLE_DROP}         %%%##############         ${NC}"
  color_echo "${PIHOLE_DROP}           %%###########           ${NC}"
  color_echo "${PIHOLE_DROP}             %%#######             ${NC}"


  color_echo "${BOLD}${MAGENTA}Pi-hole SSL Security Setup${NC}\n"
  color_echo "${BOLD}${MAGENTA}Welcome to Pi-hole SSL Config Interactive Setup!${NC}"
  # Interactive prompts
  read -rp "Enter the fully qualified domain name to secure: " DOMAIN
  color_echo "${BOLD}${BLUE}Choose certificate provider:${NC}"
  select CERT_PROVIDER in "zerossl" "letsencrypt"; do
    [ -n "$CERT_PROVIDER" ] && break
  done
  color_echo "${BOLD}${BLUE}Choose DNS provider:${NC}"
  select DNS_PROVIDER in "cloudflare" "namecheap" "godaddy" "route53" "digitalocean" "linode" "gcloud" "desec"; do
    [ -n "$DNS_PROVIDER" ] && break
  done
  # Provider-specific prompts
  case "$DNS_PROVIDER" in
    cloudflare)
      read -rp "Cloudflare email: " CF_EMAIL
      read -rp "Cloudflare API token: " CF_TOKEN
      ;;
    namecheap)
      read -rp "Namecheap username: " NAMECHEAP_USERNAME
      read -rp "Namecheap API key: " NAMECHEAP_API_KEY
      read -rp "Namecheap source IP (leave blank for current IP): " NAMECHEAP_SOURCEIP
      ;;
    godaddy)
      read -rp "GoDaddy API key: " GODADDY_API_KEY
      read -rp "GoDaddy API secret: " GODADDY_API_SECRET
      ;;
    route53)
      read -rp "AWS Access Key ID: " AWS_ACCESS_KEY_ID
      read -rp "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
      read -rp "AWS region (default: us-east-1): " AWS_REGION
      AWS_REGION=${AWS_REGION:-us-east-1}
      ;;
    digitalocean)
      read -rp "DigitalOcean API token: " DO_API_TOKEN
      ;;
    linode)
      read -rp "Linode API token: " LINODE_API_TOKEN
      ;;
    gcloud)
      read -rp "Path to GCP service account JSON file: " GCP_SERVICE_ACCOUNT_FILE
      ;;
    desec)
      read -rp "deSEC API token: " DESEC_API_TOKEN
      ;;
  esac
  # Cert provider specific
  if [[ "$CERT_PROVIDER" == "zerossl" ]]; then
    read -rp "ZeroSSL email: " ZEROSSL_EMAIL
    read -rp "ZeroSSL API key: " ZEROSSL_KEY
  fi
  read -rp "Certificate key length (ec-256, 2048, 4096) [ec-256]: " KEY_LENGTH
  KEY_LENGTH=${KEY_LENGTH:-ec-256}
  read -rp "Are you using Docker for Pi-hole? (y/N): " docker_answer
  if [[ "$docker_answer" =~ ^[Yy]$ ]]; then
    DOCKER_MODE=true
    read -rp "Docker container name [pihole]: " DOCKER_CONTAINER_NAME
    DOCKER_CONTAINER_NAME=${DOCKER_CONTAINER_NAME:-pihole}
  fi
  # Build command
  CMD="$0 --domain $(printf '%q' "$DOMAIN") --cert-provider $(printf '%q' "$CERT_PROVIDER") --dns-provider $(printf '%q' "$DNS_PROVIDER") --key-length $(printf '%q' "$KEY_LENGTH")"
  case "$DNS_PROVIDER" in
    cloudflare)
      CMD+=" --cf-email $(printf '%q' "$CF_EMAIL") --cf-token $(printf '%q' "$CF_TOKEN")";;
    namecheap)
      CMD+=" --namecheap-username $(printf '%q' "$NAMECHEAP_USERNAME") --namecheap-key $(printf '%q' "$NAMECHEAP_API_KEY")"
      [ -n "$NAMECHEAP_SOURCEIP" ] && CMD+=" --namecheap-sourceip $(printf '%q' "$NAMECHEAP_SOURCEIP")";;
    godaddy)
      CMD+=" --godaddy-key $(printf '%q' "$GODADDY_API_KEY") --godaddy-secret $(printf '%q' "$GODADDY_API_SECRET")";;
    route53)
      CMD+=" --aws-access-key $(printf '%q' "$AWS_ACCESS_KEY_ID") --aws-secret-key $(printf '%q' "$AWS_SECRET_ACCESS_KEY") --aws-region $(printf '%q' "$AWS_REGION")";;
    digitalocean)
      CMD+=" --do-token $(printf '%q' "$DO_API_TOKEN")";;
    linode)
      CMD+=" --linode-token $(printf '%q' "$LINODE_API_TOKEN")";;
    gcloud)
      CMD+=" --gcp-service-file $(printf '%q' "$GCP_SERVICE_ACCOUNT_FILE")";;
    desec)
      CMD+=" --desec-token $(printf '%q' "$DESEC_API_TOKEN")";;
  esac
  if [[ "$CERT_PROVIDER" == "zerossl" ]]; then
    CMD+=" --zerossl-email $(printf '%q' "$ZEROSSL_EMAIL") --zerossl-key $(printf '%q' "$ZEROSSL_KEY")"
  fi
  if [[ "$DOCKER_MODE" == true ]]; then
    CMD+=" --docker --docker-container $(printf '%q' "$DOCKER_CONTAINER_NAME")"
  fi
  color_echo "\n${GREEN}Your configuration is complete!${NC}"
  color_echo "${BOLD}To run the setup, execute:${NC}\n"
  color_echo "  ${CYAN}$CMD${NC}\n"
  color_echo "${YELLOW}Review the command above, then copy and run it in your shell to proceed.${NC}"
  exit 0
fi

# Dry run helper functions
run_or_show() {
  if [ "$DRY_RUN" = true ]; then
    color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} Would execute: ${CYAN}$1${NC}"
    if [ $# -gt 1 ]; then
      color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} $2"
    fi
  else
    eval "$1"
  fi
}

dry_run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} Would execute: ${CYAN}$*${NC}"
  else
    "$@"
  fi
}

dry_run_info() {
  if [ "$DRY_RUN" = true ]; then
    color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} $*"
  fi
}

# Pre-flight checks
REQUIRED_COMMANDS=(curl systemctl)
if [ "$DOCKER_MODE" = false ]; then
  REQUIRED_COMMANDS+=(lighttpd)
  REQUIRED_DIRS=(/etc/lighttpd /etc/lighttpd/conf-enabled /etc/lighttpd/certs /var/www/html)
else
  REQUIRED_COMMANDS+=(docker)
  REQUIRED_DIRS=()
fi

for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if [ "$DRY_RUN" = true ]; then
    if ! command -v "$cmd" &>/dev/null; then
      color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} ${RED}Warning:${NC} Required command $(highlight_var "$cmd") not found. Would need to be installed."
    else
      color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} Required command $(highlight_var "$cmd") is available."
    fi
  else
    if ! command -v "$cmd" &>/dev/null; then
      color_echo "${RED}Error:${NC} Required command $(highlight_var "$cmd") not found. Please install it before proceeding." >&2
      exit 1
    fi
  fi
done

if [ "$DOCKER_MODE" = true ]; then
  # Check if Docker container exists and is running
  if [ "$DRY_RUN" = true ]; then
    if command -v docker &>/dev/null; then
      if ! docker ps --format "table {{.Names}}" | grep -q "^${DOCKER_CONTAINER_NAME}$"; then
        color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} ${RED}Warning:${NC} Docker container $(highlight_var "$DOCKER_CONTAINER_NAME") not found or not running. Would need to be available." >&2
      else
        color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} Docker container $(highlight_var "$DOCKER_CONTAINER_NAME") is available."
      fi
    else
      color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} Docker not available for container check."
    fi
  else
    if ! docker ps --format "table {{.Names}}" | grep -q "^${DOCKER_CONTAINER_NAME}$"; then
      color_echo "${RED}Error:${NC} Docker container $(highlight_var "$DOCKER_CONTAINER_NAME") not found or not running." >&2
      exit 1
    fi
  fi
else
  for dir in "${REQUIRED_DIRS[@]}"; do
    if [ "$DRY_RUN" = true ]; then
      if [[ ! -d "$dir" ]]; then
        color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} ${RED}Warning:${NC} Required directory $(highlight_var "$dir") not found. Pi-hole may need to be installed correctly." >&2
      else
        color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} Required directory $(highlight_var "$dir") is available."
      fi
    else
      if [[ ! -d "$dir" ]]; then
        color_echo "${RED}Error:${NC} Required directory $(highlight_var "$dir") not found. Please ensure Pi-hole is installed correctly." >&2
        exit 1
      fi
    fi
  done
fi

if (( REVERT_MODE )); then
  color_echo "${MAGENTA}Reverting to last known good configs...${NC}"
  if [[ -d "$BACKUP_DIR" ]]; then
    if [ "$DOCKER_MODE" = false ]; then
      dry_run_info "Would copy backup configs from $(highlight_var "$BACKUP_DIR") to $(highlight_var "/etc/lighttpd/conf-enabled/")"
      dry_run_info "Would copy backup certificates from $(highlight_var "$BACKUP_DIR/certs/") to $(highlight_var "$CERT_BASE/")"
      dry_run_info "Would reload lighttpd service"
      if [ "$DRY_RUN" = false ]; then
        cp "$BACKUP_DIR"/*.conf /etc/lighttpd/conf-enabled/
        cp -r "$BACKUP_DIR/certs/"* "$CERT_BASE/"
        systemctl reload lighttpd
      fi
    else
      # Docker revert - restore certificates
      if [ -f "$BACKUP_DIR/tls.pem" ]; then
        dry_run_info "Would copy backup certificate $(highlight_var "$BACKUP_DIR/tls.pem") to Docker container $(highlight_var "$DOCKER_CONTAINER_NAME:/etc/pihole/tls.pem")"
        dry_run_info "Would restart pihole-FTL service in Docker container"
        if [ "$DRY_RUN" = false ]; then
          docker cp "$BACKUP_DIR/tls.pem" "${DOCKER_CONTAINER_NAME}:/etc/pihole/tls.pem"
          docker exec "${DOCKER_CONTAINER_NAME}" service pihole-FTL restart
        fi
      fi
    fi
    color_echo "${GREEN}Revert complete.${NC}" && exit 0
  else
    color_echo "${RED}No backup found.${NC}" >&2; exit 1
  fi
fi

# Prepare backup
echo "Backing up configs to $BACKUP_DIR"
dry_run_info "Would create backup directory: $BACKUP_DIR/certs"
if [ "$DRY_RUN" = false ]; then
  mkdir -p "$BACKUP_DIR/certs"
fi

if [ "$DOCKER_MODE" = false ]; then
  dry_run_info "Would backup lighttpd configs from /etc/lighttpd/conf-enabled/ to $BACKUP_DIR/"
  dry_run_info "Would backup certificates from $CERT_BASE/ to $BACKUP_DIR/certs/"
  if [ "$DRY_RUN" = false ]; then
    cp /etc/lighttpd/conf-enabled/*.conf "$BACKUP_DIR/"
    cp -r "$CERT_BASE/"* "$BACKUP_DIR/certs/" 2>/dev/null || true
  fi
else
  # Backup Docker certificates if they exist
  dry_run_info "Would check for existing Docker certificate at ${DOCKER_CONTAINER_NAME}:/etc/pihole/tls.pem"
  if [ "$DRY_RUN" = false ]; then
    docker exec "${DOCKER_CONTAINER_NAME}" test -f /etc/pihole/tls.pem && \
      docker cp "${DOCKER_CONTAINER_NAME}:/etc/pihole/tls.pem" "$BACKUP_DIR/tls.pem" || true
  fi
fi

cleanup_fail() {
  color_echo "${RED}${BOLD}❗ Error detected — rolling back...${NC}"
  if [ "$DOCKER_MODE" = false ]; then
    dry_run_info "Would restore backup configs from $(highlight_var "$BACKUP_DIR/") to $(highlight_var "/etc/lighttpd/conf-enabled/")"
    dry_run_info "Would restore backup certificates from $(highlight_var "$BACKUP_DIR/certs/") to $(highlight_var "$CERT_BASE/")"
    dry_run_info "Would reload lighttpd service"
    if [ "$DRY_RUN" = false ]; then
      cp "$BACKUP_DIR"/*.conf /etc/lighttpd/conf-enabled/
      cp -r "$BACKUP_DIR/certs/"* "$CERT_BASE/"
      systemctl reload lighttpd || true
    fi
  else
    # Docker rollback
    if [ -f "$BACKUP_DIR/tls.pem" ]; then
      dry_run_info "Would restore backup certificate to Docker container"
      dry_run_info "Would restart pihole-FTL service in Docker container"
      if [ "$DRY_RUN" = false ]; then
        docker cp "$BACKUP_DIR/tls.pem" "${DOCKER_CONTAINER_NAME}:/etc/pihole/tls.pem"
        docker exec "${DOCKER_CONTAINER_NAME}" service pihole-FTL restart || true
      fi
    fi
  fi
  color_echo "${YELLOW}Configs preserved in $(highlight_var "$BACKUP_DIR")${NC}"
  exit 1
}
trap cleanup_fail ERR

# Validate DNS provider credentials
validate_dns_credentials() {
  case "$DNS_PROVIDER" in
    cloudflare)
      if [[ -z "$CF_TOKEN" || -z "$CF_EMAIL" ]]; then
        color_echo "${RED}Error:${NC} Cloudflare requires --cf-token and --cf-email" >&2
        exit 1
      fi
      ;;
    namecheap)
      if [[ -z "$NAMECHEAP_USERNAME" || -z "$NAMECHEAP_API_KEY" ]]; then
        color_echo "${RED}Error:${NC} Namecheap requires --namecheap-username and --namecheap-key" >&2
        exit 1
      fi
      if [[ -z "$NAMECHEAP_SOURCEIP" ]]; then
        NAMECHEAP_SOURCEIP=$(curl -s https://api.ipify.org)
        color_echo "${BLUE}Using current IP for Namecheap:${NC} $(highlight_var "$NAMECHEAP_SOURCEIP")"
      fi
      ;;
    godaddy)
      if [[ -z "$GODADDY_API_KEY" || -z "$GODADDY_API_SECRET" ]]; then
        color_echo "${RED}Error:${NC} GoDaddy requires --godaddy-key and --godaddy-secret" >&2
        exit 1
      fi
      ;;
    route53)
      if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
        if [[ ! -f ~/.aws/credentials ]]; then
          color_echo "${RED}Error:${NC} AWS Route53 requires --aws-access-key and --aws-secret-key or ~/.aws/credentials file" >&2
          exit 1
        fi
      fi
      ;;
    digitalocean)
      if [[ -z "$DO_API_TOKEN" ]]; then
        color_echo "${RED}Error:${NC} DigitalOcean requires --do-token" >&2
        exit 1
      fi
      ;;
    linode)
      if [[ -z "$LINODE_API_TOKEN" ]]; then
        color_echo "${RED}Error:${NC} Linode requires --linode-token" >&2
        exit 1
      fi
      ;;
    gcloud)
      if [[ -z "$GCP_SERVICE_ACCOUNT_FILE" || ! -f "$GCP_SERVICE_ACCOUNT_FILE" ]]; then
        color_echo "${RED}Error:${NC} Google Cloud DNS requires --gcp-service-file pointing to a valid service account JSON file" >&2
        exit 1
      fi
      ;;
    desec)
      if [[ -z "$DESEC_API_TOKEN" ]]; then
        color_echo "${RED}Error:${NC} deSEC requires --desec-token" >&2
        exit 1
      fi
      ;;
    *)
      color_echo "${RED}Error:${NC} Unsupported DNS provider: $(highlight_var "$DNS_PROVIDER")" >&2
      color_echo "Supported providers: ${GREEN}cloudflare${NC}, ${GREEN}namecheap${NC}, ${GREEN}godaddy${NC}, ${GREEN}route53${NC}, ${GREEN}digitalocean${NC}, ${GREEN}linode${NC}, ${GREEN}gcloud${NC}, ${GREEN}desec${NC}" >&2
      exit 1
      ;;
  esac
}

validate_dns_credentials

# Ensure acme.sh installed
if ! command -v acme.sh &>/dev/null; then
  if [ "$(id -u)" = "0" ]; then
    ACME_HOME="/root/.acme.sh"
  else
    ACME_HOME="${HOME}/.acme.sh"
  fi

  if [ ! -f "${ACME_HOME}/acme.sh" ]; then
    echo "Installing acme.sh..."
    dry_run_info "Would download and install acme.sh to $ACME_HOME with email $ZEROSSL_EMAIL"
    if [ "$DRY_RUN" = false ]; then
      curl https://get.acme.sh | bash -s email="$ZEROSSL_EMAIL"
      export PATH="${ACME_HOME}:$PATH"
    fi
  fi
fi

# Set DNS credentials based on provider
setup_dns_credentials() {
  case "$DNS_PROVIDER" in
    cloudflare)
      export CF_Token="$CF_TOKEN"
      export CF_Email="$CF_EMAIL"
      DNS_METHOD="dns_cf"
      ;;
    namecheap)
      export Namecheap_Username="$NAMECHEAP_USERNAME"
      export Namecheap_API_Key="$NAMECHEAP_API_KEY"
      export Namecheap_Sourceip="$NAMECHEAP_SOURCEIP"
      DNS_METHOD="dns_namecheap"
      ;;
    godaddy)
      export GD_Key="$GODADDY_API_KEY"
      export GD_Secret="$GODADDY_API_SECRET"
      DNS_METHOD="dns_gd"
      ;;
    route53)
      if [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
        export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
        export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
        export AWS_DEFAULT_REGION="$AWS_REGION"
      fi
      DNS_METHOD="dns_aws"
      ;;
    digitalocean)
      export DO_API_KEY="$DO_API_TOKEN"
      DNS_METHOD="dns_dgon"
      ;;
    linode)
      export LINODE_V4_API_KEY="$LINODE_API_TOKEN"
      DNS_METHOD="dns_linode"
      ;;
    gcloud)
      export GCE_SERVICE_ACCOUNT_FILE="$GCP_SERVICE_ACCOUNT_FILE"
      DNS_METHOD="dns_gcloud"
      ;;
    desec)
      export DEDYN_TOKEN="$DESEC_API_TOKEN"
      DNS_METHOD="dns_desec"
      ;;
  esac
}

setup_dns_credentials

# Set DNS credentials for Cloudflare
export CF_Token="$CF_TOKEN"
export CF_Email="$CF_EMAIL"

# Register and issue certificate
if [[ "$CERT_PROVIDER" == "zerossl" ]]; then
  dry_run_info "Would register ZeroSSL account with email: $(highlight_var "$ZEROSSL_EMAIL")"
  dry_run_info "Would issue certificate for domain: $(highlight_var "$DOMAIN") using DNS method: $(highlight_var "$DNS_METHOD") with ZeroSSL"
  if [ "$DRY_RUN" = false ]; then
    acme.sh --register-account -m "$ZEROSSL_EMAIL" \
      --server zerossl --zerossl-api-key "$ZEROSSL_KEY"
    acme.sh --issue --dns "$DNS_METHOD" -d "$DOMAIN" --server zerossl --keylength "$KEY_LENGTH"
  fi
elif [[ "$CERT_PROVIDER" == "letsencrypt" ]]; then
  dry_run_info "Would set default CA to Let's Encrypt"
  dry_run_info "Would issue certificate for domain: $(highlight_var "$DOMAIN") using DNS method: $(highlight_var "$DNS_METHOD") with Let's Encrypt"
  if [ "$DRY_RUN" = false ]; then
    acme.sh --set-default-ca --server letsencrypt
    acme.sh --issue --dns "$DNS_METHOD" -d "$DOMAIN" --keylength "$KEY_LENGTH"
  fi
else
  color_echo "${RED}Invalid cert provider:${NC} $(highlight_var "$CERT_PROVIDER")" >&2; exit 1
fi

# Install certificates
if [ "$DOCKER_MODE" = true ]; then
  # Docker installation approach
  color_echo "${BLUE}Installing certificate for Docker Pi-hole...${NC}"

  # Get certificate paths
  if [ "$(id -u)" = "0" ]; then
    ACME_HOME="/root/.acme.sh"
  else
    ACME_HOME="${HOME}/.acme.sh"
  fi

  if [[ "$KEY_LENGTH" == "ec-256" ]]; then
    CERT_PATH="${ACME_HOME}/${DOMAIN}_ecc"
  else
    CERT_PATH="${ACME_HOME}/${DOMAIN}"
  fi

  KEY_FILE="${CERT_PATH}/${DOMAIN}.key"
  CERT_FILE="${CERT_PATH}/${DOMAIN}.cer"
  COMBINED_CERT="/tmp/tls.pem"

  # Combine key and certificate
  run_or_show "cat '${KEY_FILE}' '${CERT_FILE}' > '${COMBINED_CERT}'" "Combining key and certificate files"

  # Copy to Docker container and configure
  run_or_show "docker cp '${COMBINED_CERT}' '${DOCKER_CONTAINER_NAME}:/etc/pihole/tls.pem'" "Copying certificate to Docker container"
  run_or_show "docker exec '${DOCKER_CONTAINER_NAME}' pihole-FTL --config webserver.domain '${DOMAIN}'" "Configuring Pi-hole domain in Docker container"
  run_or_show "docker exec '${DOCKER_CONTAINER_NAME}' service pihole-FTL restart" "Restarting Pi-hole FTL service in Docker container"

  # Set up auto-renewal hook for Docker
  RELOAD_CMD="cat ${KEY_FILE} ${CERT_FILE} > ${COMBINED_CERT} && docker cp ${COMBINED_CERT} ${DOCKER_CONTAINER_NAME}:/etc/pihole/tls.pem && docker exec ${DOCKER_CONTAINER_NAME} service pihole-FTL restart"
  run_or_show "acme.sh --install-cert -d '${DOMAIN}' --reloadcmd '${RELOAD_CMD}'" "Setting up auto-renewal hook for Docker"

  # Clean up temporary files
  run_or_show "rm -f '${COMBINED_CERT}'" "Cleaning up temporary certificate file"

else
  # Traditional Lighttpd installation
  color_echo "${BLUE}Installing certificate for Lighttpd...${NC}"

  CERT_DIR="$CERT_BASE/$DOMAIN"
  run_or_show "mkdir -p '$CERT_DIR'" "Creating certificate directory"
  RELOAD_CMD="systemctl force-reload lighttpd"
  run_or_show "acme.sh --install-cert -d '$DOMAIN' --key-file '$CERT_DIR/privkey.pem' --fullchain-file '$CERT_DIR/fullchain.pem' --reloadcmd '$RELOAD_CMD'" "Installing certificate for Lighttpd"

  # Configure Lighttpd SSL + redirects
  CONFSSL="/etc/lighttpd/conf-available/99-pihole-ssl.conf"
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Would create Lighttpd SSL configuration at: $CONFSSL"
    echo "[DRY RUN] Configuration would include:"
    echo "  - SSL engine enabled on port 443"
    echo "  - Certificate files: $CERT_DIR/fullchain.pem and $CERT_DIR/privkey.pem"
    echo "  - TLS 1.3 minimum protocol"
    echo "  - HTTP to HTTPS redirect"
    echo "  - Root domain redirect to /admin/"
  else
    cat > "$CONFSSL" <<EOF
server.modules += ( "mod_openssl" )
\$SERVER["socket"] == ":443" {
  ssl.engine  = "enable"
  ssl.pemfile = "$CERT_DIR/fullchain.pem"
  ssl.privkey = "$CERT_DIR/privkey.pem"
  ssl.openssl.ssl-conf-cmd = ("MinProtocol" => "TLSv1.3")
}
\$HTTP["scheme"] == "http" {
  \$HTTP["host"] =~ ".*" {
    url.redirect = (".*" => "https://%0\$0")
  }
}
\$HTTP["host"] == "$DOMAIN" {
  \$HTTP["url"] == "/" {
    url.redirect = ("" => "/admin/")
  }
}
EOF
  fi

  run_or_show "ln -sf '$CONFSSL' /etc/lighttpd/conf-enabled/" "Enabling SSL configuration"

  # HTTP root->HTTPS redirect
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Would create redirect page at: /var/www/html/index.html"
    echo "[DRY RUN] Page would redirect to: https://$DOMAIN/admin/"
  else
    cat > /var/www/html/index.html <<HTML
<!DOCTYPE html><meta http-equiv="refresh" content="0; url=https://$DOMAIN/admin/">
<script>location="https://$DOMAIN/admin/";</script>
<title>Redirecting…</title>
HTML
  fi

  # Ensure SSL module enabled
  run_or_show "apt-get update" "Updating package lists"
  run_or_show "apt-get install -y lighttpd-mod-openssl" "Installing Lighttpd OpenSSL module"
  run_or_show "lighty-enable-mod ssl" "Enabling SSL module"

  run_or_show "systemctl force-reload lighttpd" "Reloading Lighttpd configuration"

  # Setup renewal cron
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Would create cron job at: $CRON_PATH"
    echo "[DRY RUN] Cron job would run daily at 2 AM to renew certificates"
  else
    cat > "$CRON_PATH" <<CRON
SHELL=/bin/bash
MAILTO=root
0 2 * * * root ~/.acme.sh/acme.sh --cron --home \$HOME/.acme.sh >/dev/null && systemctl force-reload lighttpd
CRON
  fi
fi

if [ "$DOCKER_MODE" = true ]; then
  if [ "$DRY_RUN" = true ]; then
    color_echo "${GREEN}✔ [${YELLOW}DRY RUN${NC}${GREEN}]${NC} Setup simulation complete. Would be available at ${BOLD}${CYAN}https://$DOMAIN/admin/${NC}"
    color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} Docker container that would be configured: $(highlight_var "$DOCKER_CONTAINER_NAME")"
  else
    color_echo "${GREEN}✔ Setup complete. HTTPS available at ${BOLD}${CYAN}https://$DOMAIN/admin/${NC}"
    color_echo "Docker container: $(highlight_var "$DOCKER_CONTAINER_NAME")"
  fi
else
  if [ "$DRY_RUN" = true ]; then
    color_echo "${GREEN}✔ [${YELLOW}DRY RUN${NC}${GREEN}]${NC} Setup simulation complete. Would be available at ${BOLD}${CYAN}https://$DOMAIN/admin/${NC}"
  else
    color_echo "${GREEN}✔ Setup complete. HTTPS available at ${BOLD}${CYAN}https://$DOMAIN/admin/${NC}"
  fi
fi

if [ "$DRY_RUN" = true ]; then
  color_echo ""
  color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} To actually execute these changes, run the command again without --dry-run"
  color_echo "${YELLOW}[${BOLD}DRY RUN${NC}${YELLOW}]${NC} To revert (if changes were made), run: $0 --revert"
else
  color_echo "${BLUE}To revert, run: $0 --revert${NC}"
fi

# Provider-specific notes
case "$DNS_PROVIDER" in
  route53)
    echo ""
    echo "AWS Route53 Note: If you encounter issues with permissions,"
    echo "ensure your IAM user/role has the following permissions:"
    echo "  - route53:ListHostedZones"
    echo "  - route53:GetChange"
    echo "  - route53:ChangeResourceRecordSets"
    ;;
  gcloud)
    echo ""
    echo "Google Cloud DNS Note: Make sure your service account has the"
    echo "DNS Administrator role or appropriate permissions to create/modify records."
    ;;
  namecheap)
    echo ""
    echo "Namecheap Note: Ensure API access is enabled in your account and"
    echo "the source IP (${NAMECHEAP_SOURCEIP}) is whitelisted."
    ;;
esac

# Elevation check (skip for --dry-run and --init)
if [ "$DRY_RUN" = false ] && [ "$INIT_MODE" = 0 ]; then
  if [ "$(id -u)" -ne 0 ]; then
    color_echo "${RED}Error:${NC} This script must be run as root (use sudo) for real operations."
    color_echo "${YELLOW}Tip:${NC} You can use --dry-run or --init as a normal user."
    exit 1
  fi
fi
