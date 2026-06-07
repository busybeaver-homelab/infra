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
if ! command -v mise &> /dev/null; then
    log_info "Mise is not installed. Installing Mise..."
    if [ "$OS" = "Darwin" ] && command -v brew &> /dev/null; then
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

# 4. Generate initial age key for SOPS
AGE_KEY_DIR="$HOME/.config/sops/age"
AGE_KEY_FILE="$AGE_KEY_DIR/keys.txt"

if [ ! -f "$AGE_KEY_FILE" ]; then
    log_info "No age key found at $AGE_KEY_FILE. Generating a new key pair..."
    mkdir -p "$AGE_KEY_DIR"
    
    # We use mise exec to run age-keygen in case age isn't in global shell yet
    if mise exec age -- age-keygen -o "$AGE_KEY_FILE" &> /dev/null; then
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
if ! command -v uv &> /dev/null; then
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

log_info "Bootstrap complete!"
log_info "To enable mise in your shell, add this to your rc file (~/.zshrc, ~/.bashrc, etc.):"
echo -e "  ${YELLOW}eval \"\$(mise activate zsh)\"${NC}  # or bash, fish, etc."
log_info "To use the generated age key with SOPS, make sure this environment variable is set:"
echo -e "  ${YELLOW}export SOPS_AGE_KEY_FILE=\"$AGE_KEY_FILE\"${NC}"
