{{flutter_js}}
{{flutter_build_config}}

(async function () {
  let timer;
  try {
    // Initialize the viewer before Dart can open a preview. A missing renderer
    // must not hold the entire POS at its splash screen indefinitely.
    await Promise.race([
      import(new URL('pdfjs/4.10.38/init.mjs', document.baseURI).href),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('PDF_RENDERER_TIMEOUT')), 8000); }),
    ]);
  } catch (_) {
    console.warn('No se pudo cargar el visor PDF local. La descarga sigue disponible.');
  } finally {
    clearTimeout(timer);
  }
  _flutter.loader.load({
    serviceWorkerSettings: { serviceWorkerVersion: {{flutter_service_worker_version}} },
  });
})();
