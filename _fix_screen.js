const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'apps/fulltech_app/lib/modules/crm_comercial/crm_comercial_screen.dart');
let content = fs.readFileSync(filePath, 'utf8');

const lines = content.split('\n');

// Find the exact line of `class _CrmComercialScreenState`
let stateClassLine = -1;
let stateClassEndLine = -1;
let quickReplyLine = -1;
let searchIconLine = -1;
let masAccionesLine = -1;
let masAccionesEndLine = -1;

for (let i = 0; i < lines.length; i++) {
  const line = lines[i];
  
  if (line.includes('class _CrmComercialScreenState')) {
    stateClassLine = i;
  }
  
  if (line.includes('class _CrmQuickReplyTemplate')) {
    quickReplyLine = i;
  }
  
  if (line.includes("icon: const Icon(Icons.search_rounded, size: 20),") && i > 5400 && i < 5500) {
    searchIconLine = i;
  }
  
  if (line.includes("tooltip: 'Mas acciones'")) {
    masAccionesLine = i;
  }
}

// Find the end of _CrmComercialScreenState (the closing } before _CrmQuickReplyTemplate)
// We need to find the class that ends just before _CrmQuickReplyTemplate
// Actually, we need to find the closing } of _CrmComercialScreenState
// Let's find it by looking for the last } before _CrmQuickReplyTemplate that's at column 0

for (let i = quickReplyLine - 1; i >= 0; i--) {
  if (lines[i].trim() === '}') {
    stateClassEndLine = i;
    break;
  }
}

console.log('State class line:', stateClassLine);
console.log('State class end line:', stateClassEndLine);
console.log('QuickReplyTemplate line:', quickReplyLine);
console.log('Search icon line:', searchIconLine);
console.log('Mas acciones line:', masAccionesLine);

// The state class ends at stateClassEndLine (the closing })
// We need to insert bot methods BEFORE that line

const botMethods = `
  // ── Bot methods ──────────────────────────────────────────────────────────

  Future<void> _toggleBotPause() async {
    final conversationId = _selectedConversation?.id;
    if (conversationId == null) return;
    setState(() => _botLoading = true);
    try {
      final repo = context.read(crmComercialRepositoryProvider);
      if (_botPaused) {
        await repo.resumeBotForConversation(conversationId);
        setState(() {
          _botPaused = false;
          _botStatus = null;
          _botSkippedReason = null;
        });
      } else {
        await repo.pauseBotForConversation(conversationId);
        setState(() {
          _botPaused = true;
          _botStatus = 'PAUSED';
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cambiar estado del bot: \$e')),
        );
      }
    } finally {
      setState(() => _botLoading = false);
    }
  }

  Future<void> _toggleBotExclude() async {
    final conversationId = _selectedConversation?.id;
    if (conversationId == null) return;
    setState(() => _botLoading = true);
    try {
      final repo = context.read(crmComercialRepositoryProvider);
      if (_isExcluded) {
        await repo.includeNumberForBot(conversationId);
        setState(() => _isExcluded = false);
      } else {
        await repo.excludeNumberForBot(conversationId);
        setState(() => _isExcluded = true);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cambiar exclusion: \$e')),
        );
      }
    } finally {
      setState(() => _botLoading = false);
    }
  }

  Future<void> _suggestBotReply() async {
    final conversationId = _selectedConversation?.id;
    if (conversationId == null) return;
    setState(() => _botLoading = true);
    try {
      final repo = context.read(crmComercialRepositoryProvider);
      final result = await repo.suggestBotReply(conversationId);
      final suggestion = result['suggestion'] as String?;
      if (suggestion != null && suggestion.isNotEmpty && context.mounted) {
        _chatComposerCtrl.text = suggestion;
        _chatComposerCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: suggestion.length),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sugerencia de IA cargada en el compositor'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al obtener sugerencia: \$e')),
        );
      }
    } finally {
      setState(() => _botLoading = false);
    }
  }

  Future<void> _refreshBotStatus() async {
    final conversationId = _selectedConversation?.id;
    if (conversationId == null) return;
    try {
      final repo = context.read(crmComercialRepositoryProvider);
      final status = await repo.getConversationBotStatus(conversationId);
      setState(() {
        _botPaused = status['botPaused'] == true;
        _botStatus = status['botStatus'] as String?;
        _botSkippedReason = status['botSkippedReason'] as String?;
        _isExcluded = status['isExcluded'] == true;
      });
    } catch (_) {
      // Silently fail on refresh
    }
  }
`;

const botStatusBadgeWidget = `

class _BotStatusBadge extends StatelessWidget {
  const _BotStatusBadge({
    required this.botPaused,
    required this.botStatus,
    required this.botSkippedReason,
    required this.isExcluded,
    required this.botLoading,
  });

  final bool botPaused;
  final String? botStatus;
  final String? botSkippedReason;
  final bool isExcluded;
  final bool botLoading;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String tooltip;

    if (botLoading) {
      icon = Icons.smart_toy_outlined;
      color = Colors.grey;
      tooltip = 'Procesando...';
    } else if (isExcluded) {
      icon = Icons.block;
      color = Colors.red;
      tooltip = 'Numero excluido del bot';
    } else if (botPaused) {
      icon = Icons.pause_circle_outline;
      color = Colors.orange;
      tooltip = 'Bot pausado para esta conversacion';
    } else if (botStatus == 'HUMAN_TAKEOVER') {
      icon = Icons.support_agent;
      color = Colors.blue;
      tooltip = 'Agente humano tomo el control';
    } else if (botSkippedReason != null) {
      icon = Icons.skip_next;
      color = Colors.grey;
      tooltip = 'Bot salto: \$botSkippedReason';
    } else {
      icon = Icons.smart_toy;
      color = Colors.green;
      tooltip = 'Bot activo';
    }

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}
`;

