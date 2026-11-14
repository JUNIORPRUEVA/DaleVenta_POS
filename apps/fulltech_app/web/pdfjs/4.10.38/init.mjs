import * as pdfjsLib from './pdf.min.mjs';

// Syncfusion 29.2.11 reads this global. Both renderer and worker stay on the
// application's origin: opening a business document needs no third-party CDN.
pdfjsLib.GlobalWorkerOptions.workerSrc = new URL('./pdf.worker.min.mjs', import.meta.url).href;
globalThis.pdfjsLib = pdfjsLib;
