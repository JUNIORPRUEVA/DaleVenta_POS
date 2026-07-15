import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final chatgptApiSettingsRepositoryProvider =
    Provider<ChatgptApiSettingsRepository>((ref) {
      return ChatgptApiSettingsRepository();
    });

class ChatgptApiSettings {
  final String apiKey;
  final String model;

  const ChatgptApiSettings({required this.apiKey, required this.model});

  factory ChatgptApiSettings.empty() {
    return const ChatgptApiSettings(apiKey: '', model: 'gpt-4o-mini');
  }
}

class ChatgptApiSettingsRepository {
  static const _apiKeyStorageKey = 'chatgpt_api_key_v1';
  static const _modelStorageKey = 'chatgpt_model_v1';

  Future<ChatgptApiSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = (prefs.getString(_apiKeyStorageKey) ?? '').trim();
    final model = (prefs.getString(_modelStorageKey) ?? 'gpt-4o-mini').trim();
    return ChatgptApiSettings(
      apiKey: apiKey,
      model: model.isEmpty ? 'gpt-4o-mini' : model,
    );
  }

  Future<void> saveSettings({
    required String apiKey,
    required String model,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyStorageKey, apiKey.trim());
    await prefs.setString(
      _modelStorageKey,
      model.trim().isEmpty ? 'gpt-4o-mini' : model.trim(),
    );
  }

  Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyStorageKey);
  }
}
