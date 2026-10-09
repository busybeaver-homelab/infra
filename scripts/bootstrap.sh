#!/usr/bin/env bash

set -euo pipefail

# Homelab & Cloud Infrastructure Bootstrap Script
# Date: 2026-06-07

# Colors for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# 1. Detect OS
OS="$(uname -s)"
log_info "Detected Operating System: $OS"

# 2. Install Mise if not installed
if ! command -v mise &>/dev/null; then
  log_info "Mise is not installed. Installing Mise..."
  if [ "$OS" = "Darwin" ] && command -v brew &>/dev/null; then
    log_info "Installing Mise via Homebrew..."
    brew install mise
  else
    log_info "Installing Mise via curl script..."
    curl https://mise.run | sh
    # Add to path for current session execution
    export PATH="$HOME/.local/share/mise/bin:$PATH"
  fi
else
  log_info "Mise is already installed."
fi

# Ensure mise is in path for the rest of this script
if [ -d "$HOME/.local/share/mise/bin" ]; then
  export PATH="$HOME/.local/share/mise/bin:$PATH"
fi

# 3. Run mise install to install pinned tools (opentofu, age, etc.)
log_info "Running 'mise install' to configure global tools..."
mise install

# 3b. Install git hooks with lefthook
log_info "Installing git hooks with lefthook..."
mise exec lefthook -- lefthook install --force
HOOK_PATH="$(git rev-parse --git-path hooks)/pre-commit"
if [ -f "$HOOK_PATH" ]; then
  # Ensure pre-commit hook fails closed if lefthook cannot be located
  python3 -c "
import sys
p = sys.argv[1]
with open(p, 'r') as f:
    content = f.read()
target = 'echo \"Can\'t find lefthook in PATH\"'
replacement = '''echo \"ERROR: Can\'t find lefthook in PATH or mise! Hooks cannot run.\" >&2
      echo \"Run ./scripts/bootstrap.sh or \'mise install\' to configure environment.\" >&2
      exit 1'''
if target in content:
    with open(p, 'w') as f:
        f.write(content.replace(target, replacement))
" "$HOOK_PATH"
fi

# 3c. Ensure git-crypt is installed and unlock if locked
if ! command -v git-crypt &>/dev/null; then
  log_info "git-crypt is not installed. Installing..."
  if [ "$OS" = "Darwin" ] && command -v brew &>/dev/null; then
    log_info "Installing git-crypt via Homebrew..."
    brew install git-crypt
  else
    log_warn "git-crypt is not found. Please install git-crypt via your package manager."
  fi
else
  log_info "git-crypt is installed."
fi

if [ -d ".git-crypt" ] && command -v git-crypt &>/dev/null; then
  # Check if docs/ is currently encrypted/locked by git-crypt
  # A locked git-crypt file starts with the binary \0GITCRYPT signature
  if [ -f "docs/plans/task.md" ] && head -c 10 "docs/plans/task.md" 2>/dev/null | grep -q "GITCRYPT"; then
    log_warn "docs/ is currently locked by git-crypt."
    if gpg --list-secret-keys 5EE1590FF82DC2A3829D224FAA73ACF495CC009D &>/dev/null; then
      log_info "Production GPG key found in keyring. Unlocking docs/..."
      git-crypt unlock
      log_info "Successfully unlocked docs/."
    else
      log_warn "Production GPG key 5EE1590FF82DC2A3829D224FAA73ACF495CC009D not found in keyring."
      log_warn "Import your production GPG key and run 'git-crypt unlock' to view and edit docs/."
    fi
  else
    log_info "docs/ is unlocked or not encrypted."
  fi
fi

# 4. Generate initial age key for SOPS
AGE_KEY_DIR="$HOME/.config/sops/age"
AGE_KEY_FILE="$AGE_KEY_DIR/keys.txt"

if [ ! -f "$AGE_KEY_FILE" ]; then
  log_info "No age key found at $AGE_KEY_FILE. Generating a new key pair..."
  mkdir -p "$AGE_KEY_DIR"

  # We use mise exec to run age-keygen in case age isn't in global shell yet
  if mise exec age -- age-keygen -o "$AGE_KEY_FILE" &>/dev/null; then
    log_info "Successfully generated age key pair at $AGE_KEY_FILE"
    # Print public key
    PUBLIC_KEY=$(mise exec age -- age-keygen -y "$AGE_KEY_FILE")
    log_info "Public Key: $PUBLIC_KEY"
    log_warn "Please back up the private key file: $AGE_KEY_FILE"
  else
    log_error "Failed to generate age key. Is 'age' installed via mise?"
    exit 1
  fi
else
  log_info "An age key pair already exists at $AGE_KEY_FILE."
  PUBLIC_KEY=$(mise exec age -- age-keygen -y "$AGE_KEY_FILE")
  log_info "Current Public Key: $PUBLIC_KEY"
fi

# 5. Bootstrap uv virtual environment
log_info "Bootstrapping Python virtual environment with uv..."
if ! command -v uv &>/dev/null; then
  log_info "uv is not installed. Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  # Add to path for current session
  export PATH="$HOME/.local/bin:$PATH"
fi

# Create virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
  log_info "Creating .venv virtual environment..."
  uv venv
fi

log_info "Syncing Python dependencies from pyproject.toml..."
uv pip install -e .

# 5b. Generate or retrieve OpenTofu state encryption passphrase
TOFU_PASSPHRASE_FILE="${HOME}/.config/homelab-infra/tofu-passphrase"
if [ ! -f "${TOFU_PASSPHRASE_FILE}" ]; then
  log_info "Generating OpenTofu state encryption passphrase..."
  mkdir -p "$(dirname "${TOFU_PASSPHRASE_FILE}")"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 >"${TOFU_PASSPHRASE_FILE}"
  else
    head -c 32 /dev/urandom | base64 >"${TOFU_PASSPHRASE_FILE}"
  fi
  chmod 600 "${TOFU_PASSPHRASE_FILE}"
  log_info "Passphrase written to: ${TOFU_PASSPHRASE_FILE}"
  log_warn "IMPORTANT: Back up ${TOFU_PASSPHRASE_FILE} securely or store in SOPS."
  log_warn "If you lose it, the local state files become unrecoverable."
else
  log_info "OpenTofu passphrase already exists at: ${TOFU_PASSPHRASE_FILE}"
fi

log_info "Bootstrap complete!"
log_info "To enable mise in your shell, add this to your rc file (~/.zshrc, ~/.bashrc, etc.):"
echo -e "  ${YELLOW}eval \"\$(mise activate zsh)\"${NC}  # or bash, fish, etc."
log_info "To use the generated age key with SOPS, make sure this environment variable is set:"
echo -e "  ${YELLOW}export SOPS_AGE_KEY_FILE=\"$AGE_KEY_FILE\"${NC}"
log_info "OpenTofu state encryption: scripts auto-resolve the passphrase from SOPS or local fallback file."
echo -e "  ${YELLOW}# (Optional) Store passphrase in production SOPS:${NC}"
echo -e "  ${YELLOW}mise exec -- sops set secrets/credentials.sops.yaml '[\"opentofu\"][\"state_encryption_passphrase\"]' \"\\\"\$(cat ${TOFU_PASSPHRASE_FILE})\\\"\"${NC}"
echo -e "  ${YELLOW}# (Optional) Or set explicit environment variable in shell rc:${NC}"
echo -e "  ${YELLOW}export TF_VAR_state_encryption_passphrase=\"\$(cat ${TOFU_PASSPHRASE_FILE})\"${NC}"
