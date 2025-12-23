#!/bin/bash
set -euo pipefail

# Ligero Prover Installer
# Install the Ligero prover for use with zigkvm-sdk
# Supports macOS (Intel/ARM) and Linux (x86_64/arm64)
# Builds native prover/verifier with WebGPU acceleration (no web support)

INSTALLER_VERSION="1.0.0"
DEFAULT_VERSION="v1.2.0"
GITHUB_REPO="https://github.com/ligeroinc/ligero-prover"
DAWN_REPO="https://dawn.googlesource.com/dawn"
WABT_REPO="https://github.com/WebAssembly/wabt.git"
DAWN_COMMIT="cec4482eccee45696a7c0019e750c77f101ced04"
WABT_VERSION="1.0.36"  # Stable version compatible with Ligero

# Configuration
LIGERO_HOME="${LIGERO_HOME:-${HOME}/.ligero}"
LIGERO_BIN="${LIGERO_HOME}/bin"
LIGERO_SRC="${LIGERO_HOME}/src"
LIGERO_TMP="${LIGERO_HOME}/tmp"
LIGERO_LOG="${LIGERO_HOME}/install.log"
VERSION="${LIGERO_VERSION:-${DEFAULT_VERSION}}"

# Build paths
DAWN_SRC="${LIGERO_SRC}/dawn"
DAWN_BUILD="${DAWN_SRC}/release"
WABT_SRC="${LIGERO_SRC}/wabt"
WABT_BUILD="${WABT_SRC}/build"
LIGERO_SRC_DIR="${LIGERO_SRC}/ligero-prover"
LIGERO_BUILD="${LIGERO_SRC_DIR}/build"

# Options
FORCE_INSTALL=0
NO_PATH_SETUP=0
DRY_RUN=0
DO_UNINSTALL=0

# Platform detection
OS=""
ARCH=""
PLATFORM=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Utility functions
info() {
    echo -e "${BLUE}→${NC} $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $*" >&2
}

error() {
    echo -e "${RED}✗${NC} $*" >&2
}

die() {
    error "$*"
    error "Installation failed."
    if [ -f "$LIGERO_LOG" ]; then
        error "See installation log for details: $LIGERO_LOG"
    fi
    show_troubleshooting
    exit 1
}

show_progress() {
    local step="$1"
    local total="$2"
    local message="$3"
    echo ""
    echo -e "${BOLD}[$step/$total]${NC} $message"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LIGERO_LOG"
}

# Platform detection
detect_platform() {
    local os_name=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch_name=$(uname -m)

    case "$os_name" in
        darwin)
            OS="macos"
            ;;
        linux)
            OS="linux"
            ;;
        *)
            die "Unsupported operating system: $os_name"
            ;;
    esac

    case "$arch_name" in
        x86_64)
            ARCH="x86_64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            die "Unsupported architecture: $arch_name"
            ;;
    esac

    PLATFORM="${OS}-${ARCH}"
    log "Detected platform: $PLATFORM"
}

# Dependency checking
check_command() {
    if command -v "$1" &>/dev/null; then
        success "$1 found"
        return 0
    else
        error "$1 not found"
        return 1
    fi
}

check_minimal_deps() {
    local missing=()

    for cmd in curl git; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        die "Missing required dependencies: ${missing[*]}"
    fi
}

check_macos_dependencies() {
    info "Checking macOS dependencies..."

    # Check for Homebrew
    if ! command -v brew &>/dev/null; then
        die "Homebrew not found. Install from: https://brew.sh"
    fi
    success "Homebrew found"

    local deps=("cmake" "gmp" "mpfr" "libomp" "llvm" "boost" "ninja")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! brew list "$dep" &>/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        info "Installing missing dependencies: ${missing[*]}"
        log "Installing Homebrew packages: ${missing[*]}"

        if [ "$DRY_RUN" = "1" ]; then
            info "[DRY RUN] Would install: brew install ${missing[*]}"
        else
            brew install "${missing[@]}" || die "Failed to install dependencies"
        fi
        success "Dependencies installed"
    else
        success "All dependencies already installed"
    fi
}

