#include <windows.h>
#include <wincrypt.h>
#include <wintrust.h>
#include <softpub.h>
#include <bcrypt.h>
#include <shellapi.h>
#include <shlwapi.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iomanip>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\DaleVentasPOSSingleInstance";
constexpr DWORD kWaitTimeoutMs = 120000;

struct Options {
  bool verify_only = false;
  bool allow_unsigned = false;
  std::wstring package_path;
  std::wstring update_root;
  std::wstring expected_sha256;
  std::wstring expected_publisher;
  std::wstring restart_exe;
  std::wstring log_path;
  DWORD parent_pid = 0;
  int target_build = 0;
};

struct Result {
  std::wstring code = L"SUCCESS";
  DWORD exit_code = 0;
};

std::wstring ToLower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) {
    return static_cast<wchar_t>(towlower(ch));
  });
  return value;
}

std::wstring Trim(std::wstring value) {
  while (!value.empty() && iswspace(value.front())) value.erase(value.begin());
  while (!value.empty() && iswspace(value.back())) value.pop_back();
  return value;
}

bool StartsWithPath(const std::wstring& child, const std::wstring& root) {
  std::wstring c = ToLower(child);
  std::wstring r = ToLower(root);
  if (!r.empty() && r.back() != L'\\') r.push_back(L'\\');
  return c == ToLower(root) || c.rfind(r, 0) == 0;
}

std::wstring StripDevicePrefix(std::wstring path) {
  const std::wstring prefix = L"\\\\?\\";
  if (path.rfind(prefix, 0) == 0) return path.substr(prefix.size());
  return path;
}

