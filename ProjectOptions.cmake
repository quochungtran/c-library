include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(c_library_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(c_library_setup_options)
  option(c_library_ENABLE_HARDENING "Enable hardening" ON)
  option(c_library_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    c_library_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    c_library_ENABLE_HARDENING
    OFF)

  c_library_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR c_library_PACKAGING_MAINTAINER_MODE)
    option(c_library_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(c_library_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(c_library_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(c_library_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(c_library_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(c_library_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(c_library_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(c_library_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(c_library_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(c_library_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(c_library_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(c_library_ENABLE_PCH "Enable precompiled headers" OFF)
    option(c_library_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(c_library_ENABLE_IPO "Enable IPO/LTO" ON)
    option(c_library_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(c_library_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(c_library_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(c_library_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(c_library_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(c_library_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(c_library_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(c_library_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(c_library_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(c_library_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(c_library_ENABLE_PCH "Enable precompiled headers" OFF)
    option(c_library_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      c_library_ENABLE_IPO
      c_library_WARNINGS_AS_ERRORS
      c_library_ENABLE_USER_LINKER
      c_library_ENABLE_SANITIZER_ADDRESS
      c_library_ENABLE_SANITIZER_LEAK
      c_library_ENABLE_SANITIZER_UNDEFINED
      c_library_ENABLE_SANITIZER_THREAD
      c_library_ENABLE_SANITIZER_MEMORY
      c_library_ENABLE_UNITY_BUILD
      c_library_ENABLE_CLANG_TIDY
      c_library_ENABLE_CPPCHECK
      c_library_ENABLE_COVERAGE
      c_library_ENABLE_PCH
      c_library_ENABLE_CACHE)
  endif()

  c_library_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (c_library_ENABLE_SANITIZER_ADDRESS OR c_library_ENABLE_SANITIZER_THREAD OR c_library_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(c_library_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(c_library_global_options)
  if(c_library_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    c_library_enable_ipo()
  endif()

  c_library_supports_sanitizers()

  if(c_library_ENABLE_HARDENING AND c_library_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR c_library_ENABLE_SANITIZER_UNDEFINED
       OR c_library_ENABLE_SANITIZER_ADDRESS
       OR c_library_ENABLE_SANITIZER_THREAD
       OR c_library_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${c_library_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${c_library_ENABLE_SANITIZER_UNDEFINED}")
    c_library_enable_hardening(c_library_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(c_library_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(c_library_warnings INTERFACE)
  add_library(c_library_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  c_library_set_project_warnings(
    c_library_warnings
    ${c_library_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(c_library_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    c_library_configure_linker(c_library_options)
  endif()

  include(cmake/Sanitizers.cmake)
  c_library_enable_sanitizers(
    c_library_options
    ${c_library_ENABLE_SANITIZER_ADDRESS}
    ${c_library_ENABLE_SANITIZER_LEAK}
    ${c_library_ENABLE_SANITIZER_UNDEFINED}
    ${c_library_ENABLE_SANITIZER_THREAD}
    ${c_library_ENABLE_SANITIZER_MEMORY})

  set_target_properties(c_library_options PROPERTIES UNITY_BUILD ${c_library_ENABLE_UNITY_BUILD})

  if(c_library_ENABLE_PCH)
    target_precompile_headers(
      c_library_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(c_library_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    c_library_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(c_library_ENABLE_CLANG_TIDY)
    c_library_enable_clang_tidy(c_library_options ${c_library_WARNINGS_AS_ERRORS})
  endif()

  if(c_library_ENABLE_CPPCHECK)
    c_library_enable_cppcheck(${c_library_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(c_library_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    c_library_enable_coverage(c_library_options)
  endif()

  if(c_library_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(c_library_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(c_library_ENABLE_HARDENING AND NOT c_library_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR c_library_ENABLE_SANITIZER_UNDEFINED
       OR c_library_ENABLE_SANITIZER_ADDRESS
       OR c_library_ENABLE_SANITIZER_THREAD
       OR c_library_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    c_library_enable_hardening(c_library_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