check_linux_dependencies() {
    info "Checking Linux dependencies..."

    # Detect package manager
    if ! command -v apt-get &>/dev/null; then
        die "apt-get not found. Only Debian/Ubuntu-based distributions are currently supported."
    fi

    # Check for sudo
    local sudo_cmd=""
    if [ "$EUID" -ne 0 ]; then
        if ! command -v sudo &>/dev/null; then
            die "sudo required for package installation"
        fi
        sudo_cmd="sudo"
    fi

    # Update package list
    info "Updating package list..."
    if [ "$DRY_RUN" = "0" ]; then
        $sudo_cmd apt-get update >> "$LIGERO_LOG" 2>&1 || die "Failed to update package list"
    fi

    # Core dependencies
    local deps=(
        "build-essential"
        "git"
        "cmake"
        "ninja-build"
        "libgmp-dev"
        "libtbb-dev"
        "libssl-dev"
        "libboost-all-dev"
        "libvulkan1"
        "vulkan-tools"
        "libvulkan-dev"
        "libx11-dev"
        "libxrandr-dev"
        "libxinerama-dev"
        "libxcursor-dev"
        "libxi-dev"
        "libx11-xcb-dev"
        "mesa-common-dev"
        "libgl1-mesa-dev"
    )

    info "Installing system dependencies..."
    log "Installing apt packages: ${deps[*]}"

    if [ "$DRY_RUN" = "1" ]; then
        info "[DRY RUN] Would install: ${deps[*]}"
    else
        $sudo_cmd apt-get install -y "${deps[@]}" >> "$LIGERO_LOG" 2>&1 || die "Failed to install dependencies"
    fi

    # Check and install g++-13
    if ! command -v g++-13 &>/dev/null; then
        info "Installing g++-13..."
        log "Setting up g++-13"

        if [ "$DRY_RUN" = "0" ]; then
            $sudo_cmd add-apt-repository -y ppa:ubuntu-toolchain-r/test >> "$LIGERO_LOG" 2>&1 || warn "Failed to add toolchain PPA"
            $sudo_cmd apt-get update >> "$LIGERO_LOG" 2>&1
            $sudo_cmd apt-get install -y g++-13 >> "$LIGERO_LOG" 2>&1 || die "Failed to install g++-13"
            $sudo_cmd update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-13 20 >> "$LIGERO_LOG" 2>&1
            $sudo_cmd update-alternatives --set g++ "/usr/bin/g++-13" >> "$LIGERO_LOG" 2>&1
            success "g++-13 installed and configured"
        fi
    else
        success "g++-13 already installed"
    fi

    # Verify CMake version (need 3.x+)
    local cmake_version=$(cmake --version 2>/dev/null | head -n1 | grep -oP '\d+\.\d+' || echo "0.0")
    local cmake_major=$(echo "$cmake_version" | cut -d. -f1)

    if [ "$cmake_major" -lt 3 ]; then
        warn "CMake version too old ($cmake_version), upgrading..."
        info "Installing latest CMake from Kitware..."

        if [ "$DRY_RUN" = "0" ]; then
            $sudo_cmd apt-get remove -y --purge cmake >> "$LIGERO_LOG" 2>&1 || true
            $sudo_cmd apt-get install -y software-properties-common lsb-release wget gpg >> "$LIGERO_LOG" 2>&1

            wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | \
                gpg --dearmor - | \
                $sudo_cmd tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null

            echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" | \
                $sudo_cmd tee /etc/apt/sources.list.d/kitware.list >/dev/null

            $sudo_cmd apt-get update >> "$LIGERO_LOG" 2>&1
            $sudo_cmd apt-get install -y cmake >> "$LIGERO_LOG" 2>&1 || die "Failed to install CMake"
            success "CMake upgraded"
        fi
    else
        success "CMake version OK ($cmake_version)"
    fi

    success "All Linux dependencies installed"
}

