using BinaryBuilder, Pkg

const YGGDRASIL_DIR = "../.."
include(joinpath(YGGDRASIL_DIR, "platforms", "macos_sdks.jl"))

name = "nlolib"
version = v"0.1.0"

sources = [
    GitSource("https://github.com/kinsky-main/nlo-rk4ip-code.git",
              "14054d9ea3a3d3be07f7f9e0af467020360df02f";
              tag="v$(version)"),
    # Header-only, and Yggdrasil builds VkFFT only for its CUDA, Metal and OpenCL backends.
    GitSource("https://github.com/DTolm/VkFFT.git",
              "066a17c17068c0f11c9298d848c2976c71fad1c1";
              tag="v1.3.4"),
]

script = raw"""
cd ${WORKSPACE}/srcdir/nlo-rk4ip-code
# nlolib needs CMake >= 3.22.1; drop the image's 3.21 so CMake_jll is used.
apk del cmake
cmake -B build -GNinja \
    -DCMAKE_INSTALL_PREFIX=${prefix} \
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF \
    -DNLOLIB_BUILD_DOCS=OFF \
    -DNLOLIB_BUILD_BENCHMARKS=OFF \
    -DNLOLIB_BUILD_EXAMPLES=OFF \
    -DNLOLIB_FFTW_PROVIDER=SYSTEM \
    -DNLOLIB_SQLITE_PROVIDER=SYSTEM \
    -DNLOLIB_GLSLANG_PROVIDER=SYSTEM \
    -DNLOLIB_STATIC_LIBSTDCXX=OFF \
    -DFETCHCONTENT_SOURCE_DIR_VKFFT=${WORKSPACE}/srcdir/VkFFT \
    -DGLSLANG_VALIDATOR=${host_bindir}/glslangValidator
cmake --build build --parallel ${nproc}
cmake --install build
install_license LICENSE
"""

# The glslang static libraries use std::filesystem, which needs macOS 10.15.
sources, script = require_macos_sdk("10.15", sources, script)

platforms = supported_platforms()
# Vulkan_Loader_jll has no build for these.
filter!(p -> arch(p) != "armv6l", platforms)
filter!(p -> arch(p) != "riscv64", platforms)
filter!(p -> !(Sys.isfreebsd(p) && arch(p) == "aarch64"), platforms)
# The 32-bit Windows import library of Vulkan_Loader_jll lacks the stdcall
# names (vkCreateBuffer@16), so linking against it fails.
filter!(p -> !(Sys.iswindows(p) && nbits(p) == 32), platforms)
# The glslang static libraries carry std::string in their symbols.
platforms = expand_cxxstring_abis(platforms)

products = [
    LibraryProduct(["libnlolib", "nlolib"], :libnlolib),
]

dependencies = [
    HostBuildDependency(PackageSpec(; name="CMake_jll", version="3.31.9")),
    # Compiles the compute shaders at build time.
    HostBuildDependency("glslang_jll"),
    # Static libraries, linked in for runtime GLSL compilation.
    BuildDependency("glslang_jll"),
    BuildDependency("Vulkan_Headers_jll"),
    # libstdc++ and libgcc_s, for the statically linked glslang.
    Dependency("CompilerSupportLibraries_jll"),
    Dependency("Vulkan_Loader_jll"; compat="1.3.243"),
    Dependency("FFTW_jll"; compat="3.3.10"),
    # nlolib needs SQLite >= 3.49.2. The SQLite_jll releases from 3.51.2 up to
    # 3.54.0 each have their own soname on Linux, so a library linked against
    # one loads with no other; 3.54.1 is back to libsqlite3.so.0.
    Dependency("SQLite_jll"; compat="3.54.1"),
]

# glslang_jll is built with GCC 9.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               julia_compat="1.6", preferred_gcc_version=v"9")
