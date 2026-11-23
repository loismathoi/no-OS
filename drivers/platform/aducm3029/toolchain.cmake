# ADuCM3029 (aducm) platform toolchain
#
# Compiler and OpenOCD come from PATH. The DFP and CMSIS come from a CMSIS pack
# root. Device sources and linker script are in aducm3029_platform_sdk.cmake.

message(STATUS "ADuCM3029 Platform")

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)

# For bare-metal toolchains, only compile (not link) during CMake's compiler
# test. Linking needs the project's linker script, which does not exist yet.
set(CMAKE_TRY_COMPILE_TARGET_TYPE "STATIC_LIBRARY")

# ---------------------------------------------------------------------------
# Locate CMSIS packs (ADuCM302x DFP + ARM CMSIS)
# ---------------------------------------------------------------------------
if(NOT ADUCM_PACK_ROOT)
    if(DEFINED ENV{CMSIS_PACK_ROOT})
        set(ADUCM_PACK_ROOT "$ENV{CMSIS_PACK_ROOT}")
    else()
        set(ADUCM_PACK_ROOT "$ENV{HOME}/.cache/arm/packs")
    endif()
endif()
set(ADUCM_PACK_ROOT "${ADUCM_PACK_ROOT}" CACHE PATH "CMSIS pack root" FORCE)

file(GLOB _aducm_dfp "${ADUCM_PACK_ROOT}/AnalogDevices/ADuCM302x_DFP/*")
if(_aducm_dfp)
    list(SORT _aducm_dfp)
    list(GET _aducm_dfp -1 ADUCM_DFP)
endif()
file(GLOB _cmsis_core "${ADUCM_PACK_ROOT}/ARM/CMSIS/*/CMSIS/Core")
if(_cmsis_core)
    list(SORT _cmsis_core)
    list(GET _cmsis_core -1 ADUCM_CMSIS_CORE)
endif()

if(NOT ADUCM_DFP OR NOT EXISTS "${ADUCM_DFP}")
    message(FATAL_ERROR "ADuCM302x DFP not found under ${ADUCM_PACK_ROOT}/AnalogDevices/ADuCM302x_DFP.")
endif()
if(NOT ADUCM_CMSIS_CORE OR NOT EXISTS "${ADUCM_CMSIS_CORE}")
    message(FATAL_ERROR "CMSIS Core not found under ${ADUCM_PACK_ROOT}/ARM/CMSIS.")
endif()

# Cached for the platform SDK module and CMakeLists.
set(ADUCM_DFP "${ADUCM_DFP}" CACHE PATH "ADuCM302x Device Family Pack" FORCE)
set(ADUCM_CMSIS_CORE "${ADUCM_CMSIS_CORE}" CACHE PATH "CMSIS Core pack" FORCE)
message(STATUS "ADuCM DFP: ${ADUCM_DFP}")
message(STATUS "CMSIS Core: ${ADUCM_CMSIS_CORE}")

# ---------------------------------------------------------------------------
# Compiler selection
# ---------------------------------------------------------------------------
find_program(CMAKE_C_COMPILER   arm-none-eabi-gcc)
find_program(CMAKE_CXX_COMPILER arm-none-eabi-g++)
find_program(CMAKE_ASM_COMPILER arm-none-eabi-gcc)
find_program(CMAKE_LINKER       arm-none-eabi-ld)
find_program(CMAKE_SIZE         arm-none-eabi-size)
find_program(CMAKE_OBJCOPY      arm-none-eabi-objcopy)
find_program(CMAKE_AR           arm-none-eabi-ar)

if(NOT CMAKE_C_COMPILER)
    message(FATAL_ERROR "arm-none-eabi-gcc not found on PATH.")
endif()

set(CMAKE_EXECUTABLE_SUFFIX_ASM ".elf")
set(CMAKE_EXECUTABLE_SUFFIX_C ".elf")
set(CMAKE_EXECUTABLE_SUFFIX_CXX ".elf")

# ---------------------------------------------------------------------------
# Compiler / linker flags
# ---------------------------------------------------------------------------
set(COMMON_CPU_FLAGS "-mcpu=cortex-m3 -mthumb")

# Definitions required by the ADuCM3029 RTE / DFP headers.
set(ADUCM_DEFS "-DCORE0 -D_RTE_ -D__ADUCM3029__ -D__SILICON_REVISION__=0xffff")

