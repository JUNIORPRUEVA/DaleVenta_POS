/// Lectura de variables de entorno del proceso en plataformas de escritorio y
/// móviles. En web no existe, así que se resuelve con un stub.
library;

export 'guardian_runtime_env_io.dart'
    if (dart.library.html) 'guardian_runtime_env_web.dart';