# Build Dawn (WebGPU)
build_dawn() {
    info "Building Dawn (WebGPU)..."
    info "This is required for GPU acceleration and will take 10-20 minutes"
    log "Starting Dawn build"

    if [ -d "$DAWN_SRC" ] && [ "$FORCE_INSTALL" = "0" ]; then
        success "Dawn already exists, skipping"
        log "Dawn build skipped (already exists)"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        info "[DRY RUN] Would build Dawn at: $DAWN_SRC"
        return 0
    fi

    # Clone Dawn
    info "Cloning Dawn repository..."
    if [ -d "$DAWN_SRC" ]; then
        rm -rf "$DAWN_SRC"
    fi

    mkdir -p "$LIGERO_SRC"

    if ! git clone "$DAWN_REPO" "$DAWN_SRC" >> "$LIGERO_LOG" 2>&1; then
        die "Failed to clone Dawn repository"
    fi

    cd "$DAWN_SRC" || die "Failed to enter Dawn directory"

    # Checkout specific commit
    info "Checking out Dawn commit ${DAWN_COMMIT:0:8}..."
    if ! git checkout "$DAWN_COMMIT" >> "$LIGERO_LOG" 2>&1; then
        die "Failed to checkout Dawn commit"
    fi

    # Build Dawn
    mkdir -p "$DAWN_BUILD"
    cd "$DAWN_BUILD" || die "Failed to enter Dawn build directory"

    info "Configuring Dawn with CMake (this takes a while)..."
    log "Running cmake for Dawn"

    if ! cmake -DDAWN_FETCH_DEPENDENCIES=ON \
               -DDAWN_BUILD_MONOLITHIC_LIBRARY=STATIC \
               -DDAWN_ENABLE_INSTALL=ON \
               -DCMAKE_BUILD_TYPE=Release \
               .. >> "$LIGERO_LOG" 2>&1; then
        die "Dawn CMake configuration failed"
    fi

    info "Building Dawn (10-20 minutes, be patient)..."
    local cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
    log "Building Dawn with $cores cores"

    if ! make -j"$cores" >> "$LIGERO_LOG" 2>&1; then
        die "Dawn build failed"
    fi

    info "Installing Dawn..."
    local sudo_cmd=""
    if [ "$EUID" -ne 0 ] && [ "$OS" = "linux" ]; then
        sudo_cmd="sudo"
    fi

    if ! $sudo_cmd make install >> "$LIGERO_LOG" 2>&1; then
        die "Dawn installation failed"
    fi

    success "Dawn built and installed successfully"
    log "Dawn build completed"
}

# Build wabt (WebAssembly Binary Toolkit)
build_wabt() {
    info "Building wabt (WebAssembly Binary Toolkit)..."
    log "Starting wabt build"

    if [ -d "$WABT_SRC" ] && [ "$FORCE_INSTALL" = "0" ]; then
        success "wabt already exists, skipping"
        log "wabt build skipped (already exists)"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        info "[DRY RUN] Would build wabt at: $WABT_SRC"
        return 0
    fi

    # Clone wabt
    info "Cloning wabt repository (version ${WABT_VERSION})..."
    if [ -d "$WABT_SRC" ]; then
        rm -rf "$WABT_SRC"
    fi

    if ! git clone --depth 1 --branch "$WABT_VERSION" "$WABT_REPO" "$WABT_SRC" >> "$LIGERO_LOG" 2>&1; then
        die "Failed to clone wabt repository"
    fi

    cd "$WABT_SRC" || die "Failed to enter wabt directory"

    # Update submodules
    info "Updating wabt submodules..."
    if ! git submodule update --init >> "$LIGERO_LOG" 2>&1; then
        die "Failed to update wabt submodules"
    fi

    # Build wabt
    mkdir -p "$WABT_BUILD"
    cd "$WABT_BUILD" || die "Failed to enter wabt build directory"

    info "Configuring wabt with CMake..."
    log "Running cmake for wabt"

    local cxx_compiler="g++"
    if [ "$OS" = "macos" ]; then
        cxx_compiler="clang++"
    elif command -v g++-13 &>/dev/null; then
        cxx_compiler="g++-13"
    fi

    if ! cmake -DCMAKE_CXX_COMPILER="$cxx_compiler" .. >> "$LIGERO_LOG" 2>&1; then
        die "wabt CMake configuration failed"
    fi

    info "Building wabt..."
    local cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
    log "Building wabt with $cores cores"

    if ! make -j"$cores" >> "$LIGERO_LOG" 2>&1; then
        die "wabt build failed"
    fi

    info "Installing wabt..."
    local sudo_cmd=""
    if [ "$EUID" -ne 0 ] && [ "$OS" = "linux" ]; then
        sudo_cmd="sudo"
    fi

    if ! $sudo_cmd make install >> "$LIGERO_LOG" 2>&1; then
        die "wabt installation failed"
    fi

    success "wabt built and installed successfully"
    log "wabt build completed"
}

