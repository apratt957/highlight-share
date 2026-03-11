#!/bin/bash

set -e

# ─────────────────────────────────────────
# Colors
# ─────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────
info()    { echo -e "${CYAN}→${RESET} $1"; }
success() { echo -e "${GREEN}✓${RESET} $1"; }
warn()    { echo -e "${YELLOW}!${RESET} $1"; }
error()   { echo -e "${RED}✗${RESET} $1"; exit 1; }
section() { echo -e "\n${BOLD}$1${RESET}"; echo "────────────────────────────────────────"; }

prompt() {
  local var_name=$1
  local prompt_text=$2
  local secret=${3:-false}
  local value=""

  while [[ -z "$value" ]]; do
    if [[ "$secret" == "true" ]]; then
      read -rsp "${prompt_text}: " value
      echo
    else
      read -rp "${prompt_text}: " value
    fi
    if [[ -z "$value" ]]; then
      warn "This field is required."
    fi
  done

  eval "$var_name=\"$value\""
}

# ─────────────────────────────────────────
# Header
# ─────────────────────────────────────────
echo ""
echo -e "${BOLD}highlight-share setup${RESET}"
echo "This script will deploy the Cloudflare Worker and configure the Discord bot."
echo ""

# ─────────────────────────────────────────
# 1. Check prerequisites
# ─────────────────────────────────────────
section "Checking prerequisites"

check_command() {
  if command -v "$1" >/dev/null 2>&1; then
    success "$1 found ($(command -v "$1"))"
  else
    error "$1 is required but not installed. $2"
  fi
}

check_command node  "Install from https://nodejs.org"
check_command npm   "Install from https://nodejs.org"
check_command wrangler "Install with: npm install -g wrangler"

# Check wrangler is authenticated
info "Checking Wrangler authentication..."
if ! wrangler whoami >/dev/null 2>&1; then
  warn "You are not logged into Wrangler."
  info "Opening Cloudflare login..."
  wrangler login || error "Wrangler login failed. Please run 'wrangler login' manually and re-run this script."
fi
success "Wrangler authenticated"

# ─────────────────────────────────────────
# 2. Collect credentials
# ─────────────────────────────────────────
section "Discord configuration"

echo "You'll need the following from discord.com/developers:"
echo "  • Bot token        (Bot → Token)"
echo "  • Client ID        (OAuth2 → Client ID)"
echo "  • Guild ID         (Your Discord server ID — right-click server → Copy Server ID)"
echo ""

prompt BOT_TOKEN  "Bot token" true
prompt CLIENT_ID  "Client ID"
prompt GUILD_ID   "Guild ID"

# ─────────────────────────────────────────
# 3. Deploy Cloudflare Worker
# ─────────────────────────────────────────
section "Deploying Cloudflare Worker"

WORKER_DIR="$(cd "$(dirname "$0")/worker" 2>/dev/null && pwd)" || error "Could not find worker/ directory. Make sure you're running this script from the repo root."

info "Installing worker dependencies..."
(cd "$WORKER_DIR" && npm install --silent) || error "npm install failed in worker/"
success "Dependencies installed"

# Create KV namespace
info "Creating KV namespace..."
KV_OUTPUT=$(cd "$WORKER_DIR" && wrangler kv namespace create TOKENS 2>&1)

# Extract the id from output like: { binding = "TOKENS", id = "abc123" }
KV_ID=$(echo "$KV_OUTPUT" | grep -oE '"id":\s*"[a-f0-9]+"' | grep -oE '[a-f0-9]{32}')

if [[ -z "$KV_ID" ]]; then
  # Try alternate output format: id = "abc123"
  KV_ID=$(echo "$KV_OUTPUT" | grep -oE "id = \"[a-f0-9]+\"" | grep -oE '[a-f0-9]{32}')
fi

if [[ -z "$KV_ID" ]]; then
  echo ""
  echo "Could not automatically extract KV namespace ID from wrangler output:"
  echo "$KV_OUTPUT"
  echo ""
  prompt KV_ID "Please paste the KV namespace ID from the output above"
fi

success "KV namespace created: $KV_ID"

# Inject KV ID into wrangler.jsonc (top-level placeholder only, leave dev env untouched)
WRANGLER_FILE="$WORKER_DIR/wrangler.jsonc"

# Check placeholder exists
if grep -q "YOUR_KV_NAMESPACE_ID" "$WRANGLER_FILE"; then
  # Use a temp file to avoid in-place sed portability issues (macOS vs Linux)
  TEMP_FILE=$(mktemp)
  # Only replace the first occurrence (top-level, not the dev env)
  awk '/YOUR_KV_NAMESPACE_ID/ && !replaced { sub("YOUR_KV_NAMESPACE_ID", "'"$KV_ID"'"); replaced=1 } { print }' "$WRANGLER_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$WRANGLER_FILE"
  success "KV namespace ID written to wrangler.jsonc"
else
  warn "Placeholder YOUR_KV_NAMESPACE_ID not found in wrangler.jsonc — skipping. You may need to set it manually."
fi

# Set BOT_TOKEN as a wrangler secret
info "Setting BOT_TOKEN secret on Cloudflare Worker..."
echo "$BOT_TOKEN" | (cd "$WORKER_DIR" && wrangler secret put BOT_TOKEN) || error "Failed to set BOT_TOKEN secret."
success "BOT_TOKEN secret set"

# Deploy worker
info "Deploying worker..."
DEPLOY_OUTPUT=$(cd "$WORKER_DIR" && wrangler deploy 2>&1)
echo "$DEPLOY_OUTPUT" | tail -5

# Extract worker URL
WORKER_URL=$(echo "$DEPLOY_OUTPUT" | grep -oE 'https://[a-zA-Z0-9._-]+\.workers\.dev' | head -1)

if [[ -z "$WORKER_URL" ]]; then
  echo ""
  warn "Could not automatically extract worker URL from deploy output."
  prompt WORKER_URL "Please paste your worker URL (e.g. https://your-worker.your-subdomain.workers.dev)"
fi

success "Worker deployed at: $WORKER_URL"

# ─────────────────────────────────────────
# 4. Configure bot
# ─────────────────────────────────────────
section "Configuring Discord bot"

BOT_DIR="$(cd "$(dirname "$0")/bot" 2>/dev/null && pwd)" || error "Could not find bot/ directory."

info "Installing bot dependencies..."
(cd "$BOT_DIR" && npm install --silent) || error "npm install failed in bot/"
success "Dependencies installed"

# Write .env
ENV_FILE="$BOT_DIR/.env"
cat > "$ENV_FILE" <<EOF
BOT_TOKEN=$BOT_TOKEN
WORKER_URL=$WORKER_URL
CLIENT_ID=$CLIENT_ID
GUILD_ID=$GUILD_ID
EOF
success ".env written to bot/.env"

# ─────────────────────────────────────────
# 5. Summary
# ─────────────────────────────────────────
section "Done"

success "Worker deployed:  $WORKER_URL"
success "Bot configured:   $BOT_DIR/.env"
echo ""
echo "Next steps:"
echo ""
echo "  1. Start the bot:"
echo -e "     ${CYAN}cd bot && node bot.js${RESET}"
echo ""
echo "  2. If self-hosting the KOReader plugin, update the URL at the top of:"
echo -e "     ${CYAN}highlightshare.koplugin/main.lua${RESET}"
echo -e "     Set: ${CYAN}local worker_url = \"$WORKER_URL/quote\"${RESET}"
echo ""
echo "  3. In Discord, run ${CYAN}/token${RESET} to get your highlight token,"
echo "     then enter it in KOReader under Menu → Highlight Share Token."
echo ""
