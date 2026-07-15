import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../models/crm_comercial_models.dart';

/// Base de datos local para caché del módulo CRM Comercial.
/// Permite mostrar datos al instante mientras se sincroniza con el servidor.
class CrmComercialLocalDb {
  static final CrmComercialLocalDb instance = CrmComercialLocalDb._init();
  static Database? _database;

  CrmComercialLocalDb._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('crm_comercial_cache.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Tabla de conversaciones
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        contact_name TEXT NOT NULL,
        remote_phone TEXT,
        remote_jid TEXT,
        remote_avatar_url TEXT,
        last_message_at INTEGER,
        last_message_preview TEXT,
        last_message_type TEXT,
        last_message_direction TEXT,
        unread_count INTEGER DEFAULT 0,
        message_count INTEGER DEFAULT 0,
        crm_customer_id TEXT,
        crm_customer_name TEXT,
        crm_customer_status TEXT,
        is_new_contact INTEGER DEFAULT 0,
        can_convert_to_crm INTEGER DEFAULT 0,
        cached_at INTEGER NOT NULL
      )
    ''');

    // Tabla de mensajes
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        direction TEXT NOT NULL,
        message_type TEXT NOT NULL,
        body TEXT,
        caption TEXT,
        media_url TEXT,
        media_mime_type TEXT,
        sender_name TEXT,
        sent_at INTEGER,
        media_storage_key TEXT,
        media_status TEXT,
        original_file_name TEXT,
        media_file_size INTEGER,
        FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
      )
    ''');

    // Índice para buscar mensajes por conversación
    await db.execute('''
      CREATE INDEX idx_messages_conversation ON messages(conversation_id)
    ''');

    // Índice para ordenar conversaciones por fecha
    await db.execute('''
      CREATE INDEX idx_conversations_last_message ON conversations(last_message_at DESC)
    ''');

    // Tabla de clientes CRM
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        nombre TEXT NOT NULL,
        telefono TEXT NOT NULL,
        estado_actual TEXT NOT NULL,
        direccion TEXT,
        ciudad TEXT,
        etiqueta TEXT,
        next_action TEXT,
        next_action_at INTEGER,
        updated_at INTEGER,
        responsable_user_id TEXT,
        responsable_user_nombre TEXT,
        cached_at INTEGER NOT NULL
      )
    ''');

    // Tabla de tareas de seguimiento
    await db.execute('''
      CREATE TABLE followup_tasks (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        title TEXT NOT NULL,
        status TEXT NOT NULL,
        effective_status TEXT NOT NULL,
        priority TEXT NOT NULL,
        description TEXT,
        due_date INTEGER,
        completed_at INTEGER,
        created_at INTEGER,
        assigned_user_id TEXT,
        assigned_user_nombre TEXT,
        created_by_user_id TEXT,
        created_by_user_nombre TEXT,
        completed_by_user_id TEXT,
        completed_by_user_nombre TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');

    // Índice para tareas por cliente
    await db.execute('''
      CREATE INDEX idx_tasks_customer ON followup_tasks(customer_id)
    ''');

    // Índice para tareas pendientes
    await db.execute('''
      CREATE INDEX idx_tasks_effective_status ON followup_tasks(effective_status)
    ''');

    // Tabla de configuraciones
    await db.execute('''
      CREATE TABLE settings (
        id TEXT PRIMARY KEY,
        enabled INTEGER NOT NULL,
        selected_whatsapp_instance_id TEXT,
        selected_whatsapp_instance_name TEXT,
        updated_at INTEGER,
        selected_instance_exists INTEGER,
        warning TEXT,
        real_messages_ready INTEGER,
        cached_at INTEGER NOT NULL
      )
    ''');

    // Tabla de instancias de WhatsApp
    await db.execute('''
      CREATE TABLE whatsapp_instances (
        id TEXT PRIMARY KEY,
        instance_name TEXT NOT NULL,
        status TEXT NOT NULL,
        webhook_enabled INTEGER NOT NULL,
        is_company INTEGER NOT NULL,
        user_id TEXT,
        user_name TEXT,
        user_role TEXT,
        phone_number TEXT
      )
    ''');

    // Tabla de usuarios
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        nombre_completo TEXT NOT NULL,
        role TEXT
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    // Migraciones futuras aquí
    if (oldVersion < 1) {
      await _createDB(db, newVersion);
    }
  }

  // ==================== CONVERSATIONS ====================

  Future<void> saveConversations(
    List<CrmComercialInboxConversation> conversations,
  ) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final c in conversations) {
      batch.insert('conversations', {
        'id': c.id,
        'contact_name': c.contactName,
        'remote_phone': c.remotePhone,
        'remote_jid': c.remoteJid,
        'remote_avatar_url': c.remoteAvatarUrl,
        'last_message_at': c.lastMessageAt?.millisecondsSinceEpoch,
        'last_message_preview': c.lastMessagePreview,
        'last_message_type': c.lastMessageType,
        'last_message_direction': c.lastMessageDirection,
        'unread_count': c.unreadCount,
        'message_count': c.messageCount,
        'crm_customer_id': c.crmCustomerId,
        'crm_customer_name': c.crmCustomerName,
        'crm_customer_status': c.crmCustomerStatus,
        'is_new_contact': c.isNewContact ? 1 : 0,
        'can_convert_to_crm': c.canConvertToCrm ? 1 : 0,
        'cached_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<List<CrmComercialInboxConversation>> getConversations() async {
    final db = await database;
    final maps = await db.query(
      'conversations',
      orderBy: 'last_message_at DESC',
    );

    return maps.map((map) => _conversationFromMap(map)).toList();
  }

  Future<void> deleteAllConversations() async {
    final db = await database;
    await db.delete('conversations');
  }

  // ==================== MESSAGES ====================

  Future<void> saveMessages(
    String conversationId,
    List<CrmComercialInboxMessage> messages,
  ) async {
    final db = await database;
    final batch = db.batch();

    // Primero, eliminar mensajes antiguos de esta conversación
    batch.delete(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );

    for (final m in messages) {
      batch.insert('messages', {
        'id': m.id,
        'conversation_id': conversationId,
        'direction': m.direction,
        'message_type': m.messageType,
        'body': m.body,
        'caption': m.caption,
        'media_url': m.mediaUrl,
        'media_mime_type': m.mediaMimeType,
        'sender_name': m.senderName,
        'sent_at': m.sentAt?.millisecondsSinceEpoch,
        'media_storage_key': m.mediaStorageKey,
        'media_status': m.mediaStatus,
        'original_file_name': m.originalFileName,
        'media_file_size': m.mediaFileSize,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<List<CrmComercialInboxMessage>> getMessages(
    String conversationId,
  ) async {
    final db = await database;
    final maps = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'sent_at ASC',
    );

    return maps.map((map) => _messageFromMap(map)).toList();
  }

  Future<void> saveMessage(
    String conversationId,
    CrmComercialInboxMessage message,
  ) async {
    final db = await database;
    await db.insert('messages', {
      'id': message.id,
      'conversation_id': conversationId,
      'direction': message.direction,
      'message_type': message.messageType,
      'body': message.body,
      'caption': message.caption,
      'media_url': message.mediaUrl,
      'media_mime_type': message.mediaMimeType,
      'sender_name': message.senderName,
      'sent_at': message.sentAt?.millisecondsSinceEpoch,
      'media_storage_key': message.mediaStorageKey,
      'media_status': message.mediaStatus,
      'original_file_name': message.originalFileName,
      'media_file_size': message.mediaFileSize,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==================== CUSTOMERS ====================

  Future<void> saveCustomers(List<CrmComercialCustomer> customers) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final c in customers) {
      batch.insert('customers', {
        'id': c.id,
        'nombre': c.nombre,
        'telefono': c.telefono,
        'estado_actual': c.estadoActual,
        'direccion': c.direccion,
        'ciudad': c.ciudad,
        'etiqueta': c.etiqueta,
        'next_action': c.nextAction,
        'next_action_at': c.nextActionAt?.millisecondsSinceEpoch,
        'updated_at': c.updatedAt?.millisecondsSinceEpoch,
        'responsable_user_id': c.responsable?.id,
        'responsable_user_nombre': c.responsable?.nombreCompleto,
        'cached_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<List<CrmComercialCustomer>> getCustomers() async {
    final db = await database;
    final maps = await db.query('customers');

    return maps.map((map) => _customerFromMap(map)).toList();
  }

  Future<CrmComercialCustomer?> getCustomer(String id) async {
    final db = await database;
    final maps = await db.query('customers', where: 'id = ?', whereArgs: [id]);

    if (maps.isEmpty) return null;
    return _customerFromMap(maps.first);
  }

  // ==================== FOLLOWUP TASKS ====================

  Future<void> saveFollowupTasks(List<CrmComercialFollowupTask> tasks) async {
    final db = await database;
    final batch = db.batch();

    for (final t in tasks) {
      batch.insert('followup_tasks', {
        'id': t.id,
        'customer_id': t.customerId,
        'title': t.title,
        'status': t.status,
        'effective_status': t.effectiveStatus,
        'priority': t.priority,
        'description': t.description,
        'due_date': t.dueDate?.millisecondsSinceEpoch,
        'completed_at': t.completedAt?.millisecondsSinceEpoch,
        'created_at': t.createdAt?.millisecondsSinceEpoch,
        'assigned_user_id': t.assignedTo?.id,
        'assigned_user_nombre': t.assignedTo?.nombreCompleto,
        'created_by_user_id': t.createdBy?.id,
        'created_by_user_nombre': t.createdBy?.nombreCompleto,
        'completed_by_user_id': t.completedBy?.id,
        'completed_by_user_nombre': t.completedBy?.nombreCompleto,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<List<CrmComercialFollowupTask>> getFollowupTasks() async {
    final db = await database;
    final maps = await db.query('followup_tasks');

    return maps.map((map) => _taskFromMap(map)).toList();
  }

  // ==================== SETTINGS ====================

  Future<void> saveSettings(CrmComercialSettings settings) async {
    final db = await database;
    await db.insert('settings', {
      'id': settings.id,
      'enabled': settings.enabled ? 1 : 0,
      'selected_whatsapp_instance_id': settings.selectedWhatsappInstanceId,
      'selected_whatsapp_instance_name': settings.selectedWhatsappInstanceName,
      'updated_at': settings.updatedAt?.millisecondsSinceEpoch,
      'selected_instance_exists': (settings.selectedInstanceExists ?? false)
          ? 1
          : 0,
      'warning': settings.warning,
      'real_messages_ready': (settings.realMessagesReady ?? false) ? 1 : 0,
      'cached_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<CrmComercialSettings?> getSettings() async {
    final db = await database;
    final maps = await db.query('settings', limit: 1);

    if (maps.isEmpty) return null;
    return _settingsFromMap(maps.first);
  }

  // ==================== WHATSAPP INSTANCES ====================

  Future<void> saveWhatsappInstances(
    List<CrmComercialWhatsappInstance> instances,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (final i in instances) {
      batch.insert('whatsapp_instances', {
        'id': i.id,
        'instance_name': i.instanceName,
        'status': i.status,
        'webhook_enabled': i.webhookEnabled ? 1 : 0,
        'is_company': i.isCompany ? 1 : 0,
        'user_id': i.userId,
        'user_name': i.userName,
        'user_role': i.userRole,
        'phone_number': i.phoneNumber,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<List<CrmComercialWhatsappInstance>> getWhatsappInstances() async {
    final db = await database;
    final maps = await db.query('whatsapp_instances');

    return maps.map((map) => _instanceFromMap(map)).toList();
  }

  // ==================== USERS ====================

  Future<void> saveUsers(List<CrmComercialUserRef> users) async {
    final db = await database;
    final batch = db.batch();

    for (final u in users) {
      batch.insert('users', {
        'id': u.id,
        'nombre_completo': u.nombreCompleto,
        'role': u.role,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<List<CrmComercialUserRef>> getUsers() async {
    final db = await database;
    final maps = await db.query('users');

    return maps.map((map) => _userFromMap(map)).toList();
  }

  // ==================== CLEAR CACHE ====================

  Future<void> clearCache() async {
    final db = await database;
    final batch = db.batch();
    batch.delete('messages');
    batch.delete('conversations');
    batch.delete('customers');
    batch.delete('followup_tasks');
    batch.delete('settings');
    batch.delete('whatsapp_instances');
    batch.delete('users');
    await batch.commit(noResult: true);
  }

  // ==================== HELPERS ====================

  CrmComercialInboxConversation _conversationFromMap(Map<String, dynamic> map) {
    return CrmComercialInboxConversation(
      id: map['id'] as String,
      contactName: map['contact_name'] as String,
      remotePhone: map['remote_phone'] as String?,
      remoteJid: map['remote_jid'] as String?,
      remoteAvatarUrl: map['remote_avatar_url'] as String?,
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_message_at'] as int)
          : null,
      lastMessagePreview: map['last_message_preview'] as String?,
      lastMessageType: map['last_message_type'] as String?,
      lastMessageDirection: map['last_message_direction'] as String?,
      unreadCount: map['unread_count'] as int? ?? 0,
      messageCount: map['message_count'] as int? ?? 0,
      crmCustomerId: map['crm_customer_id'] as String?,
      crmCustomerName: map['crm_customer_name'] as String?,
      crmCustomerStatus: map['crm_customer_status'] as String?,
      isNewContact: (map['is_new_contact'] as int?) == 1,
      canConvertToCrm: (map['can_convert_to_crm'] as int?) == 1,
    );
  }

  CrmComercialInboxMessage _messageFromMap(Map<String, dynamic> map) {
    return CrmComercialInboxMessage(
      id: map['id'] as String,
      direction: map['direction'] as String,
      messageType: map['message_type'] as String,
      body: map['body'] as String?,
      caption: map['caption'] as String?,
      mediaUrl: map['media_url'] as String?,
      mediaMimeType: map['media_mime_type'] as String?,
      senderName: map['sender_name'] as String?,
      sentAt: map['sent_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['sent_at'] as int)
          : null,
      mediaStorageKey: map['media_storage_key'] as String?,
      mediaStatus: map['media_status'] as String?,
      originalFileName: map['original_file_name'] as String?,
      mediaFileSize: map['media_file_size'] as int?,
    );
  }

  CrmComercialCustomer _customerFromMap(Map<String, dynamic> map) {
    return CrmComercialCustomer(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      telefono: map['telefono'] as String,
      estadoActual: map['estado_actual'] as String,
      direccion: map['direccion'] as String?,
      ciudad: map['ciudad'] as String?,
      etiqueta: map['etiqueta'] as String?,
      nextAction: map['next_action'] as String?,
      nextActionAt: map['next_action_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['next_action_at'] as int)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
      responsable: map['responsable_user_id'] != null
          ? CrmComercialUserRef(
              id: map['responsable_user_id'] as String,
              nombreCompleto: map['responsable_user_nombre'] as String? ?? '',
            )
          : null,
    );
  }

  CrmComercialFollowupTask _taskFromMap(Map<String, dynamic> map) {
    return CrmComercialFollowupTask(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      title: map['title'] as String,
      status: map['status'] as String,
      effectiveStatus: map['effective_status'] as String,
      priority: map['priority'] as String,
      description: map['description'] as String?,
      dueDate: map['due_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['due_date'] as int)
          : null,
      completedAt: map['completed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int)
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : null,
      assignedTo: map['assigned_user_id'] != null
          ? CrmComercialUserRef(
              id: map['assigned_user_id'] as String,
              nombreCompleto: map['assigned_user_nombre'] as String? ?? '',
            )
          : null,
      createdBy: map['created_by_user_id'] != null
          ? CrmComercialUserRef(
              id: map['created_by_user_id'] as String,
              nombreCompleto: map['created_by_user_nombre'] as String? ?? '',
            )
          : null,
      completedBy: map['completed_by_user_id'] != null
          ? CrmComercialUserRef(
              id: map['completed_by_user_id'] as String,
              nombreCompleto: map['completed_by_user_nombre'] as String? ?? '',
            )
          : null,
    );
  }

  CrmComercialSettings _settingsFromMap(Map<String, dynamic> map) {
    return CrmComercialSettings(
      id: map['id'] as String? ?? 'global',
      enabled: (map['enabled'] as int?) == 1,
      selectedWhatsappInstanceId:
          map['selected_whatsapp_instance_id'] as String?,
      selectedWhatsappInstanceName:
          map['selected_whatsapp_instance_name'] as String?,
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
      selectedInstanceExists: map['selected_instance_exists'] == 1,
      warning: map['warning'] as String?,
      realMessagesReady: map['real_messages_ready'] == 1,
    );
  }

  CrmComercialWhatsappInstance _instanceFromMap(Map<String, dynamic> map) {
    return CrmComercialWhatsappInstance(
      id: map['id'] as String,
      instanceName: map['instance_name'] as String,
      status: map['status'] as String,
      webhookEnabled: (map['webhook_enabled'] as int?) == 1,
      isCompany: (map['is_company'] as int?) == 1,
      userId: map['user_id'] as String?,
      userName: map['user_name'] as String?,
      userRole: map['user_role'] as String?,
      phoneNumber: map['phone_number'] as String?,
    );
  }

  CrmComercialUserRef _userFromMap(Map<String, dynamic> map) {
    return CrmComercialUserRef(
      id: map['id'] as String,
      nombreCompleto: map['nombre_completo'] as String,
      role: map['role'] as String?,
    );
  }

  /// Cierra la base de datos (útil para testing o cleanup)
  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
  }
}