# Build Ligero
clone_ligero() {
    local version="$1"

    info "Cloning Ligero prover repository (${version})..."
    log "Cloning from: $GITHUB_REPO"

    if [ -d "$LIGERO_SRC_DIR" ]; then
        warn "Source directory already exists, removing..."
        rm -rf "$LIGERO_SRC_DIR"
    fi

    mkdir -p "$LIGERO_SRC"

    if [ "$DRY_RUN" = "1" ]; then
        info "[DRY RUN] Would clone: $GITHUB_REPO"
        return 0
    fi

    if ! git clone --depth 1 --branch "$version" "$GITHUB_REPO" "$LIGERO_SRC_DIR" >> "$LIGERO_LOG" 2>&1; then
        die "Failed to clone repository (check that version $version exists)"
    fi

    success "Source code downloaded"
    log "Ligero cloned to: $LIGERO_SRC_DIR"
}

build_ligero() {
    info "Building Ligero prover from source..."
    info "This may take several minutes..."
    log "Starting Ligero build"

    if [ "$DRY_RUN" = "1" ]; then
        info "[DRY RUN] Would build in: $LIGERO_BUILD"
        return 0
    fi

    if [ ! -d "$LIGERO_SRC_DIR" ]; then
        die "Source directory not found: $LIGERO_SRC_DIR"
    fi

    cd "$LIGERO_SRC_DIR" || die "Failed to enter source directory"

    # Create build directory
    mkdir -p "$LIGERO_BUILD"
    cd "$LIGERO_BUILD" || die "Failed to enter build directory"

    # Configure with CMake
    info "Configuring Ligero with CMake..."
    log "Running cmake for Ligero"
    if ! cmake -DCMAKE_BUILD_TYPE=Release .. >> "$LIGERO_LOG" 2>&1; then
        die "CMake configuration failed"
    fi

    # Build with make
    info "Compiling Ligero (this will take a while)..."
    local cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
    log "Building with $cores cores"

    if ! make -j"$cores" >> "$LIGERO_LOG" 2>&1; then
        die "Build failed"
    fi

    success "Build completed successfully"
    log "Ligero build finished"
}

install_binaries() {
    info "Installing binaries to ${LIGERO_BIN}..."

    if [ "$DRY_RUN" = "1" ]; then
        info "[DRY RUN] Would install binaries to: $LIGERO_BIN"
        return 0
    fi

    mkdir -p "$LIGERO_BIN"

    local binaries=("webgpu_prover" "webgpu_verifier")
    for binary in "${binaries[@]}"; do
        local src="${LIGERO_BUILD}/${binary}"
        if [ -f "$src" ]; then
            cp "$src" "${LIGERO_BIN}/" || die "Failed to copy $binary"
            chmod 755 "${LIGERO_BIN}/${binary}"
            success "${binary} installed"
            log "Installed: $binary"
        else
            die "Binary not found: $src"
        fi
    done

    # Write version file
    echo "$VERSION" > "${LIGERO_HOME}/VERSION"
    log "Installation completed"
}

# Shell integration
setup_shell_integration() {
    if [ "$NO_PATH_SETUP" = "1" ]; then
        info "Skipping shell PATH configuration"
        return 0
    fi

    info "Configuring shell integration..."

    local shell_name=""
    local shell_rc=""

    # Detect shell
    case "$SHELL" in
        */bash)
            shell_rc="${HOME}/.bashrc"
            shell_name="bash"
            ;;
        */zsh)
            shell_rc="${HOME}/.zshrc"
            shell_name="zsh"
            ;;
        */fish)
            shell_rc="${HOME}/.config/fish/config.fish"
            shell_name="fish"
            ;;
        *)
            warn "Unknown shell: $SHELL"
            info "Add this to your shell configuration manually:"
            info "  export PATH=\"${LIGERO_BIN}:\$PATH\""
            log "Unknown shell, manual PATH setup required"
            return 0
            ;;
    esac

    # Check if already configured
    if [ -f "$shell_rc" ] && grep -q "${LIGERO_BIN}" "$shell_rc" 2>/dev/null; then
        warn "PATH already configured in $shell_rc"
        log "PATH already configured"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        info "[DRY RUN] Would update: $shell_rc"
        return 0
    fi

    # Add to shell config
    local config_line=""
    if [ "$shell_name" = "fish" ]; then
        config_line="set -gx PATH \"${LIGERO_BIN}\" \$PATH"
    else
        config_line="export PATH=\"${LIGERO_BIN}:\$PATH\""
    fi

    mkdir -p "$(dirname "$shell_rc")"
    {
        echo ""
        echo "# Ligero prover"
        echo "$config_line"
    } >> "$shell_rc"

    success "Updated $shell_rc"
    log "Shell configuration updated: $shell_rc"
}

