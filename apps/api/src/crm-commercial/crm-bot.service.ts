import {
  Injectable,
  Logger,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { WhatsappService } from '../whatsapp/whatsapp.service';
import { AiAssistantService } from '../ai-assistant/ai-assistant.service';
import { normalizeWhatsappPhone } from '../whatsapp-inbox/whatsapp-identity.util';
import {
  Role,
  WhatsappMessageDirection,
  WhatsappMessageType,
} from '@prisma/client';

type AuthUser = { id: string; role: Role };

export enum BotSkipReason {
  BOT_DISABLED = 'BOT_DISABLED',
  CONVERSATION_PAUSED = 'CONVERSATION_PAUSED',
  NUMBER_EXCLUDED = 'NUMBER_EXCLUDED',
  HUMAN_TAKEOVER = 'HUMAN_TAKEOVER',
  HUMAN_TAKEOVER_ACTIVE = 'HUMAN_TAKEOVER_ACTIVE',
  MISSING_API_KEY = 'MISSING_API_KEY',
  SELF_MESSAGE = 'SELF_MESSAGE',
  DUPLICATE_MESSAGE = 'DUPLICATE_MESSAGE',
  CLIENT_REQUESTED_HUMAN = 'CLIENT_REQUESTED_HUMAN',
  AI_ERROR = 'AI_ERROR',
  NO_TEXT_CONTENT = 'NO_TEXT_CONTENT',
}

export enum BotConversationStatus {
  ACTIVE = 'ACTIVE',
  PAUSED = 'PAUSED',
  HUMAN_TAKEOVER = 'HUMAN_TAKEOVER',
  DISABLED_FOR_NUMBER = 'DISABLED_FOR_NUMBER',
}

const DEFAULT_SYSTEM_PROMPT = `Eres un asesor comercial profesional de FULLTECH SRL, una empresa dominicana de tecnología y seguridad.

INSTRUCCIONES DE COMPORTAMIENTO:
- Responde como una persona real, no como un robot.
- Ayuda al cliente a elegir productos o servicios de forma natural.
- Haz preguntas útiles cuando falten datos.
- Convence de forma natural, sin sonar a guion.
- Mantén respuestas breves cuando sea necesario.
- Mantén un tono dominicano profesional y amigable.
- Guía al cliente hacia cotización, visita, instalación, compra o contacto humano según el caso.
- Respeta horarios, ubicación, métodos de pago y políticas de la empresa.
- Reconoce cuándo debes transferir a un humano.

REGLAS IMPORTANTES:
- No inventes precios si no están en la información disponible.
- Si no sabes algo, responde de forma natural y ofrece consultar con el equipo.
- No digas "soy una IA" a menos que te pregunten directamente.
- No uses lenguaje técnico innecesario.
- No prometas cosas que la empresa no ofrece.
- No cierres ventas con datos incompletos.
- Si el cliente quiere comprar, pide los datos necesarios: nombre, teléfono, ubicación, producto/servicio, forma de pago.
- Si el cliente está molesto, responde con calma y ofrece ayuda humana.
- Si el cliente pide hablar con una persona, responde amablemente y marca la conversación para atención humana.`;

const DEFAULT_BUSINESS_CONTEXT = `FULLTECH SRL - Empresa dominicana de tecnología y seguridad.

SERVICIOS PRINCIPALES:
- Cámaras de seguridad (instalación y venta)
- Motores de portones (eléctricos y automáticos)
- Alarmas residenciales y comerciales
- Cercos eléctricos
- Intercom y sistemas de acceso
- Puntos de venta (sistemas POS)
- Tecnología en general`;

function asStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string')
    : [];
}

@Injectable()
export class CrmBotService {
  private readonly logger = new Logger(CrmBotService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly whatsappService: WhatsappService,
    private readonly aiAssistantService: AiAssistantService,
  ) {}

  private getCompanyId(): string {
    return process.env.COMPANY_ID ?? '00000000-0000-0000-0000-000000000001';
  }

