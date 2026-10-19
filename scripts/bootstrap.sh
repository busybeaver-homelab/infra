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

# 3b. Install git hooks with lefthook (assert_lefthook_installed: true in lefthook.yml enforces fail-closed behavior)
log_info "Installing git hooks with lefthook..."
mise exec lefthook -- lefthook install --force
rm -f "$(git rev-parse --git-path hooks)/prepare-commit-msg"

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
  # Check if docs/ or backups/ is currently encrypted/locked by git-crypt
  # A locked git-crypt file starts with the binary \0GITCRYPT signature
  if ([ -f "docs/plans/archive/task-2026-10-13-legacy-consolidated-tracker.md" ] && head -c 10 "docs/plans/archive/task-2026-10-13-legacy-consolidated-tracker.md" 2>/dev/null | grep -q "GITCRYPT") ||
    ([ -f "backups/README.md" ] && head -c 10 "backups/README.md" 2>/dev/null | grep -q "GITCRYPT"); then
    log_warn "docs/ or backups/ is currently locked by git-crypt."
    if gpg --list-secret-keys 5EE1590FF82DC2A3829D224FAA73ACF495CC009D &>/dev/null; then
      log_info "Production GPG key found in keyring. Unlocking repository..."
      git-crypt unlock
      log_info "Successfully unlocked repository."
    else
      log_warn "Production GPG key 5EE1590FF82DC2A3829D224FAA73ACF495CC009D not found in keyring."
      log_warn "Import your production GPG key and run 'git-crypt unlock' to view and edit docs/ and backups/."
    fi
  else
    log_info "docs/ and backups/ are unlocked or not encrypted."
  fi
fi

# 3d. Ensure github/gh-stack CLI extension is installed for Stacked Pull Requests (STD-CI-73)
log_info "Checking GitHub CLI 'github/gh-stack' extension..."
if mise exec gh -- gh extension list 2>/dev/null | grep -Fq "github/gh-stack"; then
  log_info "GitHub CLI extension 'github/gh-stack' is already installed."
else
  log_info "Installing GitHub CLI extension 'github/gh-stack'..."
  if mise exec gh -- gh extension install github/gh-stack &>/dev/null; then
    log_info "Successfully installed 'github/gh-stack' extension."
  else
    log_warn "Could not install 'github/gh-stack' (ensure 'gh auth login' is configured, then run 'mise exec gh -- gh extension install github/gh-stack')."
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

log_info "Syncing Python dependencies from pyproject.toml and uv.lock..."
uv sync --frozen

log_info "Bootstrap complete!"
log_info "To enable mise in your shell, add this to your rc file (~/.zshrc, ~/.bashrc, etc.):"
echo -e "  ${YELLOW}eval \"\$(mise activate zsh)\"${NC}  # or bash, fish, etc."
log_info "To use the generated age key with SOPS, make sure this environment variable is set:"
echo -e "  ${YELLOW}export SOPS_AGE_KEY_FILE=\"$AGE_KEY_FILE\"${NC}"
log_info "OpenTofu state encryption: the passphrase lives only in production SOPS (no default, no local file)."
echo -e "  ${YELLOW}# First setup only: generate it straight into SOPS (nothing is printed or written to disk):${NC}"
echo -e "  ${YELLOW}openssl rand -hex 32 | jq -R . | mise exec -- sops set --value-stdin secrets/credentials.sops.yaml '[\"opentofu\"][\"state_encryption_passphrase\"]'${NC}"
echo -e "  ${YELLOW}# Before running tofu, export it from SOPS into TF_VAR_state_encryption_passphrase:${NC}"
echo -e "  ${YELLOW}export TF_VAR_state_encryption_passphrase=\"\$(mise exec -- sops -d --extract '[\"opentofu\"][\"state_encryption_passphrase\"]' secrets/credentials.sops.yaml)\"${NC}"
