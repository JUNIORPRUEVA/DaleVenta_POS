# Local PDF renderer

PDF.js 4.10.38, compatible with the installed Syncfusion PDF viewer29.2.11.
The upstream files are unmodified and retain their Apache2 license. Both the
renderer and its matching worker are served locally, including in Flutter web
builds; generated PDFs are never uploaded to a rendering service.

Integration reference: https://pub.dev/packages/syncfusion_flutter_pdfviewer/versions/29.2.11

Upstream assets: https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.10.38/

SHA256:

- pdf.min.mjs: `27fc2a057a00f92a4334ad06e17dbd7259912954e9fb7f76400bcca5fd190a9c`
- pdf.worker.min.mjs: `1baa1844c89c80a5b2797c916e75ab29254be46d8e9cb53cb6364d7aad84be36`

Update the library and worker together, preserve the license, and rerun the web
PDF acceptance check. Do not replace one asset with a different version.
