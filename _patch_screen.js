const fs = require('fs');
const path = require('path');

const filePath = path.resolve(__dirname, 'apps/fulltech_app/lib/modules/crm_comercial/crm_comercial_screen.dart');
let content = fs.readFileSync(filePath, 'utf8');

console.log(`File length: ${content.length}`);

// ============================================================
// 2. Add bot status badge before search IconButton (line 5471)
// ============================================================
const target2 = `                IconButton(
                  tooltip: 'Buscar en conversacion',`;

const replacement2 = `                if (hasConversation) _BotStatusBadge(
                    botPaused: selectedConversation.botPaused,
                    botStatus: selectedConversation.botStatus,
                    botSkippedReason: selectedConversation.botSkippedReason,
                    isExcluded: selectedConversation.isExcluded,
                    botGloballyEnabled: _botGloballyEnabled,
                  ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Buscar en conversacion',`;

if (content.includes(target2)) {
  content = content.replace(target2, replacement2);
  console.log('2. Bot status badge added');
} else {
  console.log('2. FAILED - target not found');
  // Debug: show what's around that area
  const idx = content.indexOf('IconButton');
  if (idx >= 0) {
    console.log('First IconButton found at index:', idx);
    console.log('Context:', JSON.stringify(content.substring(idx, idx + 100)));
  }
}

// ============================================================
// 3. Add bot control menu items in PopupMenuButton (line 5582)
// ============================================================
const target3 = `                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'new-chat',
                      child: Text('Nuevo chat por numero'),
                    ),
                  ],`;

const replacement3 = `                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: 'new-chat',
                      child: Text('Nuevo chat por numero'),
                    ),
                    if (hasConversation) ...[
                      PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'bot-pause',
                        child: Text(selectedConversation.botPaused ? 'Reanudar bot' : 'Pausar bot'),
                      ),
                      PopupMenuItem<String>(
                        value: 'bot-exclude',
                        child: Text(selectedConversation.isExcluded ? 'Incluir numero en bot' : 'Excluir numero del bot'),
                      ),
                      PopupMenuItem<String>(
                        value: 'bot-suggest',
                        child: const Text('Sugerir respuesta con bot'),
                      ),
                    ],
                  ],`;

if (content.includes(target3)) {
  content = content.replace(target3, replacement3);
  console.log('3. Bot menu items added');
} else {
  console.log('3. FAILED - target not found');
  // Debug
  const idx = content.indexOf('itemBuilder: (context) => const');
  if (idx >= 0) {
    console.log('itemBuilder found at index:', idx);
    console.log('Context:', JSON.stringify(content.substring(idx, idx + 200)));
  }
}

// ============================================================
// 4. Add bot action handler (line 5577-5580)
// ============================================================
const target4 = `                    if (value == 'new-chat') {
                      _openNewChatDialog();
                    }`;

const replacement4 = `                    if (value == 'new-chat') {
                      _openNewChatDialog();
                    } else if (value == 'bot-pause') {
                      _toggleBotPause();
                    } else if (value == 'bot-exclude') {
                      _toggleBotExclude();
                    } else if (value == 'bot-suggest') {
                      _suggestBotReply();
                    }`;

if (content.includes(target4)) {
  content = content.replace(target4, replacement4);
  console.log('4. Bot action handler added');
} else {
  console.log('4. FAILED - target not found');
  const idx = content.indexOf("value == 'new-chat'");
  if (idx >= 0) {
    console.log('new-chat handler found at index:', idx);
    console.log('Context:', JSON.stringify(content.substring(idx, idx + 150)));
  }
}

// Write the modified content back
fs.writeFileSync(filePath, content, 'utf8');
console.log('Done - Screen patched successfully');
