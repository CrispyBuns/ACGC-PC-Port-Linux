#!/usr/bin/env bash

# Build configuration
BUILD_DIR="build"
GENERATOR="Ninja"
BUILD_TYPE="Release"
CMAKE_FLAGS=""
TOTAL_CORES=$(nproc)
NUM_JOBS=$TOTAL_CORES

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Ask user for number of CPU cores to use
ask_cpu_cores() {
    echo ""
    echo -e "${BLUE}CPU cores available: $TOTAL_CORES${NC}"
    read -p "How many cores do you want to use? (default: $TOTAL_CORES): " -r cores_input
    echo ""
    
    # If empty, use all cores
    if [ -z "$cores_input" ]; then
        NUM_JOBS=$TOTAL_CORES
        echo -e "${GREEN}Using all $TOTAL_CORES cores${NC}"
    # Validate input is a number
    elif ! [[ "$cores_input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid input. Using all $TOTAL_CORES cores${NC}"
        NUM_JOBS=$TOTAL_CORES
    # Check if input is within valid range
    elif [ "$cores_input" -gt "$TOTAL_CORES" ]; then
        echo -e "${YELLOW}Input exceeds available cores. Using all $TOTAL_CORES cores${NC}"
        NUM_JOBS=$TOTAL_CORES
    elif [ "$cores_input" -lt 1 ]; then
        echo -e "${YELLOW}Must use at least 1 core. Using 1 core${NC}"
        NUM_JOBS=1
    else
        NUM_JOBS=$cores_input
        echo -e "${GREEN}Using $NUM_JOBS cores${NC}"
    fi
    echo ""
}

# Ask user to choose OpenGL or OpenGL ES
choose_opengl() {
    local distro=$1
    
    echo -e "${BLUE}Choose OpenGL implementation:${NC}"
    echo "1) OpenGL ES (for mobile/embedded)"
    echo "2) OpenGL (standard desktop)"
    read -p "Enter choice (1 or 2): " -n 1 -r opengl_choice
    echo ""
    
    if [ "$opengl_choice" = "1" ]; then
        CMAKE_FLAGS="$CMAKE_FLAGS -DPC_USE_GLES=ON"
        check_and_install_gles "$distro"
    elif [ "$opengl_choice" = "2" ]; then
        CMAKE_FLAGS="$CMAKE_FLAGS -DPC_USE_GLES=OFF"
        check_and_install_opengl "$distro"
    else
        echo -e "${RED}Invalid choice${NC}"
        choose_opengl "$distro"
    fi
}

# Check and install OpenGL ES if needed
check_and_install_gles() {
    local distro=$1
    echo ""
    echo -e "${BLUE}Checking OpenGL ES development libraries...${NC}"
    
    # Try to detect OpenGL ES headers
    if [ -f /usr/include/GLES2/gl2.h ] || [ -f /usr/include/GLES3/gl3.h ]; then
        echo -e "${GREEN}✓${NC} OpenGL ES development libraries found"
        return 0
    fi
    
    echo -e "${YELLOW}OpenGL ES development libraries not found${NC}"
    read -p "Install OpenGL ES dev libraries? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_opengl_es "$distro"
    fi
}

# Check and install OpenGL if needed
check_and_install_opengl() {
    local distro=$1
    echo ""
    echo -e "${BLUE}Checking OpenGL development libraries...${NC}"
    
    # Try to detect OpenGL headers
    if [ -f /usr/include/GL/gl.h ]; then
        echo -e "${GREEN}✓${NC} OpenGL development libraries found"
        return 0
    fi
    
    echo -e "${YELLOW}OpenGL development libraries not found${NC}"
    read -p "Install OpenGL dev libraries? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_opengl "$distro"
    fi
}

# Install OpenGL ES
install_opengl_es() {
    local distro=$1
    echo -e "${BLUE}Installing OpenGL ES development libraries...${NC}"
    
    case "$distro" in
        ubuntu|debian)
            sudo apt update && sudo apt install -y libegl1-mesa-dev libgles2-mesa-dev
            ;;
        arch)
            sudo pacman -S mesa
            ;;
        fedora|rhel|centos)
            sudo dnf install -y mesa-libEGL-devel mesa-libGLES-devel
            ;;
        opensuse*)
            sudo zypper install Mesa-libEGL-devel Mesa-libGLES-devel
            ;;
        *)
            echo -e "${RED}Unknown distro: $distro${NC}"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}OpenGL ES libraries installed successfully!${NC}"
    else
        echo -e "${RED}Failed to install OpenGL ES libraries${NC}"
        return 1
    fi
}

# Install OpenGL
install_opengl() {
    local distro=$1
    echo -e "${BLUE}Installing OpenGL development libraries...${NC}"
    
    case "$distro" in
        ubuntu|debian)
            sudo apt update && sudo apt install -y libgl1-mesa-dev libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev
            ;;
        arch)
            sudo pacman -S mesa xorg-server-devel
            ;;
        fedora|rhel|centos)
            sudo dnf install -y mesa-libGL-devel libX11-devel libXrandr-devel libXinerama-devel libXcursor-devel
            ;;
        opensuse*)
            sudo zypper install Mesa-devel xorg-x11-devel
            ;;
        *)
            echo -e "${RED}Unknown distro: $distro${NC}"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}OpenGL libraries installed successfully!${NC}"
    else
        echo -e "${RED}Failed to install OpenGL libraries${NC}"
        return 1
    fi
}