# Verification
verify_installation() {
    info "Verifying installation..."

    if [ "$DRY_RUN" = "1" ]; then
        info "[DRY RUN] Would verify binaries in: $LIGERO_BIN"
        return 0
    fi

    local binaries=("webgpu_prover" "webgpu_verifier")

    for binary in "${binaries[@]}"; do
        if [ ! -x "${LIGERO_BIN}/${binary}" ]; then
            error "${binary} not found or not executable"
            return 1
        fi
    done

    success "Installation verified"
    log "Installation verification passed"
    return 0
}

# Uninstall
uninstall_ligero() {
    if [ ! -d "$LIGERO_HOME" ]; then
        info "Ligero not installed at $LIGERO_HOME"
        return 0
    fi

    warn "This will remove $LIGERO_HOME"
    echo -n "Continue? [y/N] "
    read -r response

    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        info "Uninstall cancelled"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        info "[DRY RUN] Would remove: $LIGERO_HOME"
    else
        rm -rf "$LIGERO_HOME"
        success "Ligero uninstalled"
    fi

    warn "Remember to remove PATH configuration from your shell config:"
    info "  ~/.bashrc, ~/.zshrc, or ~/.config/fish/config.fish"

    # Note about system-wide installations
    if [ "$OS" = "linux" ]; then
        warn "Dawn and wabt were installed system-wide and were not removed"
        info "To remove them, run:"
        info "  sudo rm -rf /usr/local/lib/libdawn* /usr/local/include/dawn"
        info "  sudo rm -rf /usr/local/bin/wasm* /usr/local/include/wabt"
    fi
}

# Troubleshooting
show_troubleshooting() {
    cat << 'EOF'

Troubleshooting:
  1. Check the installation log:
     cat ~/.ligero/install.log

  2. Build process overview:
     - Dawn (WebGPU) - 10-20 minutes
     - wabt (WebAssembly toolkit) - 2-5 minutes
     - Ligero prover - 5-10 minutes
     Total: ~30 minutes on a fast machine

  3. System requirements:
     - macOS: Homebrew, 8GB+ RAM, 5GB disk space
     - Linux: Ubuntu 22.04+, 8GB+ RAM, 5GB disk space

  4. Common issues:
     - Dawn build fails: Check you have enough disk space and RAM
     - CMake errors: Ensure CMake 3.x+ is installed
     - Permission denied: Use sudo for system package installation

  5. Manual installation:
     See: scripts/ligero/README.md

  6. Report issues:
     https://github.com/ligeroinc/ligero-prover/issues
     https://github.com/MatteoMer/zigkvm-sdk/issues

EOF
}

# Usage
usage() {
    cat << EOF
Ligero Prover Installer v${INSTALLER_VERSION}

Install the Ligero prover for zero-knowledge proof generation.
Builds: Dawn (WebGPU) + wabt + Ligero prover (native only, no web support)

Usage: $0 [OPTIONS]

Options:
  -v, --version VERSION    Install specific version (default: ${DEFAULT_VERSION})
  -h, --home DIR          Installation directory (default: ~/.ligero)
  -f, --force             Force reinstall even if already installed
  -u, --uninstall         Uninstall Ligero
  --no-path-setup         Skip shell PATH configuration
  --dry-run               Show what would be done without making changes
  --help                  Show this help message

Environment Variables:
  LIGERO_VERSION          Version to install
  LIGERO_HOME             Installation directory

Build time: ~30 minutes on modern hardware
Disk space: ~5GB

Examples:
  # Install latest version
  $0

  # Install specific version
  $0 --version v1.1.0

  # Install to custom location
  $0 --home /opt/ligero

  # Uninstall
  $0 --uninstall

Documentation: https://github.com/ligeroinc/ligero-prover
Report issues: https://github.com/MatteoMer/zigkvm-sdk/issues
EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -h|--home)
                LIGERO_HOME="$2"
                LIGERO_BIN="${LIGERO_HOME}/bin"
                LIGERO_SRC="${LIGERO_HOME}/src"
                LIGERO_TMP="${LIGERO_HOME}/tmp"
                LIGERO_LOG="${LIGERO_HOME}/install.log"
                # Update build paths
                DAWN_SRC="${LIGERO_SRC}/dawn"
                DAWN_BUILD="${DAWN_SRC}/release"
                WABT_SRC="${LIGERO_SRC}/wabt"
                WABT_BUILD="${WABT_SRC}/build"
                LIGERO_SRC_DIR="${LIGERO_SRC}/ligero-prover"
                LIGERO_BUILD="${LIGERO_SRC_DIR}/build"
                shift 2
                ;;
            -f|--force)
                FORCE_INSTALL=1
                shift
                ;;
            -u|--uninstall)
                DO_UNINSTALL=1
                shift
                ;;
            --no-path-setup)
                NO_PATH_SETUP=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main installation flow
