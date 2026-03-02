#!/usr/bin/env bash
# =============================================================================
# Sentro Self-Hosted — Install Script
# =============================================================================
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/sentro-dev/self-hosted/main/install.sh | bash
#
# Or run locally:
#   chmod +x install.sh && ./install.sh
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

# ── Config ────────────────────────────────────────────────────────────────────
INSTALL_DIR="${SENTRO_INSTALL_DIR:-$HOME/sentro}"
VERSION="${SENTRO_VERSION:-latest}"
BASE_URL="https://raw.githubusercontent.com/sentro-dev/self-hosted/main"

# ── Functions ─────────────────────────────────────────────────────────────────
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
fatal() { error "$1"; exit 1; }

banner() {
  echo ""
  echo -e "${CYAN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════╗"
  echo "  ║     Sentro Self-Hosted Installer    ║"
  echo "  ╚═══════════════════════════════════════════╝"
  echo -e "${NC}"
  echo ""
}

generate_secret() {
  openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p -c 64 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))"
}

generate_password() {
  openssl rand -base64 24 2>/dev/null | tr -d '/+=' | head -c 24 || head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 24
}

check_requirements() {
  info "Checking requirements..."

  # Docker
  if command -v docker &>/dev/null; then
    ok "Docker found: $(docker --version | head -1)"
  elif command -v podman &>/dev/null; then
    ok "Podman found: $(podman --version | head -1)"
    warn "Using Podman — aliasing 'docker' commands to 'podman'"
    alias docker=podman
  else
    fatal "Docker or Podman is required. Install from https://docs.docker.com/get-docker/"
  fi

  # Docker Compose
  if docker compose version &>/dev/null; then
    ok "Docker Compose found: $(docker compose version --short 2>/dev/null || echo 'v2+')"
  elif docker-compose version &>/dev/null; then
    ok "Docker Compose (standalone) found"
    warn "Consider upgrading to Docker Compose v2 (built into Docker CLI)"
  else
    fatal "Docker Compose is required. Install from https://docs.docker.com/compose/install/"
  fi

  # openssl (for secret generation)
  if command -v openssl &>/dev/null; then
    ok "OpenSSL found"
  else
    warn "OpenSSL not found — will use fallback for secret generation"
  fi

  echo ""
}

setup_directory() {
  info "Setting up installation directory: ${INSTALL_DIR}"

  if [ -d "${INSTALL_DIR}" ] && [ -f "${INSTALL_DIR}/.env" ]; then
    warn "Existing installation detected at ${INSTALL_DIR}"
    echo ""
    read -rp "  Overwrite? This will NOT delete your data volumes. [y/N] " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
      info "Aborting. Your existing installation is untouched."
      exit 0
    fi
  fi

  mkdir -p "${INSTALL_DIR}"
}

download_files() {
  info "Downloading configuration files..."

  local FILES=(docker-compose.yml Caddyfile .env.example prometheus.yml server.mjs)

  # If running from the repo, copy locally. Otherwise, download.
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [ -f "${SCRIPT_DIR}/docker/docker-compose.yml" ]; then
    info "Using local files from ${SCRIPT_DIR}/docker"
    for f in "${FILES[@]}"; do
      [ -f "${SCRIPT_DIR}/docker/${f}" ] && cp "${SCRIPT_DIR}/docker/${f}" "${INSTALL_DIR}/${f}"
    done
  elif [ -f "${SCRIPT_DIR}/docker-compose.yml" ]; then
    info "Using local files from ${SCRIPT_DIR}"
    for f in "${FILES[@]}"; do
      [ -f "${SCRIPT_DIR}/${f}" ] && cp "${SCRIPT_DIR}/${f}" "${INSTALL_DIR}/${f}"
    done
  else
    info "Downloading from GitHub..."
    for f in "${FILES[@]}"; do
      curl -fsSL "${BASE_URL}/${f}" -o "${INSTALL_DIR}/${f}"
    done
  fi

  ok "Configuration files downloaded"
}

generate_env() {
  local force="${1:-false}"

  if [[ "$force" != "true" ]] && [[ -f "${INSTALL_DIR}/.env" ]]; then
    info "Existing .env found — skipping generation (use --force-env to regenerate)"
    return
  fi

  info "Generating environment configuration..."

  POSTGRES_PW="$(generate_password)"
  REDIS_PW="$(generate_password)"
  AUTH_SEC="$(generate_secret)"
  ENC_KEY="$(generate_secret)"
  ADMIN_PW="$(generate_password)"
  ADMIN_SESS="$(generate_secret)"
  GRAFANA_PW="$(generate_password)"

  cat > "${INSTALL_DIR}/.env" << EOF
# =============================================================================
# Sentro Self-Hosted — Generated Configuration
# Generated on: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# =============================================================================

# License (Community edition — 5 monitors, 1 member)
# Purchase a license at https://sentro.dev/self-hosting to unlock higher limits.
SENTRO_LICENSE_KEY=

# Image
SENTRO_IMAGE_REGISTRY=ghcr.io/sentro-dev/platform
SENTRO_IMAGE_TAG=${VERSION}

# Domains (change to your actual domains for production)
DOMAIN_APP=app.localhost
DOMAIN_ADMIN=admin.localhost
DOMAIN_API=api.localhost

# Database
POSTGRES_USER=sentro
POSTGRES_PASSWORD=${POSTGRES_PW}
POSTGRES_DB=sentro

# Redis
REDIS_PASSWORD=${REDIS_PW}

# Auth
AUTH_SECRET=${AUTH_SEC}
AUTH_URL=http://localhost:3001

# Encryption
ENCRYPTION_KEY=${ENC_KEY}

# Admin Panel
ADMIN_EMAIL=admin@localhost
ADMIN_PASSWORD=${ADMIN_PW}
ADMIN_SESSION_SECRET=${ADMIN_SESS}

# API
API_CORS_ORIGIN=http://localhost:3001,http://localhost:3002

# Email (configure a real SMTP server for production)
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_FROM=noreply@sentro.local

# Observability
GRAFANA_ADMIN_PASSWORD=${GRAFANA_PW}
PROMETHEUS_METRICS_PORT=9464

# Optional: OAuth (uncomment and configure)
# AUTH_GOOGLE_ID=
# AUTH_GOOGLE_SECRET=
# AUTH_GITHUB_ID=
# AUTH_GITHUB_SECRET=

# Optional: SMS alerts
# SMS_PROVIDER=twilio
# TWILIO_ACCOUNT_SID=
# TWILIO_AUTH_TOKEN=
# TWILIO_FROM_NUMBER=

# Optional: AI Assistant
# AI_PROVIDER=openai
# OPENAI_API_KEY=
# ANTHROPIC_API_KEY=
EOF

  ok "Environment file generated"
  echo ""
  echo -e "  ${BOLD}Admin credentials:${NC}"
  echo -e "    Email:    ${CYAN}admin@localhost${NC}"
  echo -e "    Password: ${CYAN}${ADMIN_PW}${NC}"
  echo ""
  echo -e "  ${YELLOW}Save these credentials! They won't be shown again.${NC}"
  echo ""
}