  private isAdmin(user: AuthUser): boolean {
    return user.role === Role.ADMIN;
  }

  private canWrite(user: AuthUser): boolean {
    return user.role === Role.ADMIN;
  }

  // ==================== BOT SETTINGS ====================

  async getBotSettings(user: AuthUser) {
    if (!this.isAdmin(user)) {
      throw new BadRequestException('Solo ADMIN puede ver la configuración del bot');
    }

    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: {
        openAiApiKey: true,
        openAiModel: true,
        companyName: true,
        address: true,
        businessHours: true,
        bankAccounts: true,
        gpsLocationUrl: true,
        phone: true,
        phonePreferential: true,
      },
    });

    const crmSettings = await this.prisma.crmCommercialSetting.upsert({
      where: { id: 'global' },
      create: { id: 'global' },
      update: {},
    });

    return {
      botEnabled: crmSettings.botEnabled ?? false,
      botModel: appConfig?.openAiModel ?? 'gpt-4o-mini',
      botSystemPrompt: crmSettings.botSystemPrompt || DEFAULT_SYSTEM_PROMPT,
      businessContext: crmSettings.businessContext || DEFAULT_BUSINESS_CONTEXT,
      autoReplyDelaySeconds: crmSettings.autoReplyDelaySeconds ?? 2,
      humanTakeoverMinutes: crmSettings.humanTakeoverMinutes ?? 30,
      botDefaultStatus: crmSettings.botDefaultStatus ?? 'ACTIVE',
      excludedNumbers: crmSettings.botExcludedNumbers ?? [],
      allowedChannels: crmSettings.botAllowedChannels ?? ['WHATSAPP'],
      aiConfigured: !!appConfig?.openAiApiKey,
      companyName: appConfig?.companyName ?? '',
      address: appConfig?.address ?? '',
      businessHours: appConfig?.businessHours ?? '',
      gpsLocationUrl: appConfig?.gpsLocationUrl ?? '',
      phone: appConfig?.phone ?? '',
      phonePreferential: appConfig?.phonePreferential ?? '',
    };
  }

  async updateBotSettings(user: AuthUser, dto: any) {
    if (!this.isAdmin(user)) {
      throw new BadRequestException('Solo ADMIN puede actualizar la configuración del bot');
    }

    const data: any = {};
    if (dto.botEnabled !== undefined) data.botEnabled = dto.botEnabled;
    if (dto.botSystemPrompt !== undefined) data.botSystemPrompt = dto.botSystemPrompt;
    if (dto.businessContext !== undefined) data.businessContext = dto.businessContext;
    if (dto.autoReplyDelaySeconds !== undefined) data.autoReplyDelaySeconds = dto.autoReplyDelaySeconds;
    if (dto.humanTakeoverMinutes !== undefined) data.humanTakeoverMinutes = dto.humanTakeoverMinutes;
    if (dto.botDefaultStatus !== undefined) data.botDefaultStatus = dto.botDefaultStatus;
    if (dto.excludedNumbers !== undefined) data.botExcludedNumbers = dto.excludedNumbers;
    if (dto.allowedChannels !== undefined) data.botAllowedChannels = dto.allowedChannels;

    await this.prisma.crmCommercialSetting.upsert({
      where: { id: 'global' },
      create: { id: 'global', ...data },
      update: data,
    });

    return this.getBotSettings(user);
  }

  // ==================== CONVERSATION BOT CONTROL ====================

  async getConversationBotStatus(user: AuthUser, conversationId: string) {
    if (!this.canWrite(user)) {
      throw new BadRequestException('No tienes permisos');
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      select: {
        id: true,
        remoteJid: true,
        remotePhone: true,
        botPaused: true,
        botPausedAt: true,
        botPausedByUserId: true,
        botPauseReason: true,
        assignedHumanUserId: true,
        lastHumanMessageAt: true,
        botLastReplyAt: true,
        botSkippedReason: true,
      },
    });

    if (!conversation) {
      throw new NotFoundException('Conversación no encontrada');
    }

    const settings = await this.getBotSettings(user);
    const phone = conversation.remotePhone || conversation.remoteJid;
    const normalizedPhone = phone ? normalizeWhatsappPhone(phone) ?? phone.replace(/\D/g, '') : '';
    const excludedNumbers = asStringArray(settings.excludedNumbers);
    const isExcluded = excludedNumbers.some(
      (excluded: string) => normalizedPhone.includes(excluded.replace(/\D/g, '')) || excluded.replace(/\D/g, '').includes(normalizedPhone),
    );

    let status: string;
    if (!settings.botEnabled) {
      status = BotConversationStatus.DISABLED_FOR_NUMBER;
    } else if (conversation.botPaused) {
      status = BotConversationStatus.PAUSED;
    } else if (conversation.assignedHumanUserId) {
      status = BotConversationStatus.HUMAN_TAKEOVER;
    } else if (isExcluded) {
      status = BotConversationStatus.DISABLED_FOR_NUMBER;
    } else {
      status = BotConversationStatus.ACTIVE;
    }

    return {
      conversationId: conversation.id,
      botStatus: status,
      botPaused: conversation.botPaused ?? false,
      botPausedAt: conversation.botPausedAt,
      botPausedByUserId: conversation.botPausedByUserId,
      botPauseReason: conversation.botPauseReason,
      assignedHumanUserId: conversation.assignedHumanUserId,
      lastHumanMessageAt: conversation.lastHumanMessageAt,
      botLastReplyAt: conversation.botLastReplyAt,
      botSkippedReason: conversation.botSkippedReason,
      isExcluded,
      globalBotEnabled: settings.botEnabled,
    };
  }

  async pauseBotForConversation(user: AuthUser, conversationId: string, reason?: string) {
    if (!this.canWrite(user)) {
      throw new BadRequestException('No tienes permisos');
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      select: { id: true },
    });

    if (!conversation) {
      throw new NotFoundException('Conversación no encontrada');
    }

    await this.prisma.whatsappConversation.update({
      where: { id: conversationId },
      data: {
        botPaused: true,
        botPausedAt: new Date(),
        botPausedByUserId: user.id,
        botPauseReason: reason || null,
      },
    });

    this.logger.log(`Bot pausado para conversación ${conversationId} por usuario ${user.id}. Razón: ${reason || 'No especificada'}`);

    return { ok: true, message: 'Bot pausado para esta conversación' };
  }

  async resumeBotForConversation(user: AuthUser, conversationId: string) {
    if (!this.canWrite(user)) {
      throw new BadRequestException('No tienes permisos');
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      select: { id: true },
    });

    if (!conversation) {
      throw new NotFoundException('Conversación no encontrada');
    }

    await this.prisma.whatsappConversation.update({
      where: { id: conversationId },
      data: {
        botPaused: false,
        botPausedAt: null,
        botPausedByUserId: null,
        botPauseReason: null,
        assignedHumanUserId: null,
        botSkippedReason: null,
      },
    });

    this.logger.log(`Bot reactivado para conversación ${conversationId} por usuario ${user.id}`);

    return { ok: true, message: 'Bot reactivado para esta conversación' };
  }

  async excludeNumber(user: AuthUser, conversationId: string) {
    if (!this.canWrite(user)) {
      throw new BadRequestException('No tienes permisos');
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      select: { id: true, remotePhone: true, remoteJid: true },
    });

    if (!conversation) {
      throw new NotFoundException('Conversación no encontrada');
    }

    const phone = conversation.remotePhone || conversation.remoteJid;
    const normalizedPhone = phone ? normalizeWhatsappPhone(phone) ?? phone.replace(/\D/g, '') : '';

    if (!normalizedPhone) {
      throw new BadRequestException('No se pudo determinar el número de teléfono');
    }

    const settings = await this.prisma.crmCommercialSetting.upsert({
      where: { id: 'global' },
      create: { id: 'global', botExcludedNumbers: [normalizedPhone] },
      update: {},
    });

    const currentExcluded = (settings.botExcludedNumbers as string[]) ?? [];
    if (!currentExcluded.includes(normalizedPhone)) {
      await this.prisma.crmCommercialSetting.update({
        where: { id: 'global' },
        data: { botExcludedNumbers: [...currentExcluded, normalizedPhone] },
      });
    }

    this.logger.log(`Número ${normalizedPhone} excluido del bot por usuario ${user.id}`);

    return { ok: true, message: 'Número excluido del bot', phone: normalizedPhone };
  }

  async includeNumber(user: AuthUser, conversationId: string) {
    if (!this.canWrite(user)) {
      throw new BadRequestException('No tienes permisos');
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      select: { id: true, remotePhone: true, remoteJid: true },
    });

    if (!conversation) {
      throw new NotFoundException('Conversación no encontrada');
    }

    const phone = conversation.remotePhone || conversation.remoteJid;
    const normalizedPhone = phone ? normalizeWhatsappPhone(phone) ?? phone.replace(/\D/g, '') : '';

    if (!normalizedPhone) {
      throw new BadRequestException('No se pudo determinar el número de teléfono');
    }

    const settings = await this.prisma.crmCommercialSetting.upsert({
      where: { id: 'global' },
      create: { id: 'global' },
      update: {},
    });

    const currentExcluded = (settings.botExcludedNumbers as string[]) ?? [];
    const filtered = currentExcluded.filter((num: string) => {
      const cleanNum = num.replace(/\D/g, '');
      const cleanPhone = normalizedPhone.replace(/\D/g, '');
      return cleanNum !== cleanPhone && !cleanPhone.includes(cleanNum) && !cleanNum.includes(cleanPhone);
    });

    await this.prisma.crmCommercialSetting.update({
      where: { id: 'global' },
      data: { botExcludedNumbers: filtered },
    });

    this.logger.log(`Número ${normalizedPhone} incluido nuevamente en el bot por usuario ${user.id}`);

    return { ok: true, message: 'Número incluido nuevamente en el bot', phone: normalizedPhone };
  }

  // ==================== SUGGEST REPLY (no envía) ====================

  async suggestReply(user: AuthUser, conversationId: string, dto?: { lastCustomerMessage?: string }) {
    if (!this.canWrite(user)) {
      throw new BadRequestException('No tienes permisos para usar el bot');
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      select: {
        id: true,
        remoteJid: true,
        remotePhone: true,
        remoteName: true,
      },
    });

    if (!conversation) {
      throw new NotFoundException('Conversación no encontrada');
    }

    // Obtener mensajes recientes
    const recentMessages = await this.prisma.whatsappMessage.findMany({
      where: { conversationId },
      orderBy: { sentAt: 'desc' },
      take: 20,
      select: {
        id: true,
        direction: true,
        body: true,
        caption: true,
        senderName: true,
        sentAt: true,
        aiGenerated: true,
      },
    });

    // Invertir para orden cronológico
    recentMessages.reverse();

    const normalizedRecent = recentMessages
      .map((msg) => {
        const text = (msg.body ?? msg.caption ?? '').toString().trim();
        if (!text) return null;
        return {
          direction: msg.direction.toString().toUpperCase(),
          text,
          senderName: msg.senderName,
          aiGenerated: msg.aiGenerated ?? false,
        };
      })
      .filter((row): row is { direction: string; text: string; senderName: string | null; aiGenerated: boolean } => !!row);

    // Encontrar último mensaje del cliente
    let lastCustomerMessage = (dto?.lastCustomerMessage ?? '').trim();
    if (!lastCustomerMessage) {
      for (let i = normalizedRecent.length - 1; i >= 0; i--) {
        if (normalizedRecent[i].direction === 'INCOMING' && !normalizedRecent[i].aiGenerated) {
          lastCustomerMessage = normalizedRecent[i].text;
          break;
        }
      }
    }

    if (!lastCustomerMessage) {
      throw new BadRequestException('No hay un mensaje reciente del cliente para analizar');
    }

    // Obtener contexto
    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: {
        companyName: true,
        address: true,
        gpsLocationUrl: true,
        businessHours: true,
        bankAccounts: true,
        openAiModel: true,
      },
    });

    const crmSettings = await this.prisma.crmCommercialSetting.upsert({
      where: { id: 'global' },
      create: { id: 'global' },
      update: {},
    });

    const systemPrompt = crmSettings.botSystemPrompt || DEFAULT_SYSTEM_PROMPT;
    const businessContext = crmSettings.businessContext || DEFAULT_BUSINESS_CONTEXT;
    const model = appConfig?.openAiModel ?? 'gpt-4o-mini';

    // Construir contexto para IA
    const contextMessages = normalizedRecent.slice(-12).map((m) => ({
      role: m.direction === 'INCOMING' ? ('user' as const) : ('assistant' as const),
      content: m.text,
    }));

    const systemMessage = `${systemPrompt}\n\nINFORMACIÓN DE LA EMPRESA:\n${businessContext}\n\nUBICACIÓN: ${appConfig?.address || 'No configurada'}\nHORARIO: ${appConfig?.businessHours || 'No configurado'}\nGPS: ${appConfig?.gpsLocationUrl || ''}`;

    try {
      const startTime = Date.now();
      const result = await this.aiAssistantService.suggestCrmCommercialReply({
        lastCustomerMessage,
        recentMessages: normalizedRecent.map((m) => ({ direction: m.direction, text: m.text })),
        crmStatus: 'NUEVO',
        customerInfo: {
          name: conversation.remoteName || '',
          phone: conversation.remotePhone || '',
        },
        availableBusinessData: {
          location: appConfig?.address || '',
          businessHours: appConfig?.businessHours || '',
          bankAccounts: [],
          catalogSummary: null,
          libraryItems: [],
        },
      });
      const duration = Date.now() - startTime;

      this.logger.log(`Sugerencia generada para conversación ${conversationId} en ${duration}ms. Confianza: ${result.confidence}`);

      return {
        intent: result.intent,
        suggestedReply: result.suggestedReply,
        nextAction: result.nextAction,
        missingData: result.missingData,
        confidence: result.confidence,
        dataUsed: result.dataUsed,
        aiConfigured: true,
        modelUsed: model,
        durationMs: duration,
      };
    } catch (error) {
      this.logger.error(`Error generando sugerencia para conversación ${conversationId}: ${error instanceof Error ? error.message : String(error)}`);
      throw new BadRequestException('Error al generar sugerencia con IA');
    }
  }

  // ==================== SEND AI REPLY (genera, guarda y envía) ====================

  async sendAiReply(user: AuthUser, conversationId: string, dto?: { lastCustomerMessage?: string }) {
    if (!this.canWrite(user)) {
      throw new BadRequestException('No tienes permisos para usar el bot');
    }

    // Primero obtener sugerencia
    const suggestion = await this.suggestReply(user, conversationId, dto);

    if (!suggestion.suggestedReply) {
      throw new BadRequestException('No se pudo generar una respuesta');
    }

    // Enviar mensaje
    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      select: {
        id: true,
        instanceId: true,
        remoteJid: true,
      },
    });

    if (!conversation) {
      throw new NotFoundException('Conversación no encontrada');
    }

    // Obtener instancia
    const waInstance = await this.prisma.userWhatsappInstance.findUnique({
      where: { id: conversation.instanceId },
      select: { instanceName: true },
    });

    if (!waInstance) {
      throw new BadRequestException('Instancia de WhatsApp no encontrada');
    }

    // Enviar por WhatsApp
    let evolutionMessageId: string | undefined;
    try {
      const sendResult = await this.whatsappService.sendTextMessage(
        waInstance.instanceName,
        conversation.remoteJid,
        suggestion.suggestedReply,
      );
      evolutionMessageId = this.extractEvolutionMessageId(sendResult);
    } catch (error) {
      this.logger.error(`Error enviando mensaje IA a ${conversationId}: ${error instanceof Error ? error.message : String(error)}`);
      throw new BadRequestException('Error al enviar el mensaje por WhatsApp');
    }

    // Guardar mensaje en BD
    const savedMessage = await this.prisma.whatsappMessage.create({
      data: {
        conversationId,
        evolutionId: evolutionMessageId ?? null,
        direction: WhatsappMessageDirection.OUTGOING,
        messageType: WhatsappMessageType.CONVERSATION,
        body: suggestion.suggestedReply,
        senderName: 'Bot IA',
        sentAt: new Date(),
        aiGenerated: true,
        aiModel: suggestion.modelUsed ?? null,
        aiPromptVersion: '1.0',
      },
    });

    // Actualizar conversación
    await this.prisma.whatsappConversation.update({
      where: { id: conversationId },
      data: {
        botLastReplyAt: new Date(),
        lastMessageAt: new Date(),
        unreadCount: 0,
      },
    });

    this.logger.log(`Respuesta IA enviada a conversación ${conversationId}. Mensaje: ${savedMessage.id}`);

    return {
      ok: true,
      messageId: savedMessage.id,
      text: suggestion.suggestedReply,
      intent: suggestion.intent,
      confidence: suggestion.confidence,
      modelUsed: suggestion.modelUsed,
      durationMs: suggestion.durationMs,
    };
  }

  // ==================== AUTO-RESPONDER (llamado desde webhook) ====================

  async evaluateAndRespond(conversationId: string, messageBody: string, messageId: string) {
    this.logger.log(`Evaluando mensaje ${messageId} en conversación ${conversationId} para respuesta automática`);

    // 1. Verificar configuración global
    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: { openAiApiKey: true, openAiModel: true },
    });

    if (!appConfig?.openAiApiKey) {
      await this.updateBotSkipReason(conversationId, BotSkipReason.MISSING_API_KEY);
      this.logger.warn(`Bot saltado: MISSING_API_KEY para conversación ${conversationId}`);
      return { responded: false, reason: BotSkipReason.MISSING_API_KEY };
    }

    const crmSettings = await this.prisma.crmCommercialSetting.upsert({
      where: { id: 'global' },
      create: { id: 'global' },
      update: {},
    });

    // 2. Verificar si el bot está habilitado globalmente
    if (!crmSettings.botEnabled) {
      await this.updateBotSkipReason(conversationId, BotSkipReason.BOT_DISABLED);
      this.logger.log(`Bot saltado: BOT_DISABLED para conversación ${conversationId}`);
      return { responded: false, reason: BotSkipReason.BOT_DISABLED };
    }

    // 3. Obtener conversación
    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      select: {
        id: true,
        remoteJid: true,
        remotePhone: true,
        botPaused: true,
        assignedHumanUserId: true,
        lastHumanMessageAt: true,
        botLastReplyAt: true,
      },
    });

    if (!conversation) {
      return { responded: false, reason: 'CONVERSATION_NOT_FOUND' };
    }

    // 4. Verificar si la conversación está pausada
    if (conversation.botPaused) {
      await this.updateBotSkipReason(conversationId, BotSkipReason.CONVERSATION_PAUSED);
      this.logger.log(`Bot saltado: CONVERSATION_PAUSED para conversación ${conversationId}`);
      return { responded: false, reason: BotSkipReason.CONVERSATION_PAUSED };
    }

    // 5. Verificar si el número está excluido
    const phone = conversation.remotePhone || conversation.remoteJid;
    const normalizedPhone = phone ? normalizeWhatsappPhone(phone) ?? phone.replace(/\D/g, '') : '';
    const excludedNumbers = asStringArray(crmSettings.botExcludedNumbers);
    const isExcluded = excludedNumbers.some((excluded: string) => {
      const cleanExcluded = excluded.replace(/\D/g, '');
      const cleanPhone = normalizedPhone.replace(/\D/g, '');
      return cleanExcluded && cleanPhone && (cleanPhone.includes(cleanExcluded) || cleanExcluded.includes(cleanPhone));
    });

    if (isExcluded) {
      await this.updateBotSkipReason(conversationId, BotSkipReason.NUMBER_EXCLUDED);
      this.logger.log(`Bot saltado: NUMBER_EXCLUDED para conversación ${conversationId}`);
      return { responded: false, reason: BotSkipReason.NUMBER_EXCLUDED };
    }

    // 6. Verificar human takeover
    if (conversation.assignedHumanUserId) {
      await this.updateBotSkipReason(conversationId, BotSkipReason.HUMAN_TAKEOVER);
      this.logger.log(`Bot saltado: HUMAN_TAKEOVER para conversación ${conversationId}`);
      return { responded: false, reason: BotSkipReason.HUMAN_TAKEOVER };
    }

    // 7. Verificar si un humano respondió recientemente
    const takeoverMinutes = crmSettings.humanTakeoverMinutes ?? 30;
    if (conversation.lastHumanMessageAt) {
      const elapsed = Date.now() - conversation.lastHumanMessageAt.getTime();
      if (elapsed < takeoverMinutes * 60 * 1000) {
        await this.updateBotSkipReason(conversationId, BotSkipReason.HUMAN_TAKEOVER);
        this.logger.log(`Bot saltado: HUMAN_TAKEOVER_ACTIVE (humano respondió hace ${Math.round(elapsed / 60000)}min) para conversación ${conversationId}`);
        return { responded: false, reason: BotSkipReason.HUMAN_TAKEOVER_ACTIVE };
      }
    }

    // 8. Verificar si el cliente pidió un humano
    const lowerBody = messageBody.toLowerCase();
    const humanRequestPatterns = [
      'hablar con una persona', 'hablar con alguien', 'atención humana',
      'quiero hablar con', 'comunicame con', 'pásame con', 'transferir',
      'agente humano', 'representante', 'asesor humano', 'persona real',
      'hablar con un agente', 'quiero que me atienda una persona',
      'me puedes pasar con', 'necesito hablar con un',
    ];
    const requestedHuman = humanRequestPatterns.some((pattern) => lowerBody.includes(pattern));

    if (requestedHuman) {
      // Responder amablemente y pausar
      const humanReply = 'Entendido, con gusto te comunico con uno de nuestros asesores humanos para que te pueda ayudar de manera más personalizada. En un momento alguien de nuestro equipo te atenderá. ¡Gracias por tu paciencia! 🙌';
      
      await this.sendBotMessage(conversationId, humanReply, appConfig.openAiModel ?? 'gpt-4o-mini');
      await this.pauseBotForConversationInternal(conversationId, 'Cliente solicitó atención humana');
      
      this.logger.log(`Bot respondió y se pausó: CLIENT_REQUESTED_HUMAN para conversación ${conversationId}`);
      return { responded: true, reason: 'CLIENT_REQUESTED_HUMAN', message: humanReply };
    }

    // 9. Generar respuesta con IA
    try {
      const delaySeconds = crmSettings.autoReplyDelaySeconds ?? 2;
      if (delaySeconds > 0) {
        await this.sleep(delaySeconds * 1000);
      }

      const systemPrompt = crmSettings.botSystemPrompt || DEFAULT_SYSTEM_PROMPT;
      const businessContext = crmSettings.businessContext || DEFAULT_BUSINESS_CONTEXT;

      // Obtener historial reciente
      const recentMessages = await this.prisma.whatsappMessage.findMany({
        where: { conversationId },
        orderBy: { sentAt: 'desc' },
        take: 15,
        select: {
          direction: true,
          body: true,
          caption: true,
          aiGenerated: true,
          sentAt: true,
        },
      });

      recentMessages.reverse();

      const contextLines = recentMessages
        .map((msg) => {
          const text = (msg.body ?? msg.caption ?? '').trim();
          if (!text) return null;
          const prefix = msg.direction === 'INCOMING' ? 'Cliente' : msg.aiGenerated ? 'Bot IA' : 'Asesor';
          return `${prefix}: ${text}`;
        })
        .filter((line): line is string => !!line)
        .slice(-10);

      const systemMessage = `${systemPrompt}\n\nINFORMACIÓN DE LA EMPRESA:\n${businessContext}\n\nCONTEXTO DE LA CONVERSACIÓN:\n${contextLines.join('\n')}\n\nCliente: ${messageBody}\n\nResponde como asesor comercial:`;

      const startTime = Date.now();
      const aiResponse = await this.aiAssistantService.generateText(systemMessage);
      const duration = Date.now() - startTime;

      if (!aiResponse || !aiResponse.trim()) {
        throw new Error('Respuesta vacía de la IA');
      }

      // Enviar mensaje
      await this.sendBotMessage(conversationId, aiResponse.trim(), appConfig.openAiModel ?? 'gpt-4o-mini');

      this.logger.log(`Respuesta automática enviada a conversación ${conversationId} en ${duration}ms`);

      return {
        responded: true,
        reason: 'AI_RESPONSE',
        message: aiResponse.trim(),
        durationMs: duration,
        modelUsed: appConfig.openAiModel ?? 'gpt-4o-mini',
      };
    } catch (error) {
      this.logger.error(`Error generando respuesta IA para conversación ${conversationId}: ${error instanceof Error ? error.message : String(error)}`);
      await this.updateBotSkipReason(conversationId, BotSkipReason.AI_ERROR);
      return { responded: false, reason: BotSkipReason.AI_ERROR, error: error instanceof Error ? error.message : String(error) };
    }
  }

  // ==================== INTERNAL HELPERS ====================

  private async sendBotMessage(conversationId: string, text: string, model: string) {
    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      select: { id: true, instanceId: true, remoteJid: true },
    });

    if (!conversation) return;

    const waInstance = await this.prisma.userWhatsappInstance.findUnique({
      where: { id: conversation.instanceId },
      select: { instanceName: true },
    });

    if (!waInstance) return;

    let evolutionMessageId: string | undefined;
    try {
      const sendResult = await this.whatsappService.sendTextMessage(
        waInstance.instanceName,
        conversation.remoteJid,
        text,
      );
      evolutionMessageId = this.extractEvolutionMessageId(sendResult);
    } catch (error) {
      this.logger.error(`Error enviando mensaje bot a ${conversationId}: ${error instanceof Error ? error.message : String(error)}`);
    }

    await this.prisma.whatsappMessage.create({
      data: {
        conversationId,
        evolutionId: evolutionMessageId ?? null,
        direction: WhatsappMessageDirection.OUTGOING,
        messageType: WhatsappMessageType.CONVERSATION,
        body: text,
        senderName: 'Bot IA',
        sentAt: new Date(),
        aiGenerated: true,
        aiModel: model,
        aiPromptVersion: '1.0',
      },
    });

    await this.prisma.whatsappConversation.update({
      where: { id: conversationId },
      data: {
        botLastReplyAt: new Date(),
        lastMessageAt: new Date(),
        unreadCount: 0,
      },
    });
  }

  private async pauseBotForConversationInternal(conversationId: string, reason: string) {
    await this.prisma.whatsappConversation.update({
      where: { id: conversationId },
      data: {
        botPaused: true,
        botPausedAt: new Date(),
        botPauseReason: reason,
      },
    });
  }

  private async updateBotSkipReason(conversationId: string, reason: BotSkipReason) {
    try {
      await this.prisma.whatsappConversation.update({
        where: { id: conversationId },
        data: { botSkippedReason: reason },
      });
    } catch {
      // Ignorar errores de actualización
    }
  }

  private extractEvolutionMessageId(result: unknown): string | undefined {
    if (!result || typeof result !== 'object') return undefined;
    const map = result as Record<string, unknown>;
    const direct = map['id'];
    if (typeof direct === 'string' && direct.trim().length > 0) {
      return direct.trim();
    }
    const key = map['key'];
    if (key && typeof key === 'object') {
      const keyId = (key as Record<string, unknown>)['id'];
      if (typeof keyId === 'string' && keyId.trim().length > 0) {
        return keyId.trim();
      }
    }
    return undefined;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
