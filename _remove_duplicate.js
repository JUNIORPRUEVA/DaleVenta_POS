const fs = require('fs');
const path = require('path');

const filePath = path.resolve(__dirname, 'apps/fulltech_app/lib/modules/crm_comercial/crm_comercial_screen.dart');
let content = fs.readFileSync(filePath, 'utf8');

// Find the SECOND occurrence of the bot methods header (the misplaced one)
const firstIdx = content.indexOf('// --- Bot AI UI methods');
const secondIdx = content.indexOf('// --- Bot AI UI methods', firstIdx + 1);

if (secondIdx < 0) {
  console.log('No duplicate found');
  process.exit(0);
}

console.log('First occurrence at:', firstIdx);
console.log('Second occurrence at:', secondIdx);

// The second occurrence ends with "}\r\n\r\nclass _CrmQuickReplyTemplate"
const endMarker = 'class _CrmQuickReplyTemplate';
const endIdx = content.indexOf(endMarker, secondIdx);

if (endIdx < 0) {
  console.log('Could not find end marker');
  process.exit(1);
}

console.log('endIdx:', endIdx);

// Go back from endMarker to find the preceding "}\r\n\r\n"
const blockEnd = content.lastIndexOf('}\r\n\r\n', endIdx);
if (blockEnd < secondIdx) {
  console.log('Could not find block end with \\r\\n, trying \\n');
  const blockEnd2 = content.lastIndexOf('}\n\n', endIdx);
  if (blockEnd2 < secondIdx) {
    console.log('Could not find block end at all');
    process.exit(1);
  }
  console.log('Block ends at:', blockEnd2);
  // Remove from secondIdx to blockEnd2 + 3
  const before = content.substring(0, secondIdx);
  const after = content.substring(blockEnd2 + 3);
  content = before + after;
} else {
  console.log('Block ends at:', blockEnd);
  // Remove from secondIdx to blockEnd + 4 (the "}\r\n\r\n")
  const before = content.substring(0, secondIdx);
  const after = content.substring(blockEnd + 4);
  content = before + after;
}

fs.writeFileSync(filePath, content, 'utf8');
console.log('Duplicate removed successfully');

// Verify
const count = content.split('// --- Bot AI UI methods').length - 1;
console.log('Remaining occurrences:', count);
