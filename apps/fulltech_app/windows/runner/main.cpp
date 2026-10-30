#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kWindowTitle[] = L"FullPOS Cloud - Sistema de facturacion";
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\DaleVentasPOSSingleInstance";

// El artefacto UAT convive con la instalación COMERCIAL en el mismo equipo, y
// ambas comparten nombre de producto. Con un mutex común, arrancar la UAT
// mientras la comercial está abierta terminaba en un cierre silencioso
// (`ERROR_ALREADY_EXISTS` -> EXIT_SUCCESS) y además enfocaba la ventana
// comercial. El sufijo aísla la instancia única del artefacto UAT sin tocar a la
// instalación comercial, que conserva su mutex original.
constexpr wchar_t kUatInstanceMutexSuffix[] = L"_UAT";
constexpr wchar_t kUatBuildMarker[] = L"UAT_BUILD_MANIFEST.json";

// Un artefacto es UAT si junto al ejecutable está el manifiesto que genera
// `scripts/build/build_windows_ecf_uat.ps1`. No depende de variables de entorno
// ni de argumentos: abrir el .exe con doble clic también funciona.
bool IsUatArtifact() {
  wchar_t path[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return false;
  const std::wstring exe(path, length);
  const size_t separator = exe.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return false;
  const std::wstring marker = exe.substr(0, separator + 1) + kUatBuildMarker;
  return ::GetFileAttributesW(marker.c_str()) != INVALID_FILE_ATTRIBUTES;
}

std::wstring SingleInstanceMutexName() {
  std::wstring name(kSingleInstanceMutexName);
  if (IsUatArtifact()) {
    name += kUatInstanceMutexSuffix;
  }
  return name;
}

bool FocusExistingWindow() {
  HWND existing_window = ::FindWindow(kWindowClassName, kWindowTitle);
  if (!existing_window) {
    return false;
  }
  if (::IsIconic(existing_window)) {
    ::ShowWindow(existing_window, SW_RESTORE);
  } else {
    ::ShowWindow(existing_window, SW_SHOWNORMAL);
  }
  ::SetForegroundWindow(existing_window);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  const std::wstring instance_mutex_name = SingleInstanceMutexName();
  HANDLE single_instance_mutex =
      ::CreateMutex(nullptr, TRUE, instance_mutex_name.c_str());
  if (single_instance_mutex && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Solo se enfoca una ventana cuando YA hay otra instancia de ESTE mismo
    // artefacto: con el mutex separado, la UAT nunca toca la ventana comercial.
    FocusExistingWindow();
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    if (single_instance_mutex) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance_mutex) {
    ::ReleaseMutex(single_instance_mutex);
    ::CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}