bool CanonicalizeExistingPath(const std::wstring& input, bool directory,
                              std::wstring* output) {
  DWORD attributes = GetFileAttributesW(input.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) return false;
  if (directory && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0) return false;
  if (!directory && (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) return false;

  DWORD flags = directory ? FILE_FLAG_BACKUP_SEMANTICS : FILE_ATTRIBUTE_NORMAL;
  HANDLE handle = CreateFileW(input.c_str(), 0,
                              FILE_SHARE_READ | FILE_SHARE_WRITE |
                                  FILE_SHARE_DELETE,
                              nullptr, OPEN_EXISTING, flags, nullptr);
  if (handle == INVALID_HANDLE_VALUE) return false;

  std::vector<wchar_t> buffer(32768);
  DWORD length = GetFinalPathNameByHandleW(handle, buffer.data(),
                                           static_cast<DWORD>(buffer.size()),
                                           FILE_NAME_NORMALIZED);
  CloseHandle(handle);
  if (length == 0 || length >= buffer.size()) return false;
  *output = StripDevicePrefix(std::wstring(buffer.data(), length));
  return true;
}

std::wstring ParentDirectory(const std::wstring& path) {
  std::wstring copy = path;
  PathRemoveFileSpecW(copy.data());
  return copy.c_str();
}

bool EnsureDirectory(const std::wstring& path) {
  if (path.empty()) return false;
  if (CreateDirectoryW(path.c_str(), nullptr)) return true;
  return GetLastError() == ERROR_ALREADY_EXISTS;
}

std::wstring Timestamp() {
  SYSTEMTIME st{};
  GetLocalTime(&st);
  wchar_t buffer[64]{};
  swprintf_s(buffer, L"%04u-%02u-%02uT%02u:%02u:%02u.%03u",
             st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
             st.wMilliseconds);
  return buffer;
}

void AppendLog(const Options& options, const std::wstring& message) {
  if (options.log_path.empty()) return;
  EnsureDirectory(ParentDirectory(options.log_path));
  std::wofstream log(options.log_path, std::ios::app);
  if (!log.is_open()) return;
  log << Timestamp() << L" targetBuild=" << options.target_build << L" "
      << message << L"\n";
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return std::string();
  int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                 static_cast<int>(value.size()), nullptr, 0,
                                 nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

void WriteResultFile(const Options& options, const Result& result) {
  if (options.update_root.empty() || options.target_build <= 0) return;
  std::wstring dir =
      options.update_root + L"\\" + std::to_wstring(options.target_build);
  EnsureDirectory(dir);
  std::wstring path = dir + L"\\installer_result.json";
  std::ofstream file(path, std::ios::trunc);
  if (!file.is_open()) return;
  file << "{\n";
  file << "  \"targetBuild\": " << options.target_build << ",\n";
  file << "  \"result\": \"" << WideToUtf8(result.code) << "\",\n";
  file << "  \"exitCode\": " << result.exit_code << ",\n";
  file << "  \"timestamp\": \"" << WideToUtf8(Timestamp()) << "\"\n";
  file << "}\n";
}

std::vector<std::wstring> CommandLineArgs() {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  std::vector<std::wstring> args;
  if (argv == nullptr) return args;
  for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
  LocalFree(argv);
  return args;
}

bool ParseOptions(Options* options) {
  const auto args = CommandLineArgs();
  for (size_t i = 0; i < args.size(); ++i) {
    const std::wstring key = args[i];
    auto require_value = [&](std::wstring* target) -> bool {
      if (i + 1 >= args.size()) return false;
      *target = args[++i];
      return true;
    };
    if (key == L"--verify-only") {
      options->verify_only = true;
    } else if (key == L"--allow-unsigned") {
      options->allow_unsigned = true;
    } else if (key == L"--package") {
      if (!require_value(&options->package_path)) return false;
    } else if (key == L"--update-root") {
      if (!require_value(&options->update_root)) return false;
    } else if (key == L"--expected-sha256") {
      if (!require_value(&options->expected_sha256)) return false;
    } else if (key == L"--expected-publisher") {
      if (!require_value(&options->expected_publisher)) return false;
    } else if (key == L"--restart-exe") {
      if (!require_value(&options->restart_exe)) return false;
    } else if (key == L"--log-path") {
      if (!require_value(&options->log_path)) return false;
    } else if (key == L"--parent-pid") {
      std::wstring value;
      if (!require_value(&value)) return false;
      options->parent_pid = wcstoul(value.c_str(), nullptr, 10);
    } else if (key == L"--target-build") {
      std::wstring value;
      if (!require_value(&value)) return false;
      options->target_build = _wtoi(value.c_str());
    } else {
      return false;
    }
  }
  return !options->package_path.empty() && !options->update_root.empty() &&
         !options->expected_sha256.empty();
}

std::wstring BytesToHex(const std::vector<unsigned char>& bytes) {
  std::wostringstream stream;
  stream << std::hex << std::setfill(L'0');
  for (unsigned char byte : bytes) {
    stream << std::setw(2) << static_cast<int>(byte);
  }
  return stream.str();
}

bool VerifySha256(const std::wstring& path, const std::wstring& expected) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                            nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;

  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  bool ok = false;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr,
                                  0) == 0 &&
      BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) == 0) {
    std::vector<unsigned char> buffer(64 * 1024);
    DWORD read = 0;
    ok = true;
    while (ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()),
                    &read, nullptr) &&
           read > 0) {
      if (BCryptHashData(hash, buffer.data(), read, 0) != 0) {
        ok = false;
        break;
      }
    }
    std::vector<unsigned char> digest(32);
    if (ok &&
        BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()),
                         0) == 0) {
      ok = ToLower(BytesToHex(digest)) == ToLower(Trim(expected));
    } else {
      ok = false;
    }
  }
  if (hash) BCryptDestroyHash(hash);
  if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
  CloseHandle(file);
  return ok;
}

