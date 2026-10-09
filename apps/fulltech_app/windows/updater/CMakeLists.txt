cmake_minimum_required(VERSION 3.14)

add_executable(FullposUpdater WIN32
  "main.cpp"
)

target_compile_features(FullposUpdater PUBLIC cxx_std_17)
target_compile_definitions(FullposUpdater PRIVATE UNICODE _UNICODE NOMINMAX)
target_compile_options(FullposUpdater PRIVATE /W4 /WX /EHsc)
target_link_libraries(FullposUpdater PRIVATE wintrust.lib crypt32.lib shell32.lib bcrypt.lib shlwapi.lib)

# El destino debe ser una ruta ABSOLUTA expresada con un generator expression,
# igual que hace el runner en windows/CMakeLists.txt:
#   install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}")
# donde CMAKE_INSTALL_PREFIX = $<TARGET_FILE_DIR:fullpos_cloud>.
#
# Un DESTINATION relativo ("updater") NO sirve: CMake lo antepone al
# CMAKE_INSTALL_PREFIX *sin evaluar*, generando
#   .../x64/$<TARGET_FILE_DIR:fullpos_cloud>/updater
# y el paso INSTALL falla con "file cannot create directory ... Maybe need
# administrative privileges" (MSB3073 en INSTALL.vcxproj).
#
# Con el genex, el instalador va a <dir de fullpos_cloud.exe>/updater, que es
# "runner\Release\updater\FullposUpdater.exe" tal como lo empaqueta setup.iss.
install(TARGETS FullposUpdater RUNTIME
  DESTINATION "$<TARGET_FILE_DIR:fullpos_cloud>/updater"
  COMPONENT Runtime)
