const fs = require('fs');
const path = require('path');

const filePath = path.resolve(__dirname, 'apps/fulltech_app/lib/modules/crm_comercial/crm_comercial_screen.dart');
let content = fs.readFileSync(filePath, 'utf8');

console.log(`File length: ${content.length}`);

// ============================================================
// Step 1: Remove the misplaced bot methods (they're between 
// _CrmConversationListItem.build() closing and _CrmQuickReplyTemplate)
// ============================================================

// Find the misplaced bot methods section - it starts with the comment
// "// --- Bot AI UI methods ---" and ends with "}" before "class _CrmQuickReplyTemplate"
const misplacedStart = content.indexOf('// --- Bot AI UI methods -------------------------------------------------');
if (misplacedStart >= 0) {
  // Find the closing "}" of this block - it's followed by blank line then "class _CrmQuickReplyTemplate"
  const afterMisplaced = content.indexOf('class _CrmQuickReplyTemplate', misplacedStart);
  if (afterMisplaced >= 0) {
    // Go back from class _CrmQuickReplyTemplate to find the preceding "}\n\n"
    const blockEnd = content.lastIndexOf('}\n\n', afterMisplaced);
    if (blockEnd >= misplacedStart) {
      // Remove from misplacedStart to blockEnd + 3 (the "}\n\n")
      const before = content.substring(0, misplacedStart);
      const after = content.substring(blockEnd + 3);
      content = before + after;
      console.log('Removed misplaced bot methods');
    }
  }
}

// ============================================================
// Step 2: Find the state class closing brace and insert methods there
// ============================================================

// Find the state class definition
const stateClassStart = content.indexOf('class _CrmComercialScreenState extends ConsumerState<CrmComercialScreen> {');
if (stateClassStart < 0) {
  console.log('ERROR: Could not find state class');
  process.exit(1);
}

// Count braces to find the matching closing brace of the state class
let depth = 0;
let inString = false;
let stringChar = null;
let stateClassEnd = -1;

for (let i = stateClassStart; i < content.length; i++) {
  const ch = content[i];
  const prev = i > 0 ? content[i-1] : '';
  
  // Handle string literals
  if (!inString) {
    if (ch === '"' || ch === "'" || ch === '`') {
      // Check if it's a triple-quoted string
      if (content.substring(i, i+3) === '"""' || content.substring(i, i+3) === "'''") {
        inString = true;
        stringChar = content.substring(i, i+3);
        i += 2;
        continue;
      }
      inString = true;
      stringChar = ch;
      continue;
    }
  } else {
    if (typeof stringChar === 'string' && stringChar.length === 3) {
      // Triple-quoted string
      if (content.substring(i, i+3) === stringChar && prev !== '\\') {
        inString = false;
        stringChar = null;
        i += 2;
        continue;
      }
    } else if (ch === stringChar && prev !== '\\') {
      inString = false;
      stringChar = null;
      continue;
    }
    continue;
  }
  
  // Handle single-line comments
  if (ch === '/' && content[i+1] === '/') {
    while (i < content.length && content[i] !== '\n') i++;
    continue;
  }
  
  // Handle multi-line comments
  if (ch === '/' && content[i+1] === '*') {
    i += 2;
    while (i < content.length && !(content[i] === '*' && content[i+1] === '/')) i++;
    i++;
    continue;
  }
  
  if (ch === '{') depth++;
  if (ch === '}') {
    depth--;
    if (depth === 0) {
      stateClassEnd = i;
      break;
    }
  }
}

if (stateClassEnd < 0) {
  console.log('ERROR: Could not find state class closing brace');
  process.exit(1);
}

console.log(`State class ends at position ${stateClassEnd}`);

// The closing brace is at stateClassEnd. We insert BEFORE it.
const botMethods = `
  // --- Bot AI UI methods -------------------------------------------------

  Future<void> _toggleBotPause() async {
    final conversation = _selectedConversation;
    if (conversation == null) return;
    try {
      final repo = ref.read(crmComercialRepositoryProvider);
      if (conversation.botPaused) {
        await repo.resumeBotForConversation(conversation.id);
      } else {
        await repo.pauseBotForConversation(conversation.id);
      }
      if (!mounted) return;
      setState(() {
        _selectedConversation = conversation.copyWith(
          botPaused: !conversation.botPaused,
        );
      });
    } catch (e) {
      debugPrint('[CRM][Bot] Error toggling bot pause: ' + e.toString());
    }
  }

  Future<void> _toggleBotExclude() async {
    final conversation = _selectedConversation;
    if (conversation == null) return;
    try {
      final repo = ref.read(crmComercialRepositoryProvider);
      if (conversation.isExcluded) {
        await repo.includeNumberInBot(conversation.id);
      } else {
        await repo.excludeNumberFromBot(conversation.id);
      }
      if (!mounted) return;
      setState(() {
        _selectedConversation = conversation.copyWith(
          isExcluded: !conversation.isExcluded,
        );
      });
    } catch (e) {
      debugPrint('[CRM][Bot] Error toggling bot exclude: ' + e.toString());
    }
  }

  Future<void> _suggestBotReply() async {
    final conversation = _selectedConversation;
    if (conversation == null) return;
    try {
      final repo = ref.read(crmComercialRepositoryProvider);
      final lastIncoming = _messages
          .where((m) => m.direction.toUpperCase() == 'INCOMING')
          .toList()
          .lastOrNull;
      final result = await repo.suggestBotReply(
        conversation.id,
        lastCustomerMessage: lastIncoming?.body ?? lastIncoming?.caption,
      );
      if (!mounted) return;
      if (result != null && result['reply'] != null) {
        _setComposerText(result['reply'].toString());
      }
    } catch (e) {
      debugPrint('[CRM][Bot] Error suggesting bot reply: ' + e.toString());
    }
  }
`;

// Insert before the closing brace
content = content.substring(0, stateClassEnd) + botMethods + content.substring(stateClassEnd);

// Write the modified content back
fs.writeFileSync(filePath, content, 'utf8');
console.log('Done - Bot methods inserted inside state class');