// 1. Add bot state variables after _lastConversationPollAt
const stateVarLine = lines.findIndex(l => l.includes('DateTime? _lastConversationPollAt;'));
if (stateVarLine >= 0) {
  const botStateVars = `
  // Bot state
  bool _botPaused = false;
  String? _botStatus;
  String? _botSkippedReason;
  bool _isExcluded = false;
  bool _botLoading = false;
`;
  lines.splice(stateVarLine + 1, 0, botStateVars);
  console.log('Added bot state variables after line', stateVarLine);
}

// 2. Add _BotStatusBadge widget after search icon button
// Recalculate line numbers after splice
let searchIconIdx = -1;
for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes("icon: const Icon(Icons.search_rounded, size: 20),") && i > 5400 && i < 5600) {
    searchIconIdx = i;
    break;
  }
}

if (searchIconIdx >= 0) {
  const badgeWidget = `                if (hasConversation && _selectedConversation != null)
                  _BotStatusBadge(
                    botPaused: _botPaused,
                    botStatus: _botStatus,
                    botSkippedReason: _botSkippedReason,
                    isExcluded: _isExcluded,
                    botLoading: _botLoading,
                  ),`;
  lines.splice(searchIconIdx + 1, 0, badgeWidget);
  console.log('Added BotStatusBadge after search icon at line', searchIconIdx);
}

// 3. Add bot menu items in "Mas acciones" PopupMenuButton
let masAccItemBuilderIdx = -1;
for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes("itemBuilder: (context) => const [")) {
    masAccItemBuilderIdx = i;
    break;
  }
}

if (masAccItemBuilderIdx >= 0) {
  // Find the closing ] of itemBuilder
  let closingBracketIdx = -1;
  for (let i = masAccItemBuilderIdx; i < lines.length; i++) {
    if (lines[i].trim() === '],' && lines[i-1] && lines[i-1].includes('Quitar filtro')) {
      closingBracketIdx = i;
      break;
    }
  }
  
  if (closingBracketIdx >= 0) {
    const botMenuItems = `                            if (_selectedConversation != null) ...[
                              const PopupMenuDivider(),
                              PopupMenuItem<String>(
                                value: 'bot-pause',
                                child: Text(_botPaused
                                    ? 'Reanudar bot'
                                    : 'Pausar bot'),
                              ),
                              PopupMenuItem<String>(
                                value: 'bot-exclude',
                                child: Text(_isExcluded
                                    ? 'Incluir numero en bot'
                                    : 'Excluir numero del bot'),
                              ),
                              PopupMenuItem<String>(
                                value: 'bot-suggest',
                                child: Text('Sugerir respuesta IA'),
                              ),
                            ],`;
        lines.splice(closingBracketIdx, 0, botMenuItems);
        console.log('Added bot menu items before line', closingBracketIdx);
    }
  }
}

// 4. Add bot action handlers in onSelected
let onSelectedIdx = -1;
for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes("onSelected: (value) {")) {
    onSelectedIdx = i;
    break;
  }
}

if (onSelectedIdx >= 0) {
  // Find the closing } of onSelected
  let closeIdx = -1;
  let braceCount = 0;
  let found = false;
  for (let i = onSelectedIdx; i < lines.length && !found; i++) {
    for (let ch of lines[i]) {
      if (ch === '{') braceCount++;
      if (ch === '}') braceCount--;
    }
    if (braceCount === 0 && i > onSelectedIdx) {
      closeIdx = i;
      found = true;
    }
  }
  
  if (closeIdx >= 0) {
    const botHandlers = `                            if (value == 'bot-pause') {
                              _toggleBotPause();
                            }
                            if (value == 'bot-exclude') {
                              _toggleBotExclude();
                            }
                            if (value == 'bot-suggest') {
                              _suggestBotReply();
                            }`;
    lines.splice(closeIdx, 0, botHandlers);
    console.log('Added bot handlers before line', closeIdx);
  }
}

// 5. Add bot methods inside _CrmComercialScreenState before its closing }
// Find the class end line again (recalculated)
let stateEndIdx = -1;
let quickReplyIdx = -1;
for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes('class _CrmQuickReplyTemplate')) {
    quickReplyIdx = i;
    break;
  }
}

// Find the last } before _CrmQuickReplyTemplate that's at column 0 (closing the state class)
for (let i = quickReplyIdx - 1; i >= 0; i--) {
  if (lines[i].trim() === '}') {
    stateEndIdx = i;
    break;
  }
}

if (stateEndIdx >= 0) {
  lines.splice(stateEndIdx, 0, botMethods);
  console.log('Added bot methods before line', stateEndIdx);
}

// 6. Add _BotStatusBadge class before _CrmQuickReplyTemplate
// Recalculate quickReplyIdx
quickReplyIdx = -1;
for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes('class _CrmQuickReplyTemplate')) {
    quickReplyIdx = i;
    break;
  }
}

if (quickReplyIdx >= 0) {
  lines.splice(quickReplyIdx, 0, botStatusBadgeWidget);
  console.log('Added BotStatusBadge class before line', quickReplyIdx);
}

// Also need to change itemBuilder from `const [` to `[` since we have dynamic items
for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes("itemBuilder: (context) => const [") && lines[i].includes('Mas acciones')) {
    // This is the one we need to change
  }
  if (lines[i].includes("itemBuilder: (context) => const [") && i > 5100 && i < 5200) {
    lines[i] = lines[i].replace("itemBuilder: (context) => const [", "itemBuilder: (context) => [");
    console.log('Changed const to non-const for itemBuilder at line', i);
    break;
  }
}

content = lines.join('\n');
fs.writeFileSync(filePath, content, 'utf8');
console.log('File written successfully');
