$path = "c:\Users\pc\DEV\PROYECTOS\INTERNO\FULLTECH\apps\fulltech_app\lib\modules\crm_comercial\crm_comercial_screen.dart"
$content = Get-Content -Path $path -Raw

Write-Host "File length: $($content.Length)"

# 1. Add bot state variables after _lastConversationPollAt
$target = 'DateTime? _lastConversationPollAt;'
$replacement = "DateTime? _lastConversationPollAt;`r`n`r`n  // Bot AI state`r`n  bool _botGloballyEnabled = false;`r`n  bool _botConversationPaused = false;`r`n  bool _botNumberExcluded = false;`r`n  String? _botConversationStatus;`r`n  String? _botSkippedReason;`r`n  bool _loadingBotStatus = false;"
if ($content.Contains($target)) {
    $content = $content.Replace($target, $replacement)
    Write-Host "1. Bot state variables added"
} else {
    Write-Host "1. FAILED - target not found"
}

# 2. Add bot status badge before search IconButton
$target2 = "IconButton(`r`n                  tooltip: 'Buscar en conversacion',"
$replacement2 = "if (hasConversation) _BotStatusBadge(`r`n                    botPaused: selectedConversation.botPaused,`r`n                    botStatus: selectedConversation.botStatus,`r`n                    botSkippedReason: selectedConversation.botSkippedReason,`r`n                    isExcluded: selectedConversation.isExcluded,`r`n                    botGloballyEnabled: _botGloballyEnabled,`r`n                  ),`r`n                const SizedBox(width: 4),`r`n                IconButton(`r`n                  tooltip: 'Buscar en conversacion',"
if ($content.Contains($target2)) {
    $content = $content.Replace($target2, $replacement2)
    Write-Host "2. Bot status badge added"
} else {
    Write-Host "2. FAILED - target not found"
}

# 3. Add bot control menu items
$target3 = "itemBuilder: (context) => const [`r`n                    PopupMenuItem<String>(`r`n                      value: 'new-chat',`r`n                      child: Text('Nuevo chat por numero'),`r`n                    ),`r`n                  ],"
$replacement3 = "itemBuilder: (context) => [`r`n                    const PopupMenuItem<String>(`r`n                      value: 'new-chat',`r`n                      child: Text('Nuevo chat por numero'),`r`n                    ),`r`n                    if (hasConversation) ...[`r`n                      PopupMenuDivider(),`r`n                      PopupMenuItem<String>(`r`n                        value: 'bot-pause',`r`n                        child: Text(selectedConversation.botPaused ? 'Reanudar bot' : 'Pausar bot'),`r`n                      ),`r`n                      PopupMenuItem<String>(`r`n                        value: 'bot-exclude',`r`n                        child: Text(selectedConversation.isExcluded ? 'Incluir numero en bot' : 'Excluir numero del bot'),`r`n                      ),`r`n                      PopupMenuItem<String>(`r`n                        value: 'bot-suggest',`r`n                        child: const Text('Sugerir respuesta con bot'),`r`n                      ),`r`n                    ],`r`n                  ],"
if ($content.Contains($target3)) {
    $content = $content.Replace($target3, $replacement3)
    Write-Host "3. Bot menu items added"
} else {
    Write-Host "3. FAILED - target not found"
}

# 4. Add bot action handler
$target4 = "if (value == 'new-chat') {`r`n                      _openNewChatDialog();`r`n                    }"
$replacement4 = "if (value == 'new-chat') {`r`n                      _openNewChatDialog();`r`n                    } else if (value == 'bot-pause') {`r`n                      _toggleBotPause();`r`n                    } else if (value == 'bot-exclude') {`r`n                      _toggleBotExclude();`r`n                    } else if (value == 'bot-suggest') {`r`n                      _suggestBotReply();`r`n                    }"
if ($content.Contains($target4)) {
    $content = $content.Replace($target4, $replacement4)
    Write-Host "4. Bot action handler added"
} else {
    Write-Host "4. FAILED - target not found"
}