set(CMAKE_C_FLAGS "${COMMON_CPU_FLAGS} ${ADUCM_DEFS} -ffunction-sections -fdata-sections -MD" CACHE STRING "C compiler flags" FORCE)
set(CMAKE_CXX_FLAGS "${COMMON_CPU_FLAGS} ${ADUCM_DEFS} -ffunction-sections -fdata-sections -MD" CACHE STRING "C++ compiler flags" FORCE)
# ADI_DISABLE_INSTRUCTION_SRAM selects the DFP's strong Reset_Handler in
# reset_ADuCM3029.S, which clears PMG_TST_SRAM_CTL.INSTREN before any data
# access. That remaps the 32 KiB of instruction SRAM (unused - code runs from
# flash) as data SRAM, doubling DSRAM_A/DSRAM_B to 32 KiB each (SRAM MODE2).
# The linker regions are widened to match (see aducm3029_platform_sdk.cmake).
# Requires the code cache to stay disabled (default); see system_ADuCM3029.c.
set(CMAKE_ASM_FLAGS "${COMMON_CPU_FLAGS} ${ADUCM_DEFS} -DADI_DISABLE_INSTRUCTION_SRAM -x assembler-with-cpp" CACHE STRING "ASM compiler flags" FORCE)

# Debug build flags - Full debug info, no optimization.
# Use GCC's default DWARF version (4 for this toolchain) rather than forcing
# -gdwarf-2: the older format lacks the location lists cortex-debug/GDB need to
# render source and locals, which broke source-level debugging on this platform.
set(CMAKE_C_FLAGS_DEBUG "-g -O0 -D_DEBUG" CACHE STRING "C compiler flags for Debug" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG "-g -O0 -D_DEBUG" CACHE STRING "C++ compiler flags for Debug" FORCE)
set(CMAKE_ASM_FLAGS_DEBUG "-g -D_DEBUG" CACHE STRING "ASM compiler flags for Debug" FORCE)

# Release build flags - Optimize for speed, disable assertions
set(CMAKE_C_FLAGS_RELEASE "-O2 -DNDEBUG" CACHE STRING "C compiler flags for Release" FORCE)
set(CMAKE_CXX_FLAGS_RELEASE "-O2 -DNDEBUG" CACHE STRING "C++ compiler flags for Release" FORCE)
set(CMAKE_ASM_FLAGS_RELEASE "-DNDEBUG" CACHE STRING "ASM compiler flags for Release" FORCE)

# RelWithDebInfo build flags - Optimize with debug info
set(CMAKE_C_FLAGS_RELWITHDEBINFO "-O2 -g -DNDEBUG" CACHE STRING "C compiler flags for RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO "-O2 -g -DNDEBUG" CACHE STRING "C++ compiler flags for RelWithDebInfo" FORCE)
set(CMAKE_ASM_FLAGS_RELWITHDEBINFO "-g -DNDEBUG" CACHE STRING "ASM compiler flags for RelWithDebInfo" FORCE)

# MinSizeRel build flags - Optimize for size
set(CMAKE_C_FLAGS_MINSIZEREL "-Os -DNDEBUG" CACHE STRING "C compiler flags for MinSizeRel" FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL "-Os -DNDEBUG" CACHE STRING "C++ compiler flags for MinSizeRel" FORCE)
set(CMAKE_ASM_FLAGS_MINSIZEREL "-DNDEBUG" CACHE STRING "ASM compiler flags for MinSizeRel" FORCE)

# Linker flags. The -T<linker script> is intentionally NOT set here: the
# ADuCM3029.ld is generated per-project by config_aducm3029_sdk(), which appends
# it via target_link_options() (mirrors the stm32/CubeMX flow).
set(CMAKE_EXE_LINKER_FLAGS "${COMMON_CPU_FLAGS} -specs=nosys.specs -Wl,--gc-sections -lm" CACHE STRING "Linker flags for MCU" FORCE)

# ---------------------------------------------------------------------------
# OpenOCD discovery (for flash/debug targets)
# ---------------------------------------------------------------------------
find_program(OPENOCD_PATH
    NAMES openocd
    DOC "Path to OpenOCD executable"
)

if(OPENOCD_PATH)
    get_filename_component(_ocd_bin "${OPENOCD_PATH}" DIRECTORY)
    set(OPENOCD_SCRIPTS "${_ocd_bin}/../share/openocd/scripts")
    set(OPENOCD_INTERFACE "interface/cmsis-dap.cfg")
    set(OPENOCD_CHIPNAME "aducm3029")
    set(OPENOCD_TARGETCFG "target/aducm3029.cfg")

    # target/aducm3029.cfg is in the DFP, not in OpenOCD's scripts dir. Add the
    # DFP's openocd/scripts to the search path.
    set(OPENOCD_EXTRA_COMMANDS "add_script_search_dir \"${ADUCM_DFP}/openocd/scripts\"")

    if(NOT PROBE)
        set(PROBE "openocd")
    endif()

    message(STATUS "Found OpenOCD: ${OPENOCD_PATH}")
else()
    message(STATUS "OpenOCD not found on PATH")
endif()
