cmake_minimum_required(VERSION 3.14)

add_executable(FullposUpdater WIN32
  "main.cpp"
)

target_compile_features(FullposUpdater PUBLIC cxx_std_17)
target_compile_definitions(FullposUpdater PRIVATE UNICODE _UNICODE NOMINMAX)
target_compile_options(FullposUpdater PRIVATE /W4 /WX /EHsc)
target_link_libraries(FullposUpdater PRIVATE wintrust.lib crypt32.lib shell32.lib bcrypt.lib shlwapi.lib)

install(TARGETS FullposUpdater RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}/updater"
  COMPONENT Runtime)