# 5. Add bot methods before _CrmTimelineEntry
$target5 = "class _CrmTimelineEntry {"
$replacement5 = "  // --- Bot AI UI methods -------------------------------------------------`r`n`r`n  Future<void> _toggleBotPause() async {`r`n    final conversation = _selectedConversation;`r`n    if (conversation == null) return;`r`n    try {`r`n      final repo = ref.read(crmComercialRepositoryProvider);`r`n      if (conversation.botPaused) {`r`n        await repo.resumeBotForConversation(conversation.id);`r`n      } else {`r`n        await repo.pauseBotForConversation(conversation.id);`r`n      }`r`n      if (!mounted) return;`r`n      setState(() {`r`n        _selectedConversation = conversation.copyWith(`r`n          botPaused: !conversation.botPaused,`r`n        );`r`n      });`r`n    } catch (e) {`r`n      debugPrint('[CRM][Bot] Error toggling bot pause: ' + e.toString());`r`n    }`r`n  }`r`n`r`n  Future<void> _toggleBotExclude() async {`r`n    final conversation = _selectedConversation;`r`n    if (conversation == null) return;`r`n    try {`r`n      final repo = ref.read(crmComercialRepositoryProvider);`r`n      if (conversation.isExcluded) {`r`n        await repo.includeNumberInBot(conversation.id);`r`n      } else {`r`n        await repo.excludeNumberFromBot(conversation.id);`r`n      }`r`n      if (!mounted) return;`r`n      setState(() {`r`n        _selectedConversation = conversation.copyWith(`r`n          isExcluded: !conversation.isExcluded,`r`n        );`r`n      });`r`n    } catch (e) {`r`n      debugPrint('[CRM][Bot] Error toggling bot exclude: ' + e.toString());`r`n    }`r`n  }`r`n`r`n  Future<void> _suggestBotReply() async {`r`n    final conversation = _selectedConversation;`r`n    if (conversation == null) return;`r`n    try {`r`n      final repo = ref.read(crmComercialRepositoryProvider);`r`n      final lastIncoming = _messages`r`n          .where((m) => m.direction.toUpperCase() == 'INCOMING')`r`n          .toList()`r`n          .lastOrNull;`r`n      final result = await repo.suggestBotReply(`r`n        conversation.id,`r`n        lastCustomerMessage: lastIncoming?.body ?? lastIncoming?.caption,`r`n      );`r`n      if (!mounted) return;`r`n      final suggestedText = result['suggestedReply'] as String?;`r`n      if (suggestedText != null && suggestedText.isNotEmpty) {`r`n        _chatComposerCtrl.text = suggestedText;`r`n      }`r`n    } catch (e) {`r`n      debugPrint('[CRM][Bot] Error suggesting bot reply: ' + e.toString());`r`n    }`r`n  }`r`n`r`nclass _BotStatusBadge extends StatelessWidget {`r`n  const _BotStatusBadge({`r`n    required this.botPaused,`r`n    this.botStatus,`r`n    this.botSkippedReason,`r`n    required this.isExcluded,`r`n    required this.botGloballyEnabled,`r`n  });`r`n`r`n  final bool botPaused;`r`n  final String? botStatus;`r`n  final String? botSkippedReason;`r`n  final bool isExcluded;`r`n  final bool botGloballyEnabled;`r`n`r`n  @override`r`n  Widget build(BuildContext context) {`r`n    IconData icon;`r`n    Color color;`r`n    String tooltip;`r`n`r`n    if (!botGloballyEnabled) {`r`n      icon = Icons.power_off_rounded;`r`n      color = const Color(0xFF9CA3AF);`r`n      tooltip = 'Bot desactivado globalmente';`r`n    } else if (isExcluded) {`r`n      icon = Icons.block_rounded;`r`n      color = const Color(0xFFEF4444);`r`n      tooltip = 'Numero excluido del bot';`r`n    } else if (botPaused) {`r`n      icon = Icons.pause_circle_outline_rounded;`r`n      color = const Color(0xFFF59E0B);`r`n      tooltip = 'Bot pausado para esta conversacion';`r`n    } else if (botStatus == 'HUMAN_TAKEOVER') {`r`n      icon = Icons.support_agent_rounded;`r`n      color = const Color(0xFF3B82F6);`r`n      tooltip = 'Humano tomo el control';`r`n    } else {`r`n      icon = Icons.smart_toy_rounded;`r`n      color = const Color(0xFF25D366);`r`n      tooltip = 'Bot activo';`r`n    }`r`n`r`n    return Tooltip(`r`n      message: tooltip,`r`n      child: Container(`r`n        padding: const EdgeInsets.all(4),`r`n        decoration: BoxDecoration(`r`n          color: color.withAlpha(25),`r`n          borderRadius: BorderRadius.circular(8),`r`n        ),`r`n        child: Icon(icon, size: 18, color: color),`r`n      ),`r`n    );`r`n  }`r`n}`r`n`r`nclass _CrmTimelineEntry {"
if ($content.Contains($target5)) {
    $content = $content.Replace($target5, $replacement5)
    Write-Host "5. Bot methods and _BotStatusBadge added"
} else {
    Write-Host "5. FAILED - target not found"
}

Set-Content -Path $path -Value $content -NoNewline
Write-Host "Done - Screen patched successfully"
