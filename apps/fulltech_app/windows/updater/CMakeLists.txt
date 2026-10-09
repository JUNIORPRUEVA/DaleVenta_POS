cmake_minimum_required(VERSION 3.14)

add_executable(FullposUpdater WIN32
  "main.cpp"
)

target_compile_features(FullposUpdater PUBLIC cxx_std_17)
target_compile_definitions(FullposUpdater PRIVATE UNICODE _UNICODE NOMINMAX)
target_compile_options(FullposUpdater PRIVATE /W4 /WX /EHsc)
target_link_libraries(FullposUpdater PRIVATE wintrust.lib crypt32.lib shell32.lib bcrypt.lib shlwapi.lib)

# El destino debe ser RELATIVO al prefijo de instalacion. Con
# "${CMAKE_INSTALL_PREFIX}/updater" el prefijo (un generator expression del
# proyecto Flutter) se resolvia como ruta absoluta y el paso INSTALL fallaba
# intentando escribir en "C:/Program Files/fullpos_cloud/updater" sin permisos.
# Relativo => <prefijo>/updater, que es donde setup.iss espera
# "Release\updater\FullposUpdater.exe".
install(TARGETS FullposUpdater RUNTIME DESTINATION "updater"
  COMPONENT Runtime)
