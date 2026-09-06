#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kWindowTitle[] = L"FullPOS Cloud - Sistema de facturacion";
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\DaleVentasPOSSingleInstance";
constexpr ULONG_PTR kBackupOpenCopyDataId = 0x4456424B;

std::wstring Utf16FromUtf8(const std::string& utf8_string) {
  if (utf8_string.empty()) {
    return std::wstring();
  }
  int target_length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(),
      static_cast<int>(utf8_string.size()), nullptr, 0);
  if (target_length <= 0) {
    return std::wstring();
  }
  std::wstring utf16_string(target_length, L'\0');
  int converted_length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(),
      static_cast<int>(utf8_string.size()), utf16_string.data(), target_length);
  if (converted_length <= 0) {
    return std::wstring();
  }
  return utf16_string;
}

bool EndsWith(const std::string& value, const std::string& suffix) {
  if (suffix.size() > value.size()) {
    return false;
  }
  return std::equal(suffix.rbegin(), suffix.rend(), value.rbegin());
}

bool IsBackupPath(const std::string& value) {
  std::string lower = value;
  std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return EndsWith(lower, ".dvbackup") || EndsWith(lower, ".zip");
}

std::wstring FirstBackupPath(const std::vector<std::string>& arguments) {
  for (const auto& argument : arguments) {
    if (IsBackupPath(argument)) {
      return Utf16FromUtf8(argument);
    }
  }
  return std::wstring();
}

bool ForwardBackupOpenToExistingWindow(const std::wstring& backup_path) {
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
  if (!backup_path.empty()) {
    COPYDATASTRUCT payload{};
    payload.dwData = kBackupOpenCopyDataId;
    payload.cbData =
        static_cast<DWORD>((backup_path.size() + 1) * sizeof(wchar_t));
    payload.lpData = const_cast<wchar_t*>(backup_path.c_str());
    ::SendMessage(existing_window, WM_COPYDATA, 0,
                  reinterpret_cast<LPARAM>(&payload));
  }
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance_mutex =
      ::CreateMutex(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    const std::vector<std::string> command_line_arguments =
        GetCommandLineArguments();
    ForwardBackupOpenToExistingWindow(FirstBackupPath(command_line_arguments));
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