bool WinVerifyTrustFile(const std::wstring& path) {
  WINTRUST_FILE_INFO file_info{};
  file_info.cbStruct = sizeof(file_info);
  file_info.pcwszFilePath = path.c_str();

  WINTRUST_DATA trust_data{};
  trust_data.cbStruct = sizeof(trust_data);
  trust_data.dwUIChoice = WTD_UI_NONE;
  trust_data.fdwRevocationChecks = WTD_REVOKE_WHOLECHAIN;
  trust_data.dwUnionChoice = WTD_CHOICE_FILE;
  trust_data.pFile = &file_info;
  trust_data.dwStateAction = WTD_STATEACTION_VERIFY;
  trust_data.dwProvFlags = WTD_CACHE_ONLY_URL_RETRIEVAL;

  GUID policy = WINTRUST_ACTION_GENERIC_VERIFY_V2;
  LONG status = WinVerifyTrust(nullptr, &policy, &trust_data);
  trust_data.dwStateAction = WTD_STATEACTION_CLOSE;
  WinVerifyTrust(nullptr, &policy, &trust_data);
  return status == ERROR_SUCCESS;
}

std::wstring ReadPublisher(const std::wstring& path) {
  HCERTSTORE store = nullptr;
  HCRYPTMSG message = nullptr;
  DWORD encoding = 0;
  DWORD content_type = 0;
  DWORD format_type = 0;
  if (!CryptQueryObject(CERT_QUERY_OBJECT_FILE, path.c_str(),
                        CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED,
                        CERT_QUERY_FORMAT_FLAG_BINARY, 0, &encoding,
                        &content_type, &format_type, &store, &message,
                        nullptr)) {
    return L"";
  }

  DWORD signer_size = 0;
  if (!CryptMsgGetParam(message, CMSG_SIGNER_INFO_PARAM, 0, nullptr,
                        &signer_size)) {
    CertCloseStore(store, 0);
    CryptMsgClose(message);
    return L"";
  }
  std::vector<unsigned char> signer_buffer(signer_size);
  if (!CryptMsgGetParam(message, CMSG_SIGNER_INFO_PARAM, 0,
                        signer_buffer.data(), &signer_size)) {
    CertCloseStore(store, 0);
    CryptMsgClose(message);
    return L"";
  }
  auto* signer = reinterpret_cast<PCMSG_SIGNER_INFO>(signer_buffer.data());
  CERT_INFO cert_info{};
  cert_info.Issuer = signer->Issuer;
  cert_info.SerialNumber = signer->SerialNumber;
  PCCERT_CONTEXT cert =
      CertFindCertificateInStore(store, encoding, 0, CERT_FIND_SUBJECT_CERT,
                                 &cert_info, nullptr);
  std::wstring publisher;
  if (cert != nullptr) {
    DWORD name_size = CertGetNameStringW(
        cert, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nullptr, nullptr, 0);
    if (name_size > 1) {
      std::vector<wchar_t> name(name_size);
      CertGetNameStringW(cert, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nullptr,
                         name.data(), name_size);
      publisher.assign(name.data());
    }
    CertFreeCertificateContext(cert);
  }
  CertCloseStore(store, 0);
  CryptMsgClose(message);
  return publisher;
}

Result ValidatePackage(const Options& options) {
  std::wstring package;
  std::wstring root;
  if (!CanonicalizeExistingPath(options.package_path, false, &package) ||
      !CanonicalizeExistingPath(options.update_root, true, &root)) {
    return {L"INVALID_PATH", 2};
  }
  if (!StartsWithPath(package, root)) return {L"PACKAGE_OUTSIDE_ROOT", 3};
  if (!VerifySha256(package, options.expected_sha256)) {
    return {L"HASH_MISMATCH", 4};
  }
  if (options.allow_unsigned && Trim(options.expected_publisher).empty()) {
    return {L"SUCCESS", 0};
  }
  if (!WinVerifyTrustFile(package)) return {L"SIGNATURE_INVALID", 5};
  const std::wstring publisher = ReadPublisher(package);
  if (publisher.empty()) return {L"PUBLISHER_MISSING", 6};
  if (ToLower(publisher) != ToLower(Trim(options.expected_publisher))) {
    return {L"PUBLISHER_MISMATCH", 7};
  }
  return {L"SUCCESS", 0};
}

void PrintResult(const Result& result) {
  std::wprintf(L"RESULT=%ls\n", result.code.c_str());
}

