// Selecciona la implementación de guardado según la plataforma.
//
// Web descarga realmente usando un `Blob` del navegador; escritorio y móvil
// escriben en el directorio temporal de la aplicación. El stub queda solo como
// red de seguridad para plataformas sin ninguna de las dos capacidades.
export 'dgii_document_saver_stub.dart'
    if (dart.library.io) 'dgii_document_saver_io.dart'
    if (dart.library.js_interop) 'dgii_document_saver_web.dart';