# Check for development package
check_pkg() {
    case "$1" in
        ubuntu|debian)
            dpkg -l | grep -q "$2"
            ;;
        arch)
            pacman -Q "$2" &> /dev/null
            ;;
        fedora|rhel|centos)
            rpm -q "$2" &> /dev/null
            ;;
        opensuse*)
            rpm -q "$2" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Check dependencies
check_dependencies() {
    local distro=$(detect_distro)
    local missing=()
    
    echo -e "${BLUE}Checking dependencies...${NC}"
    
    # Check cmake
    if ! command_exists cmake; then
        missing+=("cmake")
        echo -e "${RED}✗${NC} cmake not found"
    else
        echo -e "${GREEN}✓${NC} cmake"
    fi
    
    # Check gcc
    if ! command_exists gcc; then
        missing+=("gcc")
        echo -e "${RED}✗${NC} gcc not found"
    else
        echo -e "${GREEN}✓${NC} gcc"
    fi
    
    # Check ninja
    if ! command_exists ninja; then
        missing+=("ninja")
        echo -e "${RED}✗${NC} ninja not found"
    else
        echo -e "${GREEN}✓${NC} ninja"
    fi
    
    # Check ccache
    if ! command_exists ccache; then
        missing+=("ccache")
        echo -e "${RED}✗${NC} ccache not found"
    else
        echo -e "${GREEN}✓${NC} ccache"
    fi
    
    # Check SDL2
    if ! command_exists sdl2-config; then
        missing+=("sdl2")
        echo -e "${RED}✗${NC} SDL2 development libraries not found"
    else
        echo -e "${GREEN}✓${NC} SDL2"
    fi
    
    # If there are missing dependencies
    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Missing dependencies: ${missing[*]}${NC}"
        echo ""
        read -p "Would you like to install missing dependencies? (y/n) " -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_dependencies "$distro" "${missing[@]}"
        fi
    else
        echo -e "${GREEN}All dependencies found!${NC}"
    fi
    echo ""
    
    # Ask for OpenGL choice
    choose_opengl "$distro"
    
    # Ask for CPU cores
    ask_cpu_cores
}

# Install dependencies based on distro
install_dependencies() {
    local distro=$1
    shift
    local packages=("$@")
    
    echo -e "${BLUE}Installing dependencies for $distro...${NC}"
    
    case "$distro" in
        ubuntu|debian)
            echo "Running: sudo apt update && sudo apt install -y ..."
            local apt_packages=""
            for pkg in "${packages[@]}"; do
                case "$pkg" in
                    cmake) apt_packages="$apt_packages cmake" ;;
                    gcc) apt_packages="$apt_packages build-essential" ;;
                    ninja) apt_packages="$apt_packages ninja-build" ;;
                    ccache) apt_packages="$apt_packages ccache" ;;
                    sdl2) apt_packages="$apt_packages libsdl2-dev" ;;
                esac
            done
            sudo apt update && sudo apt install -y $apt_packages
            ;;
        arch)
            echo "Running: sudo pacman -S ..."
            local pacman_packages=""
            for pkg in "${packages[@]}"; do
                case "$pkg" in
                    cmake) pacman_packages="$pacman_packages cmake" ;;
                    gcc) pacman_packages="$pacman_packages base-devel" ;;
                    ninja) pacman_packages="$pacman_packages ninja" ;;
                    ccache) pacman_packages="$pacman_packages ccache" ;;
                    sdl2) pacman_packages="$pacman_packages sdl2" ;;
                esac
            done
            sudo pacman -S $pacman_packages
            ;;
        fedora|rhel|centos)
            echo "Running: sudo dnf install ..."
            local dnf_packages=""
            for pkg in "${packages[@]}"; do
                case "$pkg" in
                    cmake) dnf_packages="$dnf_packages cmake" ;;
                    gcc) dnf_packages="$dnf_packages gcc gcc-c++" ;;
                    ninja) dnf_packages="$dnf_packages ninja-build" ;;
                    ccache) dnf_packages="$dnf_packages ccache" ;;
                    sdl2) dnf_packages="$dnf_packages SDL2-devel" ;;
                esac
            done
            sudo dnf install -y $dnf_packages
            ;;
        opensuse*)
            echo "Running: sudo zypper install ..."
            local zypper_packages=""
            for pkg in "${packages[@]}"; do
                case "$pkg" in
                    cmake) zypper_packages="$zypper_packages cmake" ;;
                    gcc) zypper_packages="$zypper_packages gcc gcc-c++" ;;
                    ninja) zypper_packages="$zypper_packages ninja" ;;
                    ccache) zypper_packages="$zypper_packages ccache" ;;
                    sdl2) zypper_packages="$zypper_packages SDL2-devel" ;;
                esac
            done
            sudo zypper install $zypper_packages
            ;;
        *)
            echo -e "${RED}Unknown distro: $distro${NC}"
            echo "Please install the following packages manually: ${packages[*]}"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Dependencies installed successfully!${NC}"
    else
        echo -e "${RED}Failed to install dependencies${NC}"
        return 1
    fi
}

# Main
check_dependencies

# Build
mkdir $BUILD_DIR && cd $BUILD_DIR && cmake -G"$GENERATOR" -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_C_COMPILER_LAUNCHER=ccache $CMAKE_FLAGS .. && cmake --build . --config $BUILD_TYPE -j $NUM_JOBS