start_services() {
  info "Starting Sentro services..."
  echo ""

  cd "${INSTALL_DIR}"

  # Start core services
  docker compose up -d postgres redis
  info "Waiting for database to be ready..."
  sleep 5

  # Start app services (migrate runs first via depends_on)
  docker compose up -d

  ok "All services started"
}

wait_for_ready() {
  info "Waiting for services to be ready..."

  local max_attempts=30
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    if curl -sf http://localhost:3001/api/health &>/dev/null; then
      ok "Dashboard is ready!"
      break
    fi
    attempt=$((attempt + 1))
    sleep 2
  done

  if [ $attempt -eq $max_attempts ]; then
    warn "Dashboard not responding yet. It may still be starting up."
    warn "Check logs with: docker compose -f ${INSTALL_DIR}/docker-compose.yml logs -f"
  fi
}

print_summary() {
  echo ""
  echo -e "${GREEN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════╗"
  echo "  ║       Installation Complete!              ║"
  echo "  ╚═══════════════════════════════════════════╝"
  echo -e "${NC}"
  echo ""
  echo -e "  ${BOLD}Service URLs:${NC}"
  echo -e "    Dashboard:    ${CYAN}http://localhost:3001${NC}"
  echo -e "    Admin Panel:  ${CYAN}http://localhost:3002${NC}"
  echo -e "    REST API:     ${CYAN}http://localhost:4000${NC}"
  echo ""
  echo -e "  ${BOLD}Quick start:${NC}"
  echo -e "    1. Open ${CYAN}http://localhost:3001/register${NC} to create your account"
  echo -e "    2. Open ${CYAN}http://localhost:3002${NC} to access the admin panel"
  echo -e "    3. Go to Monitors > Add Monitor to start monitoring"
  echo ""
  echo -e "  ${BOLD}Useful commands:${NC}"
  echo -e "    ${CYAN}cd ${INSTALL_DIR}${NC}"
  echo -e "    docker compose logs -f          # Follow all logs"
  echo -e "    docker compose logs -f worker   # Worker logs only"
  echo -e "    docker compose ps               # Service status"
  echo -e "    docker compose down             # Stop all services"
  echo -e "    docker compose up -d            # Start all services"
  echo ""
  echo -e "  ${BOLD}Enable monitoring dashboard:${NC}"
  echo -e "    docker compose --profile monitoring up -d"
  echo -e "    Grafana: ${CYAN}http://localhost:3030${NC}  (admin / see .env)"
  echo ""
  echo -e "  ${BOLD}Enable docs + sandbox:${NC}"
  echo -e "    docker compose --profile docs --profile sandbox up -d"
  echo ""
  echo -e "  ${BOLD}License:${NC}"
  echo -e "    Running in ${CYAN}Community${NC} mode (5 monitors, 1 member)."
  echo -e "    To upgrade, set ${CYAN}SENTRO_LICENSE_KEY${NC} in .env and restart."
  echo -e "    Purchase: ${CYAN}https://sentro.dev/self-hosting${NC}"
  echo ""
  echo -e "  Configuration: ${INSTALL_DIR}/.env"
  echo -e "  Documentation: ${CYAN}https://docs.sentro.dev/docs/self-hosting${NC}"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  banner
  check_requirements
  setup_directory
  download_files
  generate_env "$FORCE_ENV"

  if [[ "${NO_START:-false}" == "true" ]]; then
    info "Skipping service start (--no-start)"
    print_summary
    return 0
  fi

  start_services
  wait_for_ready
  print_summary
}

# Parse args
FORCE_ENV=false
NO_START=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-env)
      FORCE_ENV=true
      shift
      ;;
    --dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --no-start)
      NO_START=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --dir DIR        Installation directory (default: ~/sentro)"
      echo "  --version TAG    Docker image version tag (default: latest)"
      echo "  --force-env      Regenerate .env even if it exists"
      echo "  --no-start       Download files and generate config without starting services"
      echo "  -h, --help       Show this help message"
      exit 0
      ;;
    *)
      fatal "Unknown option: $1. Use --help for usage."
      ;;
  esac
done

main
