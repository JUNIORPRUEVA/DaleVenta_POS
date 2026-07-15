import 'runtime_env_stub.dart' if (dart.library.html) 'runtime_env_web.dart';

class RuntimeEnv {
  static String? get(String key) => runtimeEnvGet(key);
}
