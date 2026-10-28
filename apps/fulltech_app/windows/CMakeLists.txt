# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(fullpos_cloud LANGUAGES CXX)

# Flutter genera scripts de instalación con rutas absolutas al directorio `build/`.
# En algunos entornos CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION viene activado
# y rompe el build. Forzamos OFF para permitir compilar/instalar en Windows.
set(CMAKE_ERROR_ON_ABSOLUTE_INSTALL_DESTINATION OFF)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "fullpos_cloud")

# Identidad de la aplicacion parametrizable (build UAT aislada).
#
# Los valores por defecto son EXACTAMENTE los de produccion, asi que el build
# oficial no cambia de identidad. Un build UAT pasa otros valores:
#   -DFULLPOS_APP_COMPANY="DaleVentas UAT"
#   -DFULLPOS_APP_PRODUCT="DaleVentas POS UAT"
#   -DFULLPOS_APP_DESCRIPTION="DaleVentas POS UAT"
#   -DFULLPOS_WINDOW_TITLE="DaleVentas POS UAT - Pilot"
#   -DFULLPOS_MUTEX_NAME="Local\\\\DaleVentasPOSUATSingleInstance"
#   -DBINARY_NAME="fullpos_uat"
# Con ello Windows resuelve un directorio de datos distinto
# (%APPDATA%\<Company>\<Product>), el ejecutable no colisiona con la
# instalacion real y ambos pueden ejecutarse a la vez.
set(FULLPOS_APP_COMPANY "FullPOS" CACHE STRING "CompanyName del ejecutable")
set(FULLPOS_APP_PRODUCT "FullPOS" CACHE STRING "ProductName del ejecutable")
set(FULLPOS_APP_DESCRIPTION "FullPOS" CACHE STRING "FileDescription del ejecutable")
set(FULLPOS_WINDOW_TITLE "FullPOS Cloud - Sistema de facturacion" CACHE STRING "Titulo de la ventana")
set(FULLPOS_MUTEX_NAME "Local\\\\DaleVentasPOSSingleInstance" CACHE STRING "Nombre del mutex de instancia unica")

# Override por variables de entorno (build UAT aislada).
# Sin estas variables el resultado es EXACTAMENTE el de produccion.
if(DEFINED ENV{FULLPOS_BINARY_NAME} AND NOT "$ENV{FULLPOS_BINARY_NAME}" STREQUAL "")
  set(BINARY_NAME "$ENV{FULLPOS_BINARY_NAME}")
endif()
if(DEFINED ENV{FULLPOS_APP_COMPANY} AND NOT "$ENV{FULLPOS_APP_COMPANY}" STREQUAL "")
  set(FULLPOS_APP_COMPANY "$ENV{FULLPOS_APP_COMPANY}")
endif()
if(DEFINED ENV{FULLPOS_APP_PRODUCT} AND NOT "$ENV{FULLPOS_APP_PRODUCT}" STREQUAL "")
  set(FULLPOS_APP_PRODUCT "$ENV{FULLPOS_APP_PRODUCT}")
endif()
if(DEFINED ENV{FULLPOS_APP_DESCRIPTION} AND NOT "$ENV{FULLPOS_APP_DESCRIPTION}" STREQUAL "")
  set(FULLPOS_APP_DESCRIPTION "$ENV{FULLPOS_APP_DESCRIPTION}")
endif()
if(DEFINED ENV{FULLPOS_WINDOW_TITLE} AND NOT "$ENV{FULLPOS_WINDOW_TITLE}" STREQUAL "")
  set(FULLPOS_WINDOW_TITLE "$ENV{FULLPOS_WINDOW_TITLE}")
endif()
if(DEFINED ENV{FULLPOS_MUTEX_NAME} AND NOT "$ENV{FULLPOS_MUTEX_NAME}" STREQUAL "")
  set(FULLPOS_MUTEX_NAME "$ENV{FULLPOS_MUTEX_NAME}")
endif()

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")
add_subdirectory("updater")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