main() {
    parse_args "$@"

    # Handle uninstall
    if [ "$DO_UNINSTALL" = "1" ]; then
        uninstall_ligero
        exit 0
    fi

    # Print header
    echo ""
    echo -e "${BOLD}Ligero Prover Installer v${INSTALLER_VERSION}${NC}"
    echo "=============================="
    echo ""
    warn "This will build Dawn, wabt, and Ligero from source"
    warn "Build time: ~30 minutes | Disk space: ~5GB"
    echo ""

    # Initialize log
    mkdir -p "$(dirname "$LIGERO_LOG")"
    log "Installation started (version: $VERSION)"

    if [ "$DRY_RUN" = "1" ]; then
        warn "DRY RUN MODE - no changes will be made"
        echo ""
    fi

    # Detect platform
    detect_platform
    info "Detected platform: ${PLATFORM}"
    info "Target version: ${VERSION}"

    # Check if already installed
    if [ -f "${LIGERO_HOME}/VERSION" ] && [ "$FORCE_INSTALL" = "0" ]; then
        local installed_version=$(cat "${LIGERO_HOME}/VERSION")
        if [ "$installed_version" = "$VERSION" ]; then
            success "Ligero ${VERSION} is already installed"
            info "Use --force to reinstall"
            exit 0
        else
            info "Upgrading from ${installed_version} to ${VERSION}"
        fi
    fi

    # Installation steps
    local total_steps=9

    # Step 1: Check prerequisites
    show_progress 1 $total_steps "Checking prerequisites..."
    check_minimal_deps
    check_command curl
    check_command git

    # Step 2: Install system dependencies
    show_progress 2 $total_steps "Installing system dependencies..."
    if [ "$OS" = "macos" ]; then
        check_macos_dependencies
    elif [ "$OS" = "linux" ]; then
        check_linux_dependencies
    fi

    # Step 3: Build Dawn (WebGPU)
    show_progress 3 $total_steps "Building Dawn (WebGPU) - this takes 10-20 minutes..."
    build_dawn

    # Step 4: Build wabt
    show_progress 4 $total_steps "Building wabt (WebAssembly toolkit)..."
    build_wabt

    # Step 5: Download Ligero source
    show_progress 5 $total_steps "Downloading Ligero source code..."
    clone_ligero "$VERSION"

    # Step 6: Build Ligero
    show_progress 6 $total_steps "Building Ligero prover..."
    build_ligero

    # Step 7: Install binaries
    show_progress 7 $total_steps "Installing binaries..."
    install_binaries

    # Step 8: Shell integration
    show_progress 8 $total_steps "Configuring shell integration..."
    setup_shell_integration

    # Step 9: Verify
    show_progress 9 $total_steps "Verifying installation..."
    verify_installation

    # Success message
    echo ""
    success "Installation complete!"
    echo ""
    info "To start using Ligero prover, run:"
    if [ "$NO_PATH_SETUP" = "0" ]; then
        case "$SHELL" in
            */bash)
                info "  source ~/.bashrc"
                ;;
            */zsh)
                info "  source ~/.zshrc"
                ;;
            */fish)
                info "  source ~/.config/fish/config.fish"
                ;;
            *)
                info "  export PATH=\"${LIGERO_BIN}:\$PATH\""
                ;;
        esac
        info "  # or restart your terminal"
    fi
    echo ""
    info "Verify installation:"
    info "  webgpu_prover --version"
    echo ""
    info "Documentation: ${GITHUB_REPO}"
    echo ""

    log "Installation completed successfully"
}

main "$@"
