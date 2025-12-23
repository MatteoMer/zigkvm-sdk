# Ligero Prover Installer

This directory contains installation scripts for the [Ligero prover](https://github.com/ligeroinc/ligero-prover), which enables true zero-knowledge proofs for the zigkvm-sdk.

Disclaimer: I've only used this script on my macbook M1 pro, have not tried the linux. Feel free to open issues if it's broken

## Quick Start

### One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/MatteoMer/zigkvm-sdk/main/scripts/ligero/install-ligero.sh | bash
```

After installation, restart your terminal or run:

```bash
source ~/.zshrc  # or ~/.bashrc for bash users
```

## Supported Platforms

| Platform | Architecture | Status |
|----------|-------------|--------|
| macOS | Intel (x86_64) | ✅ Supported |
| macOS | Apple Silicon (arm64) | ✅ Supported |
| Linux | x86_64 | ✅ Supported |
| Linux | arm64 | ✅ Supported |

**Requirements:**
- **macOS**: Homebrew must be installed
- **Linux**: Ubuntu 22.04+ or Debian-based distribution with `apt-get`

## Installation Options

### Basic Installation

Install the default version (v1.2.0):

```bash
bash scripts/ligero/install-ligero.sh
```

### Custom Version

Install a specific version:

```bash
bash scripts/ligero/install-ligero.sh --version v1.1.0
```

Or use an environment variable:

```bash
LIGERO_VERSION=v1.1.0 bash scripts/ligero/install-ligero.sh
```

### Custom Installation Directory

Install to a custom location:

```bash
bash scripts/ligero/install-ligero.sh --home /opt/ligero
```

Or use an environment variable:

```bash
LIGERO_HOME=/opt/ligero bash scripts/ligero/install-ligero.sh
```

### Force Reinstall

Force reinstallation even if already installed:

```bash
bash scripts/ligero/install-ligero.sh --force
```

### Skip PATH Configuration

Install without modifying shell configuration:

```bash
bash scripts/ligero/install-ligero.sh --no-path-setup
```

Then manually add to your shell config:

```bash
export PATH="$HOME/.ligero/bin:$PATH"
```

### Dry Run

See what would be done without making changes:

```bash
bash scripts/ligero/install-ligero.sh --dry-run
```

## Installation Process

The installer builds Ligero and its dependencies from source. This takes **~30 minutes** on modern hardware.

**Build Steps:**

1. **Platform Detection** - Detects your OS and architecture
2. **Prerequisite Check** - Verifies curl, git, and cmake are available
3. **System Dependencies** - Installs required packages via Homebrew (macOS) or apt (Linux)
4. **Build Dawn (WebGPU)** - *10-20 minutes*
   - Required for GPU acceleration
   - Builds Google's Dawn WebGPU implementation
   - Installs system-wide to `/usr/local/`
5. **Build wabt** - *2-5 minutes*
   - WebAssembly Binary Toolkit
   - Required dependency for Ligero
   - Installs system-wide to `/usr/local/`
6. **Build Ligero Prover** - *5-10 minutes*
   - Clones ligero-prover repository
   - Builds native prover/verifier (no web support)
   - Installs binaries to `~/.ligero/bin`
7. **Shell Integration** - Adds `~/.ligero/bin` to your PATH
8. **Verification** - Tests that binaries are executable

**System Requirements:**
- **CPU**: Multi-core processor (build uses all cores)
- **RAM**: 8GB+ recommended (Dawn build is memory-intensive)
- **Disk**: 5GB free space
- **Time**: ~30 minutes on modern hardware

## Installation Directory Structure

```
~/.ligero/
├── bin/                    # Ligero binaries
│   ├── webgpu_prover
│   └── webgpu_verifier
├── src/                    # Source code
│   ├── dawn/               # Dawn (WebGPU) source
│   ├── wabt/               # wabt source
│   └── ligero-prover/      # Ligero source
├── tmp/                    # Temporary downloads
├── VERSION                 # Installed version
└── install.log            # Installation log

/usr/local/                 # System-wide installations (Linux)
├── lib/libdawn*            # Dawn libraries
├── include/dawn/           # Dawn headers
├── bin/wasm*               # wabt tools
└── include/wabt/           # wabt headers
```

## Dependencies

### macOS Dependencies

The installer automatically installs these via Homebrew:

- cmake
- gmp
- mpfr
- libomp
- llvm
- boost
- ninja

**Manual installation:**

```bash
brew install cmake gmp mpfr libomp llvm boost ninja
```

### Linux Dependencies

The installer automatically installs these via apt:

**Core packages:**
- build-essential
- git
- cmake
- ninja-build

**Libraries:**
- libgmp-dev
- libtbb-dev
- libssl-dev
- libboost-all-dev

**GPU/Graphics (required for Dawn/WebGPU):**
- libvulkan1, vulkan-tools, libvulkan-dev
- libx11-dev, libxrandr-dev, libxinerama-dev, libxcursor-dev, libxi-dev, libx11-xcb-dev
- mesa-common-dev, libgl1-mesa-dev

**Compiler:**
- g++-13 (automatically configured as default g++)

**Manual installation:**

```bash
sudo apt-get update
sudo apt-get install build-essential git cmake ninja-build \
    libgmp-dev libtbb-dev libssl-dev libboost-all-dev \
    libvulkan1 vulkan-tools libvulkan-dev \
    libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev libx11-xcb-dev \
    mesa-common-dev libgl1-mesa-dev

# Install g++-13
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt update
sudo apt install g++-13
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-13 20
sudo update-alternatives --set g++ "/usr/bin/g++-13"
```

## Troubleshooting

### Installation Log

Check the installation log for detailed error messages:

```bash
cat ~/.ligero/install.log
```

### Common Issues

#### Homebrew Not Found (macOS)

Install Homebrew first:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### Permission Denied

On Linux, you may need sudo for package installation. The installer will use sudo automatically if available.

#### Build Failed

If the build fails:

1. Check that all dependencies are installed
2. Review the installation log: `cat ~/.ligero/install.log`
3. Ensure you have enough RAM (8GB+) and disk space (5GB+)
4. Dawn build is the most demanding - if it fails, you may need to close other applications
5. Try building manually (see Manual Installation below)
6. Report the issue with the log contents

**Common build failures:**
- **Dawn build timeout**: Close other applications, Dawn needs significant memory
- **Linker errors**: Ensure you have g++-13 on Linux
- **CMake version errors**: Upgrade CMake to 3.x+ (installer does this automatically)

#### Version Not Found

If the specified version doesn't exist:

```bash
# List available versions
git ls-remote --tags https://github.com/ligeroinc/ligero-prover
```

#### PATH Not Updated

If the PATH wasn't updated automatically, add manually:

**For bash (~/.bashrc):**

```bash
echo 'export PATH="$HOME/.ligero/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**For zsh (~/.zshrc):**

```bash
echo 'export PATH="$HOME/.ligero/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**For fish (~/.config/fish/config.fish):**

```bash
echo 'set -gx PATH "$HOME/.ligero/bin" $PATH' >> ~/.config/fish/config.fish
source ~/.config/fish/config.fish
```

## Manual Installation

If the installer doesn't work for your system, follow these steps:

### 1. Install System Dependencies

**macOS:**
```bash
brew install cmake gmp mpfr libomp llvm boost ninja
```

**Linux:**
```bash
sudo apt-get update
sudo apt-get install build-essential git cmake ninja-build \
    libgmp-dev libtbb-dev libssl-dev libboost-all-dev \
    libvulkan1 vulkan-tools libvulkan-dev \
    libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev libx11-xcb-dev \
    mesa-common-dev libgl1-mesa-dev

# Install and configure g++-13
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt update
sudo apt install g++-13
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-13 20
sudo update-alternatives --set g++ "/usr/bin/g++-13"
```

### 2. Build Dawn (WebGPU)

```bash
git clone https://dawn.googlesource.com/dawn
cd dawn
git checkout cec4482eccee45696a7c0019e750c77f101ced04
mkdir release && cd release
cmake -DDAWN_FETCH_DEPENDENCIES=ON \
      -DDAWN_BUILD_MONOLITHIC_LIBRARY=STATIC \
      -DDAWN_ENABLE_INSTALL=ON \
      -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
sudo make install  # Linux only; omit sudo on macOS
cd ../..
```

### 3. Build wabt

```bash
git clone https://github.com/WebAssembly/wabt.git
cd wabt
git submodule update --init
mkdir build && cd build

# macOS:
cmake -DCMAKE_CXX_COMPILER=clang++ ..

# Linux:
cmake -DCMAKE_CXX_COMPILER=g++-13 ..

make -j$(nproc)
sudo make install  # Linux only; omit sudo on macOS
cd ../..
```

### 4. Build Ligero

```bash
git clone --depth 1 --branch v1.2.0 https://github.com/ligeroinc/ligero-prover
cd ligero-prover
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
```

### 5. Install Binaries

```bash
mkdir -p ~/.ligero/bin
cp webgpu_prover webgpu_verifier ~/.ligero/bin/
chmod +x ~/.ligero/bin/webgpu_prover ~/.ligero/bin/webgpu_verifier
```

### 6. Update PATH

Add to your shell configuration (~/.bashrc, ~/.zshrc, etc.):

```bash
export PATH="$HOME/.ligero/bin:$PATH"
```

## Uninstallation

### Using the Installer

```bash
bash scripts/ligero/install-ligero.sh --uninstall
```

### Manual Uninstallation

```bash
# Remove Ligero installation
rm -rf ~/.ligero

# Remove PATH configuration from shell config
# Edit ~/.bashrc, ~/.zshrc, or ~/.config/fish/config.fish
# Remove the lines containing "ligero"

# Remove system-wide dependencies (Linux only, optional)
sudo rm -rf /usr/local/lib/libdawn* /usr/local/include/dawn
sudo rm -rf /usr/local/bin/wasm* /usr/local/include/wabt
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LIGERO_VERSION` | Version to install | `v1.2.0` |
| `LIGERO_HOME` | Installation directory | `~/.ligero` |

**Example:**

```bash
LIGERO_VERSION=v1.1.0 LIGERO_HOME=/opt/ligero bash scripts/ligero/install-ligero.sh
```

## Using with zigkvm-sdk

After installing Ligero, you can use it with zigkvm-sdk:

```bash
# Build your zkVM program
zig build -Dbackend=ligero

# Generate proof
zig build -Dbackend=ligero prove

# Verify proof
zig build -Dbackend=ligero verify
```

## Support

- **Ligero Issues**: https://github.com/ligeroinc/ligero-prover/issues
- **zigkvm-sdk Issues**: https://github.com/MatteoMer/zigkvm-sdk/issues
