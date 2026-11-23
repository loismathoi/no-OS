# ADuCM3029 platform SDK configuration.
#
# Adds the device sources to the project. System, reset and config headers come
# unchanged from the DFP. Startup is no-OS's patched version. The linker script
# is the DFP's, reworked into the build dir.

# Resolve the pinmux_config.c "hardware" file for the current project.
# Sets PINMUX_FILE in the caller's scope.
function(resolve_aducm_pinmux_file)
	if(DEFINED CONFIG_ADUCM_PINMUX_PATH AND NOT "${CONFIG_ADUCM_PINMUX_PATH}" STREQUAL "")
		if(IS_ABSOLUTE "${CONFIG_ADUCM_PINMUX_PATH}")
			set(PINMUX_FILE "${CONFIG_ADUCM_PINMUX_PATH}" PARENT_SCOPE)
		else()
			set(PINMUX_FILE "${CMAKE_SOURCE_DIR}/projects/${NO_OS_PROJECT_NAME}/${CONFIG_ADUCM_PINMUX_PATH}" PARENT_SCOPE)
		endif()
	else()
		set(PINMUX_FILE "${CMAKE_SOURCE_DIR}/projects/${NO_OS_PROJECT_NAME}/pinmux_config.c" PARENT_SCOPE)
	endif()
endfunction()

function(config_aducm3029_sdk BUILD_TARGET)
	resolve_aducm_pinmux_file()
	if(NOT EXISTS "${PINMUX_FILE}")
		message(FATAL_ERROR
			"ADuCM3029 pinmux file not found: ${PINMUX_FILE}. "
			"Provide projects/${NO_OS_PROJECT_NAME}/pinmux_config.c or set "
			"CONFIG_ADUCM_PINMUX_PATH.")
	endif()

	set(PLATFORM_TOOLS "${NO_OS_DIR}/tools/scripts/platform/aducm3029")

	# DFP sources are used in place. Startup is no-OS's patch.
	target_sources(${BUILD_TARGET} PRIVATE
		${PLATFORM_TOOLS}/startup_ADuCM3029_patch.c
		${PLATFORM_TOOLS}/rte/adi_initialize.c
		${ADUCM_DFP}/Source/system_ADuCM3029.c
		${ADUCM_DFP}/Source/GCC/reset_ADuCM3029.S
		${PINMUX_FILE}
	)

	# Driver config headers and RTE/init headers.
	target_include_directories(no-os PUBLIC
		${ADUCM_DFP}/Include/config
		${PLATFORM_TOOLS}/rte
	)

	# Rework the generated linker script so the WiFi/IIOD workload can use as
	# much of the chip's 64 KiB SRAM as possible.
	#
	# The reset handler clears INSTREN (-DADI_DISABLE_INSTRUCTION_SRAM, see
	# toolchain.cmake), which remaps the 32 KiB of otherwise-unused instruction
	# SRAM as data SRAM (SRAM MODE2). The chip then exposes two 32 KiB data
	# banks that are NOT contiguous: DSRAM_A at 0x20000000 and DSRAM_B at
	# 0x20040000. newlib's malloc/_sbrk can only grow one contiguous region, so
	# the heap cannot straddle the gap - it must live entirely in one bank.
	#
	# The stock script puts .data/.bss in DSRAM_B and heap+stack in DSRAM_A,
	# which caps the heap at "32 KiB minus data/bss/stack". Instead:
	#   1. widen both banks 16k -> 32k,
	#   2. move .data/.bss into DSRAM_A (alongside the stack), and
	#   3. give the whole of DSRAM_B to the heap.
	# The fixed footprint (.data + .bss + stack ~= 18 KiB) then lives in
	# DSRAM_A with room to spare, and the heap gets a full contiguous 32 KiB
	# bank to itself (see __HEAP_SIZE in the platform CMakeLists).
	#
	# DFP 4.x gives each section a program header (> DSRAM_B :ram_b). A moved
	# section gets the header of its new bank. CRLF is stripped first.
	set(_ld_file "${CMAKE_CURRENT_BINARY_DIR}/ADuCM3029.ld")
	file(READ "${ADUCM_DFP}/Source/GCC/ADuCM3029.ld" _ld_contents)
	string(REPLACE "\r" "" _ld_contents "${_ld_contents}")
	# 1. Both banks physically span 32 KiB.
	string(REGEX REPLACE
		"(DSRAM_A[^\n]*ORIGIN[ \t]*=[ \t]*0x20000000,[ \t]*LENGTH[ \t]*=[ \t]*)16k"
		"\\132k" _ld_contents "${_ld_contents}")
	string(REGEX REPLACE
		"(DSRAM_B[^\n]*ORIGIN[ \t]*=[ \t]*0x20040000,[ \t]*LENGTH[ \t]*=[ \t]*)16k"
		"\\132k" _ld_contents "${_ld_contents}")
	# 2. .data and .bss move from DSRAM_B to DSRAM_A (anchored on their end
	#    symbols so only these two output sections are retargeted).
	string(REGEX REPLACE
		"(__data_end__[^}]*})[ \t]*>[ \t]*DSRAM_B[ \t]*:ram_b"
		"\\1 > DSRAM_A :ram_a" _ld_contents "${_ld_contents}")
	string(REGEX REPLACE
		"(__bss_end__[^}]*})[ \t]*>[ \t]*DSRAM_B[ \t]*:ram_b"
		"\\1 > DSRAM_A :ram_a" _ld_contents "${_ld_contents}")
	# 3. The heap moves from DSRAM_A to DSRAM_B (gets the whole bank).
	string(REGEX REPLACE
		"(__HeapLimit[^}]*})[ \t]*>[ \t]*DSRAM_A[ \t]*:ram_a"
		"\\1 > DSRAM_B :ram_b" _ld_contents "${_ld_contents}")
	# 4. The stock ASSERT guarded heap+stack sharing DSRAM_A. Now DSRAM_A holds
	#    data/bss/stack and DSRAM_B holds the heap, so guard each bank instead.
	string(REGEX REPLACE
		"ASSERT\\(__StackLimit >= __HeapLimit[^\n]*\n"
		"ASSERT(__StackLimit >= __bss_end__, \"region DSRAM_A overflowed with stack\")\n\tASSERT(__HeapLimit <= ORIGIN(DSRAM_B) + LENGTH(DSRAM_B), \"region DSRAM_B overflowed with heap\")\n"
		_ld_contents "${_ld_contents}")
	# REGEX REPLACE returns unchanged string on pattern mismatch
	if(NOT _ld_contents MATCHES "DSRAM_A[^\n]*LENGTH = 32k"
	   OR NOT _ld_contents MATCHES "DSRAM_B[^\n]*LENGTH = 32k"
	   OR NOT _ld_contents MATCHES "__bss_end__[^}]*}[ \t]*> DSRAM_A :ram_a"
	   OR NOT _ld_contents MATCHES "__HeapLimit[^}]*}[ \t]*> DSRAM_B :ram_b"
	   OR NOT _ld_contents MATCHES "region DSRAM_B overflowed with heap")
		message(FATAL_ERROR
			"ADuCM3029.ld rework did not match ${ADUCM_DFP}/Source/GCC/ADuCM3029.ld.")
	endif()
	file(WRITE "${_ld_file}" "${_ld_contents}")

	target_link_options(${BUILD_TARGET} PRIVATE -T${_ld_file})

	# OpenOCD config for flash/debug (vars set in toolchain.cmake).
	generate_openocd_config()
endfunction()