void WaitForParent(const Options& options) {
  if (options.parent_pid == 0) {
    AppendLog(options, L"parent wait skipped: no parent pid");
    return;
  }
  HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, options.parent_pid);
  if (process == nullptr) {
    AppendLog(options, L"parent wait skipped: parent not found");
    return;
  }
  AppendLog(options, L"parent wait started");
  DWORD wait = WaitForSingleObject(process, kWaitTimeoutMs);
  CloseHandle(process);
  AppendLog(options, wait == WAIT_OBJECT_0 ? L"parent exited"
                                           : L"parent wait timeout");
}

void WaitForMutex(const Options& options) {
  HANDLE mutex = OpenMutexW(SYNCHRONIZE, FALSE, kSingleInstanceMutexName);
  if (mutex == nullptr) {
    AppendLog(options, L"mutex wait skipped: mutex not present");
    return;
  }
  AppendLog(options, L"mutex wait started");
  DWORD wait = WaitForSingleObject(mutex, kWaitTimeoutMs);
  CloseHandle(mutex);
  AppendLog(options, wait == WAIT_OBJECT_0 ? L"mutex released"
                                           : L"mutex wait timeout");
}

Result RunInstaller(const Options& options) {
  std::wstring inno_log = options.log_path + L".inno.log";
  std::wstring params = L"/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG=\"" +
                        inno_log + L"\"";
  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOCLOSEPROCESS;
  info.lpVerb = L"runas";
  info.lpFile = options.package_path.c_str();
  info.lpParameters = params.c_str();
  info.nShow = SW_SHOWNORMAL;
  AppendLog(options, L"installer start requested");
  if (!ShellExecuteExW(&info)) {
    DWORD error = GetLastError();
    if (error == ERROR_CANCELLED) {
      AppendLog(options, L"uac result=cancelled");
      return {L"UAC_CANCELLED", error};
    }
    AppendLog(options, L"installer ShellExecuteEx failed");
    return {L"UPDATER_ERROR", error};
  }
  AppendLog(options, L"installer started");
  WaitForSingleObject(info.hProcess, INFINITE);
  DWORD exit_code = 1;
  GetExitCodeProcess(info.hProcess, &exit_code);
  CloseHandle(info.hProcess);
  AppendLog(options, std::wstring(L"installer exit code=") +
                         std::to_wstring(exit_code));
  if (exit_code == 0) return {L"SUCCESS", 0};
  return {L"INSTALLER_FAILED", exit_code};
}

void Relaunch(const Options& options) {
  if (options.restart_exe.empty()) {
    AppendLog(options, L"relaunch skipped");
    return;
  }
  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.lpFile = options.restart_exe.c_str();
  info.nShow = SW_SHOWNORMAL;
  if (ShellExecuteExW(&info)) {
    AppendLog(options, L"relaunch result=success");
  } else {
    AppendLog(options, std::wstring(L"relaunch result=failure error=") +
                           std::to_wstring(GetLastError()));
  }
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int) {
  Options options;
  if (!ParseOptions(&options)) {
    Result result{L"INVALID_ARGS", 1};
    PrintResult(result);
    return static_cast<int>(result.exit_code);
  }

  AppendLog(options, options.verify_only ? L"verify-only started"
                                         : L"updater started");
  Result validation = ValidatePackage(options);
  if (validation.code != L"SUCCESS") {
    AppendLog(options, std::wstring(L"validation failed result=") +
                           validation.code);
    WriteResultFile(options, validation);
    PrintResult(validation);
    return static_cast<int>(validation.exit_code);
  }
  if (options.verify_only) {
    AppendLog(options, L"verify-only success");
    PrintResult(validation);
    return 0;
  }

  WaitForParent(options);
  WaitForMutex(options);
  Result install_result = RunInstaller(options);
  WriteResultFile(options, install_result);
  if (install_result.code == L"SUCCESS") {
    AppendLog(options, L"INSTALLER_SUCCESS");
  }
  Relaunch(options);
  PrintResult(install_result);
  return install_result.code == L"SUCCESS" ? 0 : static_cast<int>(install_result.exit_code);
}
