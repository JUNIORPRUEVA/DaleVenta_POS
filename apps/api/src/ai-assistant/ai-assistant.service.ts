import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CompanyManualAudience, CompanyManualEntry, CompanyManualEntryKind, DepositOrderStatus, Prisma, Role } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CatalogProductsService } from '../products/catalog-products.service';
import { ChatAiAssistantDto } from './dto/chat-ai-assistant.dto';

type AiRuntimeConfig = {
  apiKey: string;
  model: string;
  companyName: string;
};

type KnowledgeRecord = {
  id: string;
  module: string;
  category: string;
  title: string;
  content: string;
  summary: string | null;
  keywords: string[];
  severity: 'info' | 'warning' | 'critical';
  active: boolean;
  createdAt: string | null;
  updatedAt: string | null;
};

type NormalizedAiContext = {
  module: string;
  screenName?: string;
  route?: string;
  entityType?: string;
  entityId?: string;
};

type AiIntent =
  | 'explain-screen'
  | 'explain-module'
  | 'clients'
  | 'catalog'
  | 'operations'
  | 'manual'
  | 'general';

type AiAssistantCitation = {
  id: string;
  module: string;
  category: string;
  title: string;
};

type AiAssistantChatResponse = {
  source: 'policy' | 'rules-only' | 'openai';
  content: string;
  citations: AiAssistantCitation[];
  denied?: boolean;
};

type PersistedAssistantMemoryRow = {
  id: string;
  module: string;
  scope: string;
  topicKey: string;
  title: string;
  summary: string;
  keywords: Prisma.JsonValue | null;
  sourceCount: number;
  lastSourceAt: Date | string | null;
  createdAt: Date | string | null;
  updatedAt: Date | string | null;
};

type PersistedConversationTurnRow = {
  userMessage: string;
  assistantResponse: string;
  module: string;
  createdAt: Date | string | null;
};

type AssistantMemoryNote = {
  scope: 'user';
  module: string;
  topicKey: string;
  title: string;
  summary: string;
  keywords: string[];
};

type CrmCommercialAiSuggestInput = {
  lastCustomerMessage: string;
  recentMessages: Array<{ direction: string; text: string }>;
  crmStatus?: string | null;
  customerInfo?: { name?: string | null; phone?: string | null } | null;
  availableBusinessData?: {
    location?: string | null;
    businessHours?: string | null;
    bankAccounts?: string[];
    catalogSummary?: string | null;
    libraryItems?: Array<{
      id: string;
      title: string;
      type: string;
      contentText?: string | null;
      mediaUrl?: string | null;
      fileName?: string | null;
      mimeType?: string | null;
      externalUrl?: string | null;
      category?: string | null;
      tags?: string[];
    }>;
  } | null;
};

type CrmCommercialAiSuggestOutput = {
  intent: string;
  suggestedReply: string;
  nextAction: string;
  missingData: string[];
  confidence: number;
  dataUsed: string[];
};

@Injectable()
export class AiAssistantService {
  private readonly logger = new Logger(AiAssistantService.name);

  private static readonly unauthorizedMessage =
    'No puedo ayudar con información privada de otro usuario ni mostrar datos para los que no tienes autorización.';

  private static readonly notEnoughDataMessage =
    'No tengo información suficiente en el sistema para responder eso. Si me das más contexto (módulo, cliente o pantalla), puedo ayudarte mejor.';

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly catalogProducts: CatalogProductsService,
  ) {}

  async suggestCommercialOrthography(input: {
    text: string;
    previousText?: string | null;
  }): Promise<{
    suggestion: string | null;
    changed: boolean;
    skipped: boolean;
    reason?: string;
  }> {
    const original = (input.text ?? '').toString();
    const trimmed = original.trim();
    if (!trimmed || trimmed.length < 6) {
      return { suggestion: null, changed: false, skipped: true, reason: 'too_short' };
    }

    const lower = trimmed.toLowerCase();
    if (['ok', 'dale', 'si', 'sí', 'gracias', 'hello', 'hola', 'perfecto'].includes(lower)) {
      return { suggestion: null, changed: false, skipped: true, reason: 'trivial' };
    }

    const runtime = await this.getOpenAiRuntimeConfig();
    if (!runtime.apiKey) {
      const fallback = this.fallbackCommercialOrthography(trimmed);
      if (fallback !== trimmed) {
        return { suggestion: fallback, changed: true, skipped: false, reason: 'local_fallback' };
      }
      return { suggestion: null, changed: false, skipped: true, reason: 'openai_unavailable' };
    }

    const systemPrompt =
      'Actúa como corrector profesional del idioma español especializado en conversaciones comerciales de WhatsApp para República Dominicana. ' +
      'Objetivo: corregir ortografía, tildes, signos de puntuación, espacios y redacción claramente rota, SIN cambiar intención ni tono humano. ' +
      'Debes conservar el estilo natural dominicano, no sonar robótico, no volverlo corporativo frío, no resumir, no inventar, no eliminar emojis. ' +
      'Respeta el contenido comercial y de servicio al cliente. Corrige abreviaciones comunes de escritura rápida cuando sea claro: ' +
      'k->que, q->que, bn->bien, tmb->también, grasias->gracias, alguiemte->alguien, erre->eres. ' +
      'Si el texto ya está bien, devuélvelo prácticamente igual.';

    const userPrompt =
      `${JSON.stringify({
        text: original,
        previousText: input.previousText ?? null,
      })}\n\n` +
      'Devuelve exactamente JSON con esta forma: ' +
      '{"correctedText":"string","changed":true|false,"notes":"string breve"}. ' +
      'Reglas estrictas: ' +
      '1) correctedText debe mantener el mismo sentido e intención; ' +
      '2) no agregues información nueva; ' +
      '3) no elimines emojis; ' +
      '4) no uses tono excesivamente formal; ' +
      '5) aplica signos de apertura (¿, ¡) cuando corresponda.';

    try {
      const parsed = await this.requestStrictJsonFromOpenAi<{
        correctedText?: unknown;
        changed?: unknown;
      }>({
        runtime,
        temperature: 0.1,
        systemPrompt,
        userPrompt,
      });

      const corrected = this.normalizeOptionalString(parsed.correctedText) ?? trimmed;
      const changed = parsed.changed === true || corrected !== trimmed;
      if (!changed) {
        return { suggestion: null, changed: false, skipped: false };
      }
      return {
        suggestion: corrected,
        changed: true,
        skipped: false,
      };
    } catch (error) {
      this.logDebug('orthography.openai_fallback', {
        message: error instanceof Error ? error.message : `${error}`,
      });
      const fallback = this.fallbackCommercialOrthography(trimmed);
      if (fallback !== trimmed) {
        return { suggestion: fallback, changed: true, skipped: false, reason: 'local_fallback' };
      }
      return { suggestion: null, changed: false, skipped: true, reason: 'openai_error' };
    }
  }

  private fallbackCommercialOrthography(value: string): string {
    let text = value
      .replace(/\s+/g, ' ')
      .trim();

    const replacements: Array<[RegExp, string]> = [
      [/\bq\b/gi, 'que'],
      [/\bk\b/gi, 'que'],
      [/\bxq\b/gi, 'porque'],
      [/\bgrasias\b/gi, 'gracias'],
      [/\bgrasia\b/gi, 'gracias'],
      [/\btmb\b/gi, 'también'],
      [/\bbn\b/gi, 'bien'],
      [/\bestoi\b/gi, 'estoy'],
      [/\baver\b/gi, 'a ver'],
      [/\bporfavor\b/gi, 'por favor'],
    ];

    for (const [pattern, replacement] of replacements) {
      text = text.replace(pattern, replacement);
    }

    text = text.replace(
      /(^|[.!?]\s+)([a-záéíóúñ])/g,
      (_, prefix: string, letter: string) => `${prefix}${letter.toUpperCase()}`,
    );

    text = text.replace(
      /^(hola|buenas|buenos dias|buenas tardes|buenas noches)\s+/i,
      (match: string) => `${match.trim()}, `,
    );

    const looksLikeQuestion = /\b(que|como|cuando|donde|cual|cuanto|puedes|podrias|me ayudas)\b/i.test(
      text.toLowerCase(),
    );
    if (looksLikeQuestion && !text.includes('?') && !text.includes('¿')) {
      text = `¿${text}?`;
    } else if (!/[.!?]$/.test(text)) {
      text = `${text}.`;
    }

    return text;
  }

  async suggestCrmCommercialReply(
    input: CrmCommercialAiSuggestInput,
  ): Promise<CrmCommercialAiSuggestOutput> {
    const rawMessage = (input.lastCustomerMessage ?? '').toString().trim();
    if (!rawMessage) {
      throw new BadRequestException('No hay mensaje del cliente para analizar.');
    }

    const location = (input.availableBusinessData?.location ?? '').toString().trim();
    const businessHours = (input.availableBusinessData?.businessHours ?? '').toString().trim();
    const bankAccounts = (input.availableBusinessData?.bankAccounts ?? [])
      .map((value) => value.toString().trim())
      .filter((value) => value.length > 0);
    const catalogSummary = (input.availableBusinessData?.catalogSummary ?? '')
      .toString()
      .trim();
    const libraryItems = (input.availableBusinessData?.libraryItems ?? [])
      .map((item) => ({
        id: item.id,
        title: (item.title ?? '').toString().trim(),
        type: (item.type ?? '').toString().trim().toUpperCase(),
        contentText: (item.contentText ?? '').toString().trim(),
        mediaUrl: (item.mediaUrl ?? '').toString().trim(),
        fileName: (item.fileName ?? '').toString().trim(),
        mimeType: (item.mimeType ?? '').toString().trim(),
        externalUrl: (item.externalUrl ?? '').toString().trim(),
        category: (item.category ?? '').toString().trim(),
        tags: Array.isArray(item.tags)
          ? item.tags.map((tag) => tag.toString().trim()).filter((tag) => tag.length > 0)
          : [],
      }))
      .filter((item) => item.title.length > 0 || item.contentText.length > 0 || item.mediaUrl.length > 0);

    const status = (input.crmStatus ?? 'NUEVO').toString().trim().toUpperCase() || 'NUEVO';
    const customerName = (input.customerInfo?.name ?? '').toString().trim();
    const greetingName = customerName.length > 0 ? ` ${customerName}` : '';

    const normalized = this.normalizeCrmCommercialText(rawMessage);
    const has = (...terms: string[]) => terms.some((term) => normalized.includes(term));

    let intent = 'interes_general';
    if (has('ubicacion', 'direccion', 'donde estan', 'donde se encuentran', 'local')) {
      intent = 'pide_ubicacion';
    } else if (has('horario', 'hora', 'abren', 'cierran', 'disponible hoy', 'atienden')) {
      intent = 'pide_horario';
    } else if (has('cuenta', 'banco', 'transferencia', 'deposito', 'depósito', 'pago por banco')) {
      intent = 'pide_cuenta_bancaria';
    } else if (has('catalogo', 'catálogo', 'productos', 'que venden', 'servicios')) {
      intent = 'pide_catalogo';
    } else if (has('precio', 'cuanto cuesta', 'cuánto cuesta', 'valor', 'costo')) {
      intent = 'pregunta_precio';
    } else if (has('cotizacion', 'cotización', 'cotizar', 'propuesta')) {
      intent = 'quiere_cotizacion';
    } else if (has('instalacion', 'instalación', 'instalar', 'montaje')) {
      intent = 'quiere_instalacion';
    } else if (has('molesto', 'inconforme', 'queja', 'mala experiencia', 'no me gusta', 'mal servicio')) {
      intent = 'cliente_molesto';
    } else if (has('seguimiento', 'dar seguimiento', 'pendiente', 'me confirma')) {
      intent = 'quiere_seguimiento';
    } else if (has('comprar', 'lo quiero', 'me interesa', 'vamos a hacerlo', 'quiero eso')) {
      intent = 'quiere_comprar';
    }

    const pickLibrary = (...types: string[]) =>
      libraryItems.find((item) => types.includes(item.type)) ?? null;

    const pickLibraryText = (...types: string[]) => {
      const item = pickLibrary(...types);
      if (!item) return null;
      return item.contentText || item.externalUrl || item.title || null;
    };

    const missingData: string[] = [];
    const dataUsed: string[] = [];
    let suggestedReply = '';
    let nextAction = '';
    let confidence = 0;

    switch (intent) {
      case 'pide_ubicacion':
        if (location.length === 0) {
          missingData.push('ubicacion');
          const item = pickLibraryText('LOCATION', 'LINK', 'TEXT');
          suggestedReply = item
            ? `Claro${greetingName}, esta es nuestra ubicación: ${item}`
            : 'No hay información configurada para esto.';
        } else {
          dataUsed.push('ubicacion');
          suggestedReply = `Claro${greetingName}, esta es nuestra ubicación: ${location}`;
        }
        nextAction = 'confirmar_visita';
        confidence = location.length === 0 ? 0.82 : 0.95;
        break;

      case 'pide_horario':
        if (businessHours.length === 0) {
          missingData.push('horario');
          const item = pickLibraryText('BUSINESS_HOURS', 'TEXT');
          suggestedReply = item
            ? `Nuestro horario es: ${item}`
            : 'No hay información configurada para esto.';
        } else {
          dataUsed.push('horario');
          suggestedReply = `Nuestro horario es: ${businessHours}`;
        }
        nextAction = 'confirmar_hora_preferida';
        confidence = businessHours.length === 0 ? 0.82 : 0.95;
        break;

      case 'pide_cuenta_bancaria':
        if (bankAccounts.length === 0) {
          missingData.push('cuentas_bancarias');
          const item = pickLibrary('BANK_ACCOUNT', 'TEXT');
          const text = item ? (item.contentText || item.title) : null;
          suggestedReply = text
            ? `Claro, aquí tienes nuestras cuentas disponibles:\n${text}`
            : 'No hay información configurada para esto.';
        } else {
          dataUsed.push('cuentas_bancarias');
          const lines = bankAccounts.map((acc) => `- ${acc}`).join('\n');
          suggestedReply = `Claro, aquí tienes nuestras cuentas disponibles:\n${lines}`;
        }
        nextAction = 'confirmar_metodo_pago';
        confidence = bankAccounts.length === 0 ? 0.84 : 0.95;
        break;

      case 'pide_catalogo':
        if (catalogSummary.length === 0) {
          missingData.push('catalogo');
          const item = pickLibraryText('CATALOG', 'QUOTE_TEMPLATE', 'TEXT');
          suggestedReply = item
            ? `Te comparto una referencia rápida de productos/servicios disponibles: ${item}`
            : 'No hay información configurada para esto.';
        } else {
          dataUsed.push('catalogo');
          suggestedReply =
              `Te comparto una referencia rápida de productos/servicios disponibles: ${catalogSummary}`;
        }
        nextAction = 'preguntar_producto_objetivo';
        confidence = catalogSummary.length === 0 ? 0.84 : 0.93;
        break;

      case 'pregunta_precio':
        suggestedReply =
          pickLibraryText('QUOTE_TEMPLATE', 'PROMOTION', 'TEXT') ??
          'Con gusto te ayudo con el precio. Para cotizarte exacto sin inventar, ¿me confirmas el producto/servicio, cantidad y ubicación de instalación?';
        nextAction = 'recolectar_datos_cotizacion';
        confidence = 0.9;
        break;

      case 'quiere_cotizacion':
        suggestedReply =
          pickLibraryText('QUOTE_TEMPLATE', 'TEXT') ??
          'Excelente. Te preparo cotización formal. Solo necesito: producto/servicio, cantidad, ubicación y fecha estimada de instalación.';
        nextAction = 'crear_cotizacion';
        confidence = 0.92;
        break;

      case 'quiere_instalacion':
        suggestedReply =
          pickLibraryText('FOLLOW_UP', 'TEXT') ??
          'Perfecto, te apoyamos con la instalación. ¿Me compartes ubicación, día preferido y una foto del área para coordinarte rápido?';
        nextAction = 'agendar_instalacion';
        confidence = 0.9;
        break;

      case 'cliente_molesto':
        suggestedReply =
          pickLibraryText('WARRANTY', 'FAQ', 'TEXT') ??
          'Lamento mucho la situación y gracias por avisarnos. Quiero ayudarte a resolverlo hoy mismo. ¿Me compartes lo ocurrido para darte una solución inmediata?';
        nextAction = 'priorizar_seguimiento';
        confidence = 0.9;
        break;

      case 'quiere_seguimiento':
        suggestedReply =
          pickLibraryText('FOLLOW_UP', 'TEXT') ??
          'Gracias por el seguimiento. Ya te confirmo el estado actualizado en breve para que tengas claridad del próximo paso.';
        nextAction = 'crear_tarea_seguimiento';
        confidence = 0.87;
        break;

      case 'quiere_comprar':
        suggestedReply =
          pickLibraryText('PROMOTION', 'QUOTE_TEMPLATE', 'TEXT') ??
          'Excelente decisión. Para dejarte todo listo hoy, ¿me confirmas producto/servicio, cantidad y método de pago preferido?';
        nextAction = 'cerrar_venta';
        confidence = 0.91;
        break;

      default:
        suggestedReply =
            'Gracias por escribirnos. Con gusto te ayudo. ¿Me compartes un poco más de detalle para orientarte con la mejor opción?';
        nextAction = 'aclarar_necesidad';
        confidence = 0.78;
        break;
    }

    const runtime = await this.getOpenAiRuntimeConfig();
    if (runtime.apiKey) {
      try {
        const parsed = await this.requestStrictJsonFromOpenAi<{
          reply?: unknown;
          nextAction?: unknown;
          confidence?: unknown;
        }>({
          runtime,
          temperature: 0.2,
          systemPrompt:
              'Eres asesor comercial de FULLTECH para WhatsApp. Responde en español dominicano profesional, breve, humano y vendedor. ' +
              'Reglas obligatorias: no inventes ubicación, horarios, cuentas bancarias, catálogo, precios ni datos no provistos. ' +
              'Si un dato falta, dilo de forma natural sin inventar. Nunca auto-envíes mensajes; solo sugerencias.',
          userPrompt:
              `${JSON.stringify({
                intent,
                crmStatus: status,
                customerName,
                lastCustomerMessage: rawMessage,
                deterministicReply: suggestedReply,
                nextAction,
                missingData,
                availableBusinessData: {
                  location,
                  businessHours,
                  bankAccounts,
                  catalogSummary,
                  libraryItems,
                },
              })}\n\n` +
              'Devuelve JSON exacto: {"reply":"string","nextAction":"string","confidence":0.0}.',
        });

        const aiReply = this.normalizeOptionalString(parsed.reply);
        const aiNextAction = this.normalizeOptionalString(parsed.nextAction);
        const aiConfidence = Number(parsed.confidence);

        if (aiReply != null) {
          suggestedReply = aiReply;
        }
        if (aiNextAction != null) {
          nextAction = aiNextAction;
        }
        if (Number.isFinite(aiConfidence)) {
          confidence = Math.max(0, Math.min(1, aiConfidence));
        }
      } catch (error) {
        this.logDebug('crm-commercial.ai_suggest_fallback', {
          message: error instanceof Error ? error.message : `${error}`,
        });
      }
    }

    dataUsed.push('estado_crm');
    if (rawMessage.length > 0) {
      dataUsed.push('mensaje_cliente');
    }
    if (customerName.length > 0) {
      dataUsed.push('cliente');
    }

    return {
      intent,
      suggestedReply,
      nextAction,
      missingData,
      confidence,
      dataUsed: Array.from(new Set(dataUsed)),
    };
  }

  async isCommercialAiConfigured(): Promise<boolean> {
    const runtime = await this.getOpenAiRuntimeConfig();
    return !!runtime.apiKey;
  }

  private normalizeCrmCommercialText(value: string) {
    return value
      .toLowerCase()
      .replace(/[áàäâ]/g, 'a')
      .replace(/[éèëê]/g, 'e')
      .replace(/[íìïî]/g, 'i')
      .replace(/[óòöô]/g, 'o')
      .replace(/[úùüû]/g, 'u')
      .replace(/[^a-z0-9\s]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  async chat(user: { id: string; role: Role }, dto: ChatAiAssistantDto) {
    const message = dto.message.trim();
    if (!message) throw new BadRequestException('El mensaje es obligatorio');

    const context = this.normalizeContext(dto.context);
    const currentUserName = await this.getCurrentUserPreferredName(user.id);
    const effectiveDto = { ...dto, context };

    if (!this.canAccessContext(user.role, context)) {
      return this.finalizeChatResponse(user, effectiveDto, {
        source: 'policy',
        content: AiAssistantService.unauthorizedMessage,
        citations: [],
        denied: true,
      }, []);
    }

    // Hard deny for common secret/credential extraction attempts.
    if (this.isForbiddenSecretRequest(message)) {
      return this.finalizeChatResponse(user, effectiveDto, {
        source: 'policy',
        content: AiAssistantService.unauthorizedMessage,
        citations: [],
        denied: true,
      }, []);
    }

    if (this.isOtherUserSensitiveRequest(user, message, context)) {
      return this.finalizeChatResponse(user, effectiveDto, {
        source: 'policy',
        content: 'Puedo ayudarte con tu propia información, pero no puedo revelar datos personales, de nómina, contrato o perfil de otro usuario.',
        citations: [],
        denied: true,
      }, []);
    }

    const knowledge = await this.buildKnowledge(user, effectiveDto);
    this.logDebug('ai.chat.context', context);
    this.logDebug('ai.chat.knowledge', knowledge.map((k) => ({ id: k.id, title: k.title, module: k.module })));

    if (knowledge.length === 0) {
      return this.finalizeChatResponse(user, effectiveDto, {
        source: 'rules-only',
        content: this.personalizeContent(AiAssistantService.notEnoughDataMessage, currentUserName),
        citations: [],
      }, knowledge);
    }

    if (this.shouldUseDeterministicLookupAnswer(message, context, knowledge)) {
      return this.finalizeChatResponse(
        user,
        effectiveDto,
        this.buildRuleOnlyFallback(message, knowledge, currentUserName),
        knowledge,
      );
    }

    const runtime = await this.getOpenAiRuntimeConfig();
    if (!runtime.apiKey) {
      return this.finalizeChatResponse(
        user,
        effectiveDto,
        this.buildRuleOnlyFallback(message, knowledge, currentUserName),
        knowledge,
      );
    }

    const safeHistory = this.normalizeHistory(dto.history).slice(-8);

    const systemPrompt =
      `SYSTEM PROMPT — FULLTECH AI\n` +
      `You are FULLTECH AI, an intelligent assistant integrated into the FULLTECH internal system for ${runtime.companyName}.\n` +
      'Your purpose is to help employees understand how to use the system, access authorized information, and guide them in their work.\n\n' +
      'Knowledge sources (provided by the system per request):\n' +
      '1) Internal manual and company rules (primary source of truth)\n' +
      '2) Application modules and their functions\n' +
      '3) Client database\n' +
      '4) Service operations, document flows and operational records\n' +
      '5) Company products catalog\n' +
      '6) Logged-in user information\n\n' +
      'Rules:\n' +
      '- Prioritize the Internal Manual whenever the question touches rules, norms, policies, procedures or how a workflow should be handled.\n' +
      '- Use ONLY the provided internal knowledge.\n' +
      '- Never invent data. If something is not available, say so and ask for missing context.\n' +
      '- Do not use external knowledge.\n' +
      '- Do not reveal private data of other users; you MAY answer the logged-in user\'s own authorized data if provided.\n' +
      '- If the user asks about the screen they are currently viewing, explain what that screen/module does and how to use it step by step.\n\n' +
      'Style:\n' +
      '- Answer clearly, professionally, and practically.\n' +
      `${currentUserName ? `- If natural, address the user by name: ${currentUserName}.\n` : ''}` +
      '- If the answer is long, give a short summary first.\n' +
      '- Never mention internal mechanisms (memory, tokens, ranking, internal context).\n\n' +
      'Return ONLY valid JSON.';

    const userPrompt =
      `${JSON.stringify({ message, context, history: safeHistory, knowledge, currentUserName })}\n\n` +
      'Devuelve exactamente este JSON: ' +
      '{"content":"string","citations":[{"id":"string","module":"string","category":"string","title":"string"}],"denied":false}. ' +
      'Reglas estrictas: ' +
      '1) si respondes algo útil basado en conocimiento enviado, citations no puede ir vacío; ' +
      '2) no incluyas citas inventadas; ' +
      '3) si el usuario pide información no autorizada de un tercero, usa denied=true y content debe explicar que no tiene permisos; ' +
      '4) si el usuario pregunta por su propia información y existe conocimiento del usuario actual, responde con esos datos y denied=false; ' +
      '5) si no hay información suficiente, denied=false y content debe pedir más contexto.';

    let parsed: {
      content?: unknown;
      citations?: unknown;
      denied?: unknown;
    };

    try {
      parsed = await this.requestStrictJsonFromOpenAi<{
        content?: unknown;
        citations?: unknown;
        denied?: unknown;
      }>({
        runtime,
        temperature: 0.2,
        systemPrompt,
        userPrompt,
      });
    } catch (error) {
      this.logDebug('openai.fallback', {
        message: error instanceof Error ? error.message : `${error}`,
      });
      return this.finalizeChatResponse(
        user,
        effectiveDto,
        this.buildRuleOnlyFallback(message, knowledge, currentUserName),
        knowledge,
      );
    }

    const content = this.normalizeOptionalString(parsed.content) ?? AiAssistantService.notEnoughDataMessage;
    const citations = this.normalizeCitations(parsed.citations, knowledge);
    const denied = parsed.denied === true;

    // Safety net: If denied then don't allow citations.
    if (denied) {
      return this.finalizeChatResponse(user, effectiveDto, {
        source: 'policy',
        content: this.isUnauthorizedMessage(content) ? content : AiAssistantService.unauthorizedMessage,
        citations: [],
        denied: true,
      }, knowledge);
    }

    // If the model returned something useful but without citations, fall back to deterministic retrieval.
    if (citations.length === 0) {
      return this.finalizeChatResponse(
        user,
        effectiveDto,
        this.buildRuleOnlyFallback(message, knowledge, currentUserName),
        knowledge,
      );
    }

    return this.finalizeChatResponse(user, effectiveDto, {
      source: 'openai',
      content: this.personalizeContent(content, currentUserName),
      citations,
      denied: false,
    }, knowledge);
  }

  private normalizeHistory(raw?: Array<{ role: 'user' | 'assistant'; content: string }>) {
    if (!Array.isArray(raw)) return [];
    return raw
      .map((m) => {
        if (!m || typeof m !== 'object') return null;
        const role = m.role === 'assistant' ? 'assistant' : 'user';
        const content = this.normalizeOptionalString(m.content);
        if (!content) return null;
        return { role, content };
      })
      .filter((m): m is NonNullable<typeof m> => !!m);
  }

  private isUnauthorizedMessage(content: string) {
    const text = content.toLowerCase();
    return text.includes('permiso') || text.includes('autoriz');
  }

  private isForbiddenSecretRequest(message: string) {
    const text = message.toLowerCase();
    return (
      text.includes('api key') ||
      text.includes('apikey') ||
      text.includes('token') ||
      text.includes('password') ||
      text.includes('contraseña') ||
      text.includes('clave') && text.includes('openai')
    );
  }

  private normalizeContext(raw: ChatAiAssistantDto['context']): NormalizedAiContext {
    const route = this.normalizeOptionalString(raw?.route) ?? undefined;
    const routeContext = this.parseRouteContext(route);
    const module = this.normalizeModuleKey(
      this.normalizeOptionalString(raw?.module) ?? routeContext.module ?? 'general',
    ) || 'general';
    const screenName = this.normalizeOptionalString(raw?.screenName) ?? routeContext.screenName ?? undefined;
    const entityType = this.normalizeOptionalString(raw?.entityType) ?? routeContext.entityType ?? undefined;
    const entityId = this.normalizeOptionalString(raw?.entityId) ?? routeContext.entityId ?? undefined;

    return {
      module,
      ...(screenName ? { screenName } : {}),
      ...(route ? { route } : {}),
      ...(entityType ? { entityType } : {}),
      ...(entityId ? { entityId } : {}),
    };
  }

  private normalizeModuleKey(value: unknown) {
    if (typeof value !== 'string') return 'general';

    const trimmed = value.trim();
    if (!trimmed) return 'general';

    const normalized = trimmed
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[\s_]+/g, '-')
      .replace(/[^a-z0-9-]/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '');

    switch (normalized) {
      case 'manual':
      case 'manualinterno':
      case 'manual-interno':
      case 'company-manual':
        return 'manual-interno';
      case 'catalogo':
      case 'catalog':
        return 'catalogo';
      case 'ventas':
      case 'venta':
        return 'ventas';
      case 'cotizacion':
      case 'cotizaciones':
        return 'cotizaciones';
      case 'operaciones':
      case 'operacion':
      case 'service-orders':
      case 'service-order':
        return 'service-orders';
      case 'document-flows':
      case 'document-flow':
      case 'flujo-documental':
      case 'flujo-documentos':
        return 'document-flows';
      case 'media-gallery':
      case 'galeria-media':
      case 'galeria':
        return 'media-gallery';
      case 'cliente':
      case 'clientes':
        return 'clientes';
      case 'nomina':
        return 'nomina';
      case 'contabilidad':
        return 'contabilidad';
      case 'administracion':
      case 'admin':
        return 'administracion';
      case 'configuracion':
      case 'settings':
        return 'configuracion';
      case 'perfil':
      case 'profile':
        return 'profile';
      default:
        return normalized || 'general';
    }
  }

  private parseRouteContext(route?: string) {
    const raw = (route ?? '').trim();
    if (!raw) return {} as Partial<NormalizedAiContext>;

    let uri: URL;
    try {
      uri = new URL(raw, 'https://fulltech.local');
    } catch {
      return {} as Partial<NormalizedAiContext>;
    }

    const path = uri.pathname.trim().toLowerCase();
    const segments = path.split('/').filter(Boolean);
    const result: Partial<NormalizedAiContext> = {};

    if (path.startsWith('/clientes')) {
      result.module = 'clientes';
      result.screenName = segments.length >= 2
        ? (segments[2] === 'editar' ? 'Editar cliente' : 'Detalle de cliente')
        : (segments[1] === 'nuevo' ? 'Nuevo cliente' : 'Clientes');
      if (segments.length >= 2 && segments[1] !== 'nuevo') {
        result.entityType = 'client';
        result.entityId = segments[1];
      }
      return result;
    }

    if (path.startsWith('/catalogo')) return { module: 'catalogo', screenName: 'Catálogo' };
    if (path === '/ventas/nueva') return { module: 'ventas', screenName: 'Registrar venta' };
    if (path.startsWith('/ventas')) return { module: 'ventas', screenName: 'Ventas' };
    if (path === '/service-orders') return { module: 'service-orders', screenName: 'Operaciones' };
    if (path === '/service-orders/nueva') return { module: 'service-orders', screenName: 'Crear orden' };
    if (path.startsWith('/service-orders/')) {
      return {
        module: 'service-orders',
        screenName: 'Detalle de orden',
        entityType: 'service-order',
        entityId: segments[1],
      };
    }
    if (path === '/document-flows') return { module: 'document-flows', screenName: 'Flujo documental' };
    if (path.startsWith('/document-flows/')) {
      return {
        module: 'document-flows',
        screenName: 'Detalle documental',
        entityType: 'service-order',
        entityId: segments[1],
      };
    }
    if (path === '/media-gallery') return { module: 'media-gallery', screenName: 'Galería media' };
    if (path === '/contabilidad/cierres-diarios') return { module: 'contabilidad', screenName: 'Cierres diarios' };
    if (path === '/contabilidad/factura-fiscal') return { module: 'contabilidad', screenName: 'Facturas fiscales' };
    if (path === '/contabilidad/pagos-pendientes') return { module: 'contabilidad', screenName: 'Pagos pendientes' };
    if (path.startsWith('/contabilidad')) return { module: 'contabilidad', screenName: 'Contabilidad' };
    if (path === '/nomina') return { module: 'nomina', screenName: 'Nómina' };
    if (path === '/mis-pagos') return { module: 'nomina', screenName: 'Mis pagos' };
    if (path.startsWith('/manual-interno')) return { module: 'manual-interno', screenName: 'Manual interno' };
    if (path.startsWith('/configuracion')) return { module: 'configuracion', screenName: 'Configuración' };
    if (path.startsWith('/administracion')) return { module: 'administracion', screenName: 'Administración' };
    if (path === '/cotizaciones/historial') {
      const quoteId = uri.searchParams.get('quoteId')?.trim() ?? '';
      const customerPhone = uri.searchParams.get('customerPhone')?.trim() ?? '';
      return {
        module: 'cotizaciones',
        screenName: 'Historial de cotizaciones',
        ...(quoteId ? { entityType: 'quote', entityId: quoteId } : {}),
        ...(!quoteId && customerPhone ? { entityType: 'client-phone', entityId: customerPhone } : {}),
      };
    }
    if (path.startsWith('/cotizaciones')) return { module: 'cotizaciones', screenName: 'Cotizaciones' };
    if (path.startsWith('/users/')) {
      return {
        module: 'administracion',
        screenName: 'Detalle de usuario',
        entityType: 'user',
        entityId: segments[1],
      };
    }
    if (path === '/users' || path === '/user') return { module: 'administracion', screenName: 'Usuarios' };
    if (path === '/horarios') return { module: 'horarios', screenName: 'Horarios' };
    if (path === '/profile') return { module: 'profile', screenName: 'Perfil' };
    if (path === '/ponche') return { module: 'ponche', screenName: 'Ponche' };
    if (path === '/ponche/historial') return { module: 'ponche', screenName: 'Historial de ponches' };

    return { module: 'general' };
  }

  private canAccessContext(role: Role, context: NormalizedAiContext) {
    const path = this.extractPath(context.route);
    if (path) {
      return this.canAccessPath(role, path);
    }
    return this.canAccessModule(role, context.module);
  }

  private extractPath(route?: string) {
    const raw = (route ?? '').trim();
    if (!raw) return '';
    try {
      return new URL(raw, 'https://fulltech.local').pathname.toLowerCase();
    } catch {
      return raw.split('?')[0]?.trim().toLowerCase() ?? '';
    }
  }

  private canAccessPath(role: Role, path: string) {
    if (!path) return true;

    if (path === '/profile') return true;
    if (path === '/mis-pagos') return true;
    if (path === '/horarios') return true;
    if (path === '/ponche') return true;
    if (path.startsWith('/catalogo')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING]);
    if (path.startsWith('/ventas')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR]);
    if (path.startsWith('/cotizaciones')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO]);
    if (path.startsWith('/clientes')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING]);
    if (path.startsWith('/nomina')) return role === Role.ADMIN;
    if (path.startsWith('/manual-interno')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO]);
    if (path.startsWith('/contabilidad')) return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE]);
    if (path.startsWith('/administracion')) return role === Role.ADMIN;
    if (path.startsWith('/configuracion')) return role === Role.ADMIN;
    if (path === '/users' || path === '/user' || path.startsWith('/users/')) return role === Role.ADMIN;

    return true;
  }

  private canAccessModule(role: Role, module: string) {
    switch (this.normalizeModuleKey(module)) {
      case 'general':
        return true;
      case 'profile':
      case 'ponche':
      case 'horarios':
        return true;
      case 'catalogo':
        return true;
      case 'service-orders':
      case 'document-flows':
      case 'media-gallery':
        return true;
      case 'ventas':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR]);
      case 'cotizaciones':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO]);
      case 'clientes':
        return true;
      case 'nomina':
        return role === Role.ADMIN;
      case 'manual-interno':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO]);
      case 'contabilidad':
        return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE]);
      case 'administracion':
      case 'configuracion':
        return role === Role.ADMIN;
      default:
        return true;
    }
  }

  private hasRole(role: Role, allowed: Role[]) {
    return allowed.includes(role);
  }

  private canAccessClientData(role: Role) {
    return true;
  }

  private shouldUseDeterministicLookupAnswer(
    message: string,
    context: NormalizedAiContext,
    knowledge: KnowledgeRecord[],
  ) {
    const tokens = new Set(this.tokenize(message));
    const hasLookupIntent = this.hasAnyToken(tokens, [
      'existe',
      'buscar',
      'busca',
      'buscarme',
      'encuentra',
      'encontrar',
      'muestrame',
      'muéstrame',
      'dame',
      'detalle',
      'detalles',
      'informacion',
      'información',
      'estado',
      'resumen',
    ]);
    const hasMatchedClient = knowledge.some((item) => item.id.startsWith('app-data:client-match:'));
    const hasMatchedCatalog = knowledge.some(
      (item) => item.id === 'app-data:catalog-search' || item.id.startsWith('app-data:product-match:'),
    );
    const hasMatchedServiceOrder = knowledge.some(
      (item) => item.id.startsWith('app-data:service-order:') || item.id.startsWith('app-data:service-order-match:'),
    );
    const hasMatchedDocumentFlow = knowledge.some(
      (item) => item.id.startsWith('app-data:document-flow:') || item.id.startsWith('app-data:document-flow-match:'),
    );
    const hasContractKnowledge = knowledge.some(
      (item) => item.id.startsWith('app-data:contract:') || item.id.startsWith('app-data:contract-match:'),
    );
    const hasSelfKnowledge = knowledge.some(
      (item) => item.id.startsWith('app-data:self:') || item.id.startsWith('app-data:contract:'),
    );
    const explicitClientLookup =
      hasMatchedClient ||
      (hasLookupIntent && this.hasAnyToken(tokens, ['cliente', 'clientes', 'nombre', 'telefono', 'teléfono', 'movimientos']));
    const explicitCatalogLookup =
      hasMatchedCatalog ||
      (hasLookupIntent && this.hasAnyToken(tokens, ['producto', 'productos', 'catalogo', 'catálogo', 'precio', 'stock', 'inventario']));
    const explicitOperationsLookup =
      hasMatchedServiceOrder ||
      hasMatchedDocumentFlow ||
      (hasLookupIntent && this.hasAnyToken(tokens, ['orden', 'ordenes', 'órdenes', 'servicio', 'servicios', 'operacion', 'operación', 'operaciones', 'flujo', 'documental']));
    const explicitContractLookup =
      hasContractKnowledge ||
      (hasLookupIntent && this.hasAnyToken(tokens, [
        'contrato',
        'contratos',
        'laboral',
        'trabajo',
        'salario',
        'sueldo',
        'pago',
        'frecuencia',
        'clausula',
        'cláusula',
        'firma',
        'nomina',
        'nómina',
      ]));
    const explicitSelfLookup = hasSelfKnowledge || this.isSelfInfoRequest(message, context);

    return explicitClientLookup || explicitCatalogLookup || explicitOperationsLookup || explicitContractLookup || explicitSelfLookup;
  }

  private canAccessQuoteData(role: Role) {
    return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.TECNICO]);
  }

  private canAccessSalesData(role: Role) {
    return this.canAccessModule(role, 'ventas');
  }

  private canAccessAccountingData(role: Role) {
    return this.hasRole(role, [Role.ADMIN, Role.ASISTENTE]);
  }

  private canAccessOperationsData(role: Role) {
    return this.canAccessModule(role, 'service-orders');
  }

  private canAccessDocumentFlowData(role: Role) {
    return this.canAccessModule(role, 'document-flows');
  }

  private canAccessContractData(role: Role, route?: string) {
    const path = this.extractPath(route);
    if (path === '/mis-pagos' || path === '/profile') {
      return true;
    }
    return role === Role.ADMIN;
  }

  private async buildKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const ownerId = await this.resolveCompanyOwnerId(user.id);

    const manualEntries = await this.prisma.companyManualEntry.findMany({
      where: {
        ownerId,
        published: true,
        kind: {
          in: [
            CompanyManualEntryKind.GENERAL_RULE,
            CompanyManualEntryKind.ROLE_RULE,
            CompanyManualEntryKind.POLICY,
            CompanyManualEntryKind.WARRANTY_POLICY,
            CompanyManualEntryKind.RESPONSIBILITY,
            CompanyManualEntryKind.PRICE_RULE,
            CompanyManualEntryKind.SERVICE_RULE,
            CompanyManualEntryKind.PRODUCT_SERVICE,
            CompanyManualEntryKind.MODULE_GUIDE,
          ],
        },
        OR: [
          { audience: CompanyManualAudience.GENERAL },
          {
            audience: CompanyManualAudience.ROLE_SPECIFIC,
            targetRoles: { has: user.role },
          },
        ],
      },
      orderBy: [{ sortOrder: 'asc' }, { updatedAt: 'desc' }, { title: 'asc' }],
      take: 260,
    });

    const manualKnowledge = manualEntries.map((entry) => this.toManualKnowledge(entry));
    const staticHelp = this.buildStaticModuleHelp(manualEntries.length);
    const persistentMemory = await this.buildPersistentMemoryKnowledge(user, dto);
    const authorizedData = [
      ...(await this.buildAuthorizedDataKnowledge(user, dto)),
      ...persistentMemory,
    ];

    const all = [
      ...manualKnowledge,
      ...staticHelp,
      ...authorizedData,
    ];

    return this.selectKnowledgeForPrompt({
      prompt: dto.message,
      context: dto.context,
      manualKnowledge,
      staticHelp,
      authorizedData,
      all,
    });
  }

  private toManualKnowledge(entry: CompanyManualEntry): KnowledgeRecord {
    const category = (() => {
      switch (entry.kind) {
        case CompanyManualEntryKind.POLICY:
          return 'politicas';
        case CompanyManualEntryKind.WARRANTY_POLICY:
          return 'garantias';
        case CompanyManualEntryKind.PRICE_RULE:
          return 'precios';
        case CompanyManualEntryKind.SERVICE_RULE:
          return 'servicios';
        case CompanyManualEntryKind.PRODUCT_SERVICE:
          return 'productos';
        case CompanyManualEntryKind.MODULE_GUIDE:
          return 'modulo';
        case CompanyManualEntryKind.GENERAL_RULE:
        case CompanyManualEntryKind.ROLE_RULE:
        case CompanyManualEntryKind.RESPONSIBILITY:
        default:
          return 'general';
      }
    })();

    const module = entry.moduleKey ? this.normalizeModuleKey(entry.moduleKey) : 'manual-interno';
    const titleSuffix = entry.moduleKey ? ` (${this.normalizeModuleKey(entry.moduleKey)})` : '';
    const severity = this.inferSeverity(entry.kind, entry.title, entry.content);
    const keywordBag = Array.from(
      new Set(
        [
          ...this.tokenize(`${entry.title} ${entry.summary ?? ''} ${entry.content}`),
          ...this.tokenize(entry.kind),
          ...(entry.moduleKey ? this.tokenize(entry.moduleKey) : []),
          'manual',
          'interno',
        ].filter((x) => x.trim().length > 0),
      ),
    ).slice(0, 18);

    return {
      id: `manual:${entry.id}`,
      module,
      category,
      title: `${entry.title}${titleSuffix}`,
      content: entry.content,
      summary: entry.summary,
      keywords: keywordBag,
      severity,
      active: entry.published,
      createdAt: entry.createdAt ? entry.createdAt.toISOString() : null,
      updatedAt: entry.updatedAt ? entry.updatedAt.toISOString() : null,
    };
  }

  private buildStaticModuleHelp(manualCount: number): KnowledgeRecord[] {
    return [
      this.createAppKnowledgeRecord(
        'app-help:general',
        'general',
        'guia-app',
        'Cómo pedir ayuda al asistente',
        'Puedes preguntarme sobre cómo usar módulos, qué significa una opción, qué dice el Manual Interno y dónde encontrar información. Si estás en una pantalla específica, dime el módulo (clientes, catálogo, ventas, cotizaciones, operaciones, flujo documental, galería media, nómina, manual interno, configuración) y qué estás intentando lograr.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:clientes',
        'clientes',
        'guia-app',
        'Uso del módulo de clientes',
        'En Clientes puedes buscar, crear y consultar clientes. En detalle de cliente puedes ver datos básicos, historial y procesos relacionados según tu rol. Si necesitas algo específico, dime el cliente y qué deseas revisar.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:cotizaciones',
        'cotizaciones',
        'guia-app',
        'Uso del módulo de cotizaciones',
        'En Cotizaciones puedes preparar propuestas, revisar historial y validar reglas comerciales del Manual Interno. Si ya tienes una cotización abierta o un cliente seleccionado, el asistente prioriza ese contexto.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:service-orders',
        'service-orders',
        'guia-app',
        'Uso del módulo de operaciones',
        'En Operaciones puedes crear, revisar y dar seguimiento a órdenes de servicio. Si ya estás dentro de una orden, el asistente puede resumir el estado, el cliente relacionado y qué sigue en el flujo.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:document-flows',
        'document-flows',
        'guia-app',
        'Uso del flujo documental',
        'En Flujo documental puedes revisar el estado de factura, garantía, aprobación y envío asociado a una orden de servicio. Si abres un flujo concreto, el asistente prioriza ese contexto.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:media-gallery',
        'media-gallery',
        'guia-app',
        'Uso de la galería media',
        'En Galería media puedes revisar evidencias visuales y multimedia de trabajos realizados. Si me dices qué estás viendo, te explico la pantalla y sus filtros.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:catalogo',
        'catalogo',
        'guia-app',
        'Uso del módulo de catálogo',
        'En Catálogo puedes ver productos por categoría y revisar información del catálogo. La visibilidad de precios depende de tu rol.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:ventas',
        'ventas',
        'guia-app',
        'Uso del módulo de ventas',
        'En Ventas puedes registrar ventas y revisar tus ventas autorizadas. Si necesitas ayuda, indica si estás registrando una venta nueva o revisando ventas anteriores.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:contabilidad',
        'contabilidad',
        'guia-app',
        'Uso del módulo de contabilidad',
        'En Contabilidad puedes registrar cierres, órdenes de depósito, facturas fiscales y pagos pendientes si tu rol lo permite. El asistente puede explicar la pantalla actual y resumir datos autorizados del módulo.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:nomina',
        'nomina',
        'guia-app',
        'Uso del módulo de nómina',
        'Nómina contiene información sensible. Solo usuarios autorizados pueden ver datos de empleados. Puedes consultar tu información personal si aplica.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:manual',
        'manual-interno',
        'guia-app',
        'Manual Interno',
        'El Manual Interno es la base principal de reglas, protocolos, políticas y guías por rol. El asistente responde priorizando estas reglas oficiales.',
      ),
      this.createAppKnowledgeRecord(
        'app-help:manual-coverage',
        'manual-interno',
        'guia-app',
        'Cobertura del Manual Interno',
        `Actualmente el sistema tiene ${manualCount} entradas publicadas del Manual Interno disponibles para este asistente según permisos y rol.`,
      ),
      this.createAppKnowledgeRecord(
        'app-help:seguridad',
        'seguridad',
        'politica-app',
        'Política de privacidad del asistente',
        'El asistente nunca debe revelar credenciales, tokens, contraseñas ni información privada de otros usuarios. Si algo no está permitido por tu rol, el asistente lo rechazará.',
      ),
    ];
  }

  private async buildAuthorizedDataKnowledge(
    user: { id: string; role: Role },
    dto: ChatAiAssistantDto,
  ): Promise<KnowledgeRecord[]> {
    const contextText = [
      dto.message,
      dto.context.module ?? '',
      dto.context.screenName ?? '',
      dto.context.route ?? '',
      dto.context.entityType ?? '',
    ].join(' ');
    const tokens = new Set(this.tokenize(contextText));
    const includeModuleContext = tokens.size === 0;
    const wantsClientsByIntent = this.isLikelyClientLookup(dto, tokens);
    const wantsCatalogByIntent = this.isLikelyCatalogLookup(dto, tokens);

    const wantsClients = includeModuleContext || wantsClientsByIntent || this.hasAnyToken(tokens, ['cliente', 'clientes']);
    const wantsCatalog = includeModuleContext || wantsCatalogByIntent || this.hasAnyToken(tokens, ['producto', 'productos', 'catalogo', 'catálogo', 'precio', 'precios']);
    const wantsContracts = includeModuleContext || this.hasAnyToken(tokens, ['contrato', 'nomina', 'nómina', 'salario', 'clausula', 'cláusula']);
    const wantsQuotes = includeModuleContext || this.hasAnyToken(tokens, ['cotizacion', 'cotizaciones', 'ticket', 'propuesta']);
    const wantsSales = includeModuleContext || this.hasAnyToken(tokens, ['venta', 'ventas', 'comision', 'comisión']);
    const wantsOperations = includeModuleContext || this.hasAnyToken(tokens, ['orden', 'ordenes', 'órdenes', 'servicio', 'servicios', 'operacion', 'operación', 'operaciones', 'tecnico', 'técnico']);
    const wantsDocumentFlows = includeModuleContext || this.hasAnyToken(tokens, ['flujo', 'documental', 'documento', 'documentos', 'garantia', 'garantía']);
    const wantsAccounting = includeModuleContext || this.hasAnyToken(tokens, ['contabilidad', 'cierre', 'cierres', 'deposito', 'depósito', 'factura', 'pago']);
    const wantsSelf = includeModuleContext || this.isSelfInfoRequest(dto.message, dto.context);
    const wantsAdaptiveLearning = includeModuleContext || this.isAdaptiveLearningQuestion(dto.message, dto.context);

    const knowledge: KnowledgeRecord[] = [];

    // Always include a minimal, non-sensitive context explainer for the current screen/module.
    knowledge.push(...this.buildScreenContextKnowledge(dto));

    if (wantsAdaptiveLearning) {
      const adaptiveKnowledge = await this.buildAdaptiveKnowledge(user);
      knowledge.push(...adaptiveKnowledge);
    }

    const conversationKnowledge = this.buildConversationLearningKnowledge(dto);
    knowledge.push(...conversationKnowledge);

    if (wantsSelf) {
      const selfKnowledge = await this.buildSelfKnowledge(user, dto);
      knowledge.push(...selfKnowledge);
    }

    // CLIENTS: scope strictly to what the user can access.
    if ((wantsClients || dto.context.module === 'clientes') && this.canAccessClientData(user.role)) {
      const clientKnowledge = await this.buildClientKnowledge(user, dto);
      knowledge.push(...clientKnowledge);
    }

    if ((wantsCatalog || dto.context.module === 'catalogo') && this.canAccessModule(user.role, 'catalogo')) {
      const catalogKnowledge = await this.buildCatalogKnowledge(user, dto);
      knowledge.push(...catalogKnowledge);
    }

    if ((wantsOperations || dto.context.module === 'service-orders') && this.canAccessOperationsData(user.role)) {
      const operationsKnowledge = await this.buildServiceOrderKnowledge(user, dto);
      knowledge.push(...operationsKnowledge);
    }

    if ((wantsDocumentFlows || dto.context.module === 'document-flows') && this.canAccessDocumentFlowData(user.role)) {
      const documentFlowKnowledge = await this.buildDocumentFlowKnowledge(user, dto);
      knowledge.push(...documentFlowKnowledge);
    }

    if ((wantsContracts || dto.context.module === 'nomina') && this.canAccessContractData(user.role, dto.context.route)) {
      const contractKnowledge = await this.buildContractKnowledge(user, dto);
      knowledge.push(...contractKnowledge);
    }

    if ((wantsQuotes || dto.context.module === 'cotizaciones') && this.canAccessQuoteData(user.role)) {
      const quoteKnowledge = await this.buildQuoteKnowledge(user, dto);
      knowledge.push(...quoteKnowledge);
    }

    if ((wantsSales || dto.context.module === 'ventas') && this.canAccessSalesData(user.role)) {
      const salesKnowledge = await this.buildSalesKnowledge(user, dto);
      knowledge.push(...salesKnowledge);
    }

    if ((wantsAccounting || dto.context.module === 'contabilidad') && this.canAccessAccountingData(user.role)) {
      const accountingKnowledge = await this.buildAccountingKnowledge(user, dto);
      knowledge.push(...accountingKnowledge);
    }

    return knowledge;
  }

  private detectIntent(message: string, context: NormalizedAiContext): AiIntent {
    const tokens = new Set(this.tokenize(`${message} ${context.module} ${context.screenName ?? ''}`));

    if (this.isScreenExplanationRequest(message, context)) return 'explain-screen';
    if (this.isModuleExplanationRequest(message, context)) return 'explain-module';
    if (this.hasAnyToken(tokens, ['manual', 'interno', 'politica', 'política', 'regla', 'reglas', 'protocolo'])) return 'manual';
    if (this.hasAnyToken(tokens, ['orden', 'ordenes', 'órdenes', 'servicio', 'servicios', 'operacion', 'operación', 'operaciones', 'flujo', 'documental'])) return 'operations';
    if (this.hasAnyToken(tokens, ['cliente', 'clientes', 'telefono', 'teléfono', 'direccion', 'dirección'])) return 'clients';
    if (this.hasAnyToken(tokens, ['producto', 'productos', 'catalogo', 'catálogo', 'precio', 'precios', 'stock', 'inventario'])) return 'catalog';
    return 'general';
  }

  private isScreenExplanationRequest(message: string, context: NormalizedAiContext) {
    const text = (message ?? '').trim().toLowerCase();
    if (!text) return false;

    const hasScreenContext = (context.screenName ?? '').trim().length > 0 || (context.route ?? '').trim().length > 0;
    const patterns = [
      'explicame esta pantalla',
      'explícame esta pantalla',
      'explica esta pantalla',
      'que es esta pantalla',
      'qué es esta pantalla',
      'que hago aqui',
      'qué hago aquí',
      'que puedo hacer aqui',
      'qué puedo hacer aquí',
      'como se usa esta pantalla',
      'cómo se usa esta pantalla',
    ];

    const matched = patterns.some((p) => text.includes(p));
    return matched || (hasScreenContext && (text.includes('esta pantalla') || text.includes('pantalla actual')));
  }

  private isModuleExplanationRequest(message: string, context: NormalizedAiContext) {
    const text = (message ?? '').trim().toLowerCase();
    if (!text) return false;
    const hasModule = this.normalizeModuleKey(context.module) !== 'general';
    return (
      text.includes('este modulo') ||
      text.includes('este módulo') ||
      text.includes('que puedo hacer en este modulo') ||
      text.includes('qué puedo hacer en este módulo')
    ) && hasModule;
  }

  private buildScreenContextKnowledge(dto: ChatAiAssistantDto): KnowledgeRecord[] {
    const module = this.normalizeModuleKey(dto.context.module);
    const screen = (dto.context.screenName ?? '').trim();
    const route = (dto.context.route ?? '').trim();
    const entityType = (dto.context.entityType ?? '').trim();
    const entityId = (dto.context.entityId ?? '').trim();
    const intent = this.detectIntent(dto.message, dto.context);

    const contextLines = [
      `Módulo: ${module || 'general'}.`,
      screen ? `Pantalla: ${screen}.` : null,
      route ? `Ruta: ${route}.` : null,
      entityType ? `Entidad: ${entityType}${entityId ? ` (${entityId})` : ''}.` : null,
    ].filter((x): x is string => !!x);

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-context:current',
        module || 'general',
        'contexto',
        'Contexto actual (pantalla y módulo)',
        contextLines.join('\n'),
      ),
    ];

    const moduleHelp = this.staticModuleOverview(module);
    if (moduleHelp) {
      result.push(
        this.createAppKnowledgeRecord(
          `app-context:module:${module}`, 
          module,
          'modulo',
          `Guía rápida del módulo: ${this.prettyModuleName(module)}`,
          moduleHelp,
        ),
      );
    }

    const screenHelp = this.staticScreenHelp(module, screen);
    if (screenHelp) {
      result.push(
        this.createAppKnowledgeRecord(
          `app-context:screen:${module}:${this.slugify(screen || 'pantalla')}`,
          module,
          'pantalla',
          screen ? `Cómo usar: ${screen}` : 'Cómo usar esta pantalla',
          screenHelp,
        ),
      );
    }

    // If user explicitly asks to explain the screen/module, add a short instruction on how to ask for data.
    if (intent === 'explain-screen' || intent === 'explain-module') {
      result.push(
        this.createAppKnowledgeRecord(
          'app-context:tips',
          module || 'general',
          'guia-app',
          'Cómo pedirme información útil',
          'Para ayudarte mejor, dime qué objetivo tienes (ej: crear una orden, buscar un cliente, ver un producto, revisar una regla). Si se trata de una entidad, indícame el nombre/ID/telefono del cliente, o el número de servicio, o el producto.',
        ),
      );
    }

    return result;
  }

  private prettyModuleName(module: string) {
    switch (this.normalizeModuleKey(module)) {
      case 'clientes':
        return 'Clientes';
      case 'catalogo':
        return 'Catálogo';
      case 'ventas':
        return 'Ventas';
      case 'cotizaciones':
        return 'Cotizaciones';
      case 'service-orders':
        return 'Operaciones';
      case 'document-flows':
        return 'Flujo documental';
      case 'media-gallery':
        return 'Galería media';
      case 'contabilidad':
        return 'Contabilidad';
      case 'nomina':
        return 'Nómina';
      case 'manual-interno':
        return 'Manual interno';
      case 'configuracion':
        return 'Configuración';
      case 'administracion':
        return 'Administración';
      default:
        return 'FULLTECH';
    }
  }

  private staticModuleOverview(module: string): string | null {
    switch (this.normalizeModuleKey(module)) {
      case 'clientes':
        return (
          'Este módulo gestiona la información de clientes.\n' +
          'Puedes buscar clientes, crear nuevos, editar datos y consultar historial según tu rol.\n' +
          'Para buscar: dime el nombre o teléfono.'
        );
      case 'catalogo':
        return (
          'Este módulo muestra el catálogo de productos.\n' +
          'Puedes consultar productos por categoría, existencia/stock y precios (según permisos).\n' +
          'Para consultar: dime el nombre del producto o categoría.'
        );
      case 'manual-interno':
        return (
          'Este módulo contiene reglas oficiales, políticas, procedimientos y guías.\n' +
          'Si preguntas por una regla, dime el tema (ej: garantía, pagos, protocolos, uso de teléfono).' 
        );
      case 'cotizaciones':
        return (
          'Este módulo se usa para crear y revisar cotizaciones.\n' +
          'Puedes preparar propuestas, ver historial por cliente y validar reglas comerciales del Manual Interno.'
        );
      case 'service-orders':
        return (
          'Este módulo gestiona operaciones y órdenes de servicio.\n' +
          'Puedes revisar estado, cliente relacionado, técnico asignado y próximos pasos operativos.'
        );
      case 'document-flows':
        return (
          'Este módulo controla el flujo documental por orden.\n' +
          'Puedes revisar preparación, aprobación y envío de factura o garantía según la orden seleccionada.'
        );
      case 'media-gallery':
        return (
          'Este módulo concentra evidencias visuales y multimedia de trabajos realizados.\n' +
          'Puedo explicarte la pantalla y el propósito de sus filtros.'
        );
      case 'contabilidad':
        return (
          'Este módulo agrupa tareas contables (cierres, depósitos, facturas, pagos pendientes) según permisos.\n' +
          'Si me dices qué pantalla estás usando, te explico el flujo.'
        );
      case 'nomina':
        return (
          'Este módulo maneja información sensible de nómina.\n' +
          'Solo usuarios autorizados pueden acceder a datos de terceros; sí puedes consultar tus propios datos si están autorizados.'
        );
      default:
        return null;
    }
  }

  private staticScreenHelp(module: string, screenName?: string): string | null {
    const screen = (screenName ?? '').trim().toLowerCase();
    const mod = this.normalizeModuleKey(module);

    if (mod === 'clientes') {
      if (screen.includes('nuevo')) {
        return 'En Nuevo cliente puedes registrar un cliente. Completa nombre, teléfono y dirección si aplica, luego guarda.';
      }
      if (screen.includes('detalle')) {
        return 'En Detalle de cliente puedes ver y editar datos del cliente, y abrir historial relacionado (cotizaciones/servicios) según permisos.';
      }
      if (screen.includes('clientes')) {
        return 'En Clientes puedes buscar y abrir perfiles. Usa nombre/teléfono para encontrar rápido.';
      }
    }

    if (mod === 'catalogo') {
      if (screen.includes('cat')) {
        return 'En Catálogo puedes consultar productos por categoría y revisar disponibilidad/precios según permisos.';
      }
    }

    if (mod === 'cotizaciones') {
      if (screen.includes('historial')) {
        return 'En Historial de cotizaciones puedes ver cotizaciones anteriores por cliente y seleccionar una para revisar/usar.';
      }
      if (screen.includes('cotizacion')) {
        return 'En Cotizaciones puedes crear o revisar propuestas. Si ya tienes un cliente, abre su historial para reutilizar información.';
      }
    }

    if (mod === 'service-orders') {
      if (screen.includes('crear')) {
        return 'En Crear orden registras una nueva operación vinculada a un cliente y una cotización. Completa tipo de servicio, categoría, fecha programada y responsable si aplica.';
      }
      if (screen.includes('detalle')) {
        return 'En Detalle de orden puedes revisar estado, cliente, técnico asignado, notas técnicas, evidencias y reportes relacionados con la operación actual.';
      }
      return 'En Operaciones puedes revisar órdenes de servicio, su estado y el seguimiento operativo de cada caso.';
    }

    if (mod === 'document-flows') {
      if (screen.includes('detalle')) {
        return 'En Detalle documental puedes revisar el estado del flujo de factura y garantía para la orden actual, así como lo pendiente antes del envío.';
      }
      return 'En Flujo documental puedes ver el estado de cada expediente documental asociado a órdenes de servicio.';
    }

    if (mod === 'media-gallery') {
      return 'En Galería media puedes revisar imágenes y videos asociados a evidencias del trabajo realizado y navegar por filtros de tipo o estado.';
    }

    if (mod === 'ponche') {
      if (screen.includes('historial')) {
        return 'En Historial de ponches puedes revisar registros previos de entrada, salida, almuerzo o permisos.';
      }
      return 'En Ponche puedes registrar entradas y salidas laborales o consultar tu historial.';
    }

    if (mod === 'contabilidad') {
      if (screen.includes('cierres')) return 'En Cierres diarios registras/resumes cierres del día según permisos.';
      if (screen.includes('factura')) return 'En Facturas fiscales gestionas facturación fiscal según permisos.';
      if (screen.includes('pagos')) return 'En Pagos pendientes revisas pagos que faltan por completar según permisos.';
      if (screen.includes('contabilidad')) return 'En Contabilidad tienes accesos a cierres, depósitos, facturas y pagos pendientes según permisos.';
    }

    if (mod === 'nomina') {
      if (screen.includes('mis pagos') || screen.includes('pagos')) return 'En Mis pagos puedes consultar tus pagos. No puedo mostrar nómina de terceros.';
      if (screen.includes('nómina') || screen.includes('nomina')) return 'En Nómina se gestiona información sensible de empleados según permisos.';
    }

    if (mod === 'manual-interno') {
      if (screen.includes('manual')) return 'En Manual interno puedes consultar reglas oficiales, políticas y procedimientos. Pídeme una regla por tema.';
    }

    return null;
  }

  private slugify(value: string) {
    return (value ?? '')
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '');
  }

  private isLikelyCatalogLookup(dto: ChatAiAssistantDto, tokens: Set<string>) {
    const module = this.normalizeModuleKey(dto.context.module);
    const searchTerms = this.extractMeaningfulQueryTerms(dto.message, {
      limit: 6,
      extraNoise: [
        'conocer',
        'conoce',
        'conoces',
        'saber',
        'sabe',
        'empresa',
        'empresas',
        'emprs',
        'fulltech',
        'todos',
        'todas',
        'producto',
        'productos',
        'catalogo',
        'catalogos',
        'catálogo',
        'precio',
        'precios',
        'disponible',
        'disponibles',
        'disponibilidad',
        'inventario',
        'stock',
      ],
    });

    if (['catalogo', 'cotizaciones', 'ventas'].includes(module) && searchTerms.length > 0) {
      return true;
    }

    return this.hasAnyToken(tokens, [
      'producto',
      'productos',
      'catalogo',
      'catálogo',
      'precio',
      'precios',
      'stock',
      'inventario',
      'disponible',
      'disponibilidad',
      'hay',
      'tienen',
      'busca',
      'buscame',
      'muestrame',
      'muéstrame',
      'cuesta',
      'vale',
    ]) && searchTerms.length > 0;
  }

  private isLikelyClientLookup(dto: ChatAiAssistantDto, tokens: Set<string>) {
    const module = this.normalizeModuleKey(dto.context.module);
    const searchTerms = this.extractMeaningfulQueryTerms(dto.message, {
      limit: 6,
      extraNoise: [
        'cliente',
        'clientes',
        'telefono',
        'teléfono',
        'correo',
        'email',
        'direccion',
        'dirección',
        'contacto',
      ],
    });
    const phoneTerms = this.extractNumericQueryTerms(dto.message);

    if (['clientes', 'ventas', 'cotizaciones'].includes(module)) {
      return searchTerms.length > 0 || phoneTerms.length > 0;
    }

    return this.hasAnyToken(tokens, [
      'cliente',
      'clientes',
      'telefono',
      'teléfono',
      'correo',
      'email',
      'direccion',
      'dirección',
      'contacto',
      'whatsapp',
    ]) || phoneTerms.length > 0;
  }

  private isAdaptiveLearningQuestion(message: string, context: NormalizedAiContext) {
    const tokens = new Set(this.tokenize(`${message} ${context.module} ${context.screenName ?? ''}`));
    return this.hasAnyToken(tokens, [
      'aprender',
      'aprende',
      'aprendiendo',
      'aprendizaje',
      'crecer',
      'creciendo',
      'actualizar',
      'actualizando',
      'datos',
      'tablas',
      'conocimiento',
      'memoria',
      'sistema',
    ]);
  }

  private async buildAdaptiveKnowledge(user: { id: string; role: Role }): Promise<KnowledgeRecord[]> {
    const ownerId = await this.resolveCompanyOwnerId(user.id);

    const clientWhere: Prisma.ClientWhereInput =
      user.role === Role.TECNICO
        ? {
            isDeleted: false,
            OR: [
              { ownerId: user.id },
              { services: { some: { OR: [{ technicianId: user.id }, { createdByUserId: user.id }] } } },
            ],
          }
        : { isDeleted: false };
    const salesWhere: Prisma.SaleWhereInput = user.role === Role.ADMIN ? {} : { userId: user.id };
    const quotesWhere: Prisma.CotizacionWhereInput = user.role === Role.ADMIN ? {} : { createdByUserId: user.id };

    const [
      manualCount,
      clientCount,
      salesCount,
      quoteCount,
      latestManual,
      latestClient,
      latestSale,
      latestQuote,
      fallbackProductCount,
    ] = await this.prisma.$transaction([
      this.prisma.companyManualEntry.count({ where: { ownerId, published: true } }),
      this.prisma.client.count({ where: clientWhere }),
      this.prisma.sale.count({ where: salesWhere }),
      this.prisma.cotizacion.count({ where: quotesWhere }),
      this.prisma.companyManualEntry.findFirst({
        where: { ownerId, published: true },
        orderBy: { updatedAt: 'desc' },
        select: { title: true, updatedAt: true },
      }),
      this.prisma.client.findFirst({
        where: clientWhere,
        orderBy: { updatedAt: 'desc' },
        select: { nombre: true, updatedAt: true },
      }),
      this.prisma.sale.findFirst({
        where: salesWhere,
        orderBy: { updatedAt: 'desc' },
        select: { saleDate: true, customer: { select: { nombre: true } } },
      }),
      this.prisma.cotizacion.findFirst({
        where: quotesWhere,
        orderBy: { updatedAt: 'desc' },
        select: { customerName: true, updatedAt: true },
      }),
      this.prisma.product.count(),
    ]);

    let productCount = fallbackProductCount;
    try {
      const liveCatalog = await this.catalogProducts.findAll();
      if (liveCatalog.total > 0) {
        productCount = liveCatalog.total;
      }
    } catch {
      productCount = fallbackProductCount;
    }

    const summary = [
      'El asistente usa conocimiento vivo del sistema, no solo respuestas estaticas.',
      'Por eso su contexto crece cuando aumentan los datos autorizados y las entradas publicadas del Manual Interno.',
      `Ahora mismo puede apoyarse en ${manualCount} normas publicadas, ${clientCount} clientes, ${productCount} productos, ${salesCount} ventas y ${quoteCount} cotizaciones visibles para tu alcance.`,
      'Cada nueva consulta vuelve a leer estos datos y por eso el asistente puede crecer junto con las tablas del sistema.',
    ].join(' ');

    const recents = [
      latestManual ? `Manual actualizado recientemente: ${latestManual.title} (${this.formatKnowledgeDate(latestManual.updatedAt)}).` : null,
      latestClient ? `Cliente reciente: ${latestClient.nombre} (${this.formatKnowledgeDate(latestClient.updatedAt)}).` : null,
      latestSale ? `Venta reciente: ${latestSale.customer?.nombre ?? 'N/D'} (${this.formatKnowledgeDate(latestSale.saleDate)}).` : null,
      latestQuote ? `Cotizacion reciente: ${latestQuote.customerName} (${this.formatKnowledgeDate(latestQuote.updatedAt)}).` : null,
    ].filter((item): item is string => !!item);

    return [
      this.createAppKnowledgeRecord(
        'app-data:growth-summary',
        'general',
        'dato-autorizado',
        'Base de conocimiento viva del asistente',
        summary,
      ),
      this.createAppKnowledgeRecord(
        'app-data:growth-recent',
        'general',
        'dato-autorizado',
        'Actividad reciente del sistema',
        recents.length > 0
          ? recents.join(' ')
          : 'No hay cambios recientes resumidos en este momento, pero el asistente seguira leyendo datos nuevos en cada consulta.',
      ),
      this.createAppKnowledgeRecord(
        'app-data:growth-policy',
        'general',
        'politica-app',
        'Como crece el conocimiento del asistente',
        'El asistente puede crecer con datos nuevos del sistema, productos nuevos, clientes nuevos, ventas nuevas y nuevas entradas publicadas del Manual Interno. La conversacion actual le aporta memoria reciente, pero las reglas oficiales y los datos autorizados tienen prioridad.',
      ),
    ];
  }

  private buildConversationLearningKnowledge(dto: ChatAiAssistantDto): KnowledgeRecord[] {
    const history = this.normalizeHistory(dto.history).slice(-12);
    if (history.length === 0) return [];

    const recentUserMessages = history.filter((item) => item.role === 'user').slice(-5);
    const recentAssistantMessages = history.filter((item) => item.role === 'assistant').slice(-3);
    const repeatedTopics = this.extractMeaningfulQueryTerms(
      recentUserMessages.map((item) => item.content).join(' '),
      { limit: 8 },
    );

    const parts = [
      'Contexto acumulado de la conversacion actual.',
      recentUserMessages.length > 0
        ? `Ultimas solicitudes del usuario: ${recentUserMessages.map((item) => this.buildExcerpt(item.content)).join(' | ')}`
        : null,
      repeatedTopics.length > 0
        ? `Temas relevantes repetidos en este hilo: ${repeatedTopics.join(', ')}.`
        : null,
      recentAssistantMessages.length > 0
        ? `Ultimas respuestas del asistente: ${recentAssistantMessages.map((item) => this.buildExcerpt(item.content)).join(' | ')}`
        : null,
      'Este contexto funciona como memoria reciente dentro del mismo hilo.',
    ].filter((item): item is string => !!item);

    return [
      this.createAppKnowledgeRecord(
        'app-data:conversation-context',
        'general',
        'dato-autorizado',
        'Memoria reciente de la conversacion',
        parts.join(' '),
      ),
    ];
  }

  private async buildPersistentMemoryKnowledge(
    user: { id: string; role: Role },
    dto: ChatAiAssistantDto,
  ): Promise<KnowledgeRecord[]> {
    try {
      const ownerId = await this.resolveCompanyOwnerId(user.id);
      const memoryRows = await this.prisma.$queryRaw<PersistedAssistantMemoryRow[]>(Prisma.sql`
        SELECT
          id::text AS id,
          module,
          scope,
          topic_key AS "topicKey",
          title,
          summary,
          keywords,
          source_count AS "sourceCount",
          last_source_at AS "lastSourceAt",
          "createdAt",
          "updatedAt"
        FROM ai_assistant_memories
        WHERE owner_id = ${ownerId}
          AND user_id = ${user.id}
        ORDER BY last_source_at DESC
        LIMIT 24
      `);

      const recentTurns = await this.prisma.$queryRaw<PersistedConversationTurnRow[]>(Prisma.sql`
        SELECT
          user_message AS "userMessage",
          assistant_response AS "assistantResponse",
          module,
          "createdAt"
        FROM ai_assistant_conversation_turns
        WHERE owner_id = ${ownerId}
          AND user_id = ${user.id}
        ORDER BY "createdAt" DESC
        LIMIT 4
      `);

      const tokens = new Set(this.tokenize(`${dto.message} ${dto.context.module ?? ''} ${dto.context.screenName ?? ''}`));
      const rankedMemories = memoryRows
        .map((row) => {
          const keywordText = this.parseStoredKeywords(row.keywords).join(' ');
          const haystack = `${row.title} ${row.summary} ${row.module} ${row.topicKey} ${keywordText}`;
          const rowTokens = new Set(this.tokenize(haystack));
          let score = 0;
          for (const token of tokens) {
            if (rowTokens.has(token)) score += token.length >= 5 ? 2 : 1;
          }
          if (this.normalizeModuleKey(row.module) === this.normalizeModuleKey(dto.context.module)) score += 3;
          if (score === 0 && this.normalizeModuleKey(row.module) === this.normalizeModuleKey(dto.context.module)) score = 1;
          return { row, score };
        })
        .filter((item) => item.score > 0)
        .sort((a, b) => b.score - a.score)
        .slice(0, 6)
        .map((item) => item.row);

      const knowledge = rankedMemories.map((row) => this.createAppKnowledgeRecord(
        `app-memory:${row.id}`,
        row.module || 'general',
        'memoria',
        row.title,
        `${row.summary}\n\nFuentes acumuladas: ${row.sourceCount}. Ultima actualizacion: ${this.formatKnowledgeDate(this.toDateValue(row.lastSourceAt))}.`,
      ));

      if (recentTurns.length > 0) {
        const lines = recentTurns.map((turn) => (
          `${this.formatKnowledgeDate(this.toDateValue(turn.createdAt))}: Usuario dijo "${this.buildExcerpt(turn.userMessage)}" y el asistente respondio "${this.buildExcerpt(turn.assistantResponse)}".`
        ));
        knowledge.push(
          this.createAppKnowledgeRecord(
            'app-memory:recent-turns',
            dto.context.module || 'general',
            'memoria',
            'Continuidad entre sesiones del asistente',
            lines.join(' '),
          ),
        );
      }

      return knowledge;
    } catch (error) {
      this.logDebug('ai.memory.read_skip', {
        message: error instanceof Error ? error.message : `${error}`,
      });
      return [];
    }
  }

  private async finalizeChatResponse(
    user: { id: string; role: Role },
    dto: ChatAiAssistantDto & { context: NormalizedAiContext },
    response: AiAssistantChatResponse,
    knowledge: KnowledgeRecord[],
  ) {
    await this.persistLearningArtifacts(user, dto, response, knowledge);
    return response;
  }

  private async persistLearningArtifacts(
    user: { id: string; role: Role },
    dto: ChatAiAssistantDto & { context: NormalizedAiContext },
    response: AiAssistantChatResponse,
    knowledge: KnowledgeRecord[],
  ) {
    try {
      const ownerId = await this.resolveCompanyOwnerId(user.id);
      const citationsJson = JSON.stringify(response.citations ?? []);

      await this.prisma.$executeRaw(Prisma.sql`
        INSERT INTO ai_assistant_conversation_turns (
          id,
          owner_id,
          user_id,
          module,
          route,
          entity_type,
          entity_id,
          user_message,
          assistant_response,
          response_source,
          denied,
          citations,
          "createdAt"
        ) VALUES (
          gen_random_uuid(),
          ${ownerId},
          ${user.id},
          ${dto.context.module || 'general'},
          ${dto.context.route ?? null},
          ${dto.context.entityType ?? null},
          ${dto.context.entityId ?? null},
          ${dto.message},
          ${response.content},
          ${response.source},
          ${response.denied === true},
          CAST(${citationsJson} AS JSONB),
          CURRENT_TIMESTAMP
        )
      `);

      const notes = this.buildPersistentMemoryNotes(dto, response, knowledge);
      for (const note of notes) {
        await this.upsertPersistentMemory(ownerId, user.id, note);
      }
    } catch (error) {
      this.logDebug('ai.memory.persist_skip', {
        message: error instanceof Error ? error.message : `${error}`,
      });
    }
  }

  private buildPersistentMemoryNotes(
    dto: ChatAiAssistantDto & { context: NormalizedAiContext },
    response: AiAssistantChatResponse,
    knowledge: KnowledgeRecord[],
  ): AssistantMemoryNote[] {
    const module = dto.context.module || 'general';
    const moduleLabel = this.describeMemoryModule(module);
    const userTerms = this.extractMeaningfulQueryTerms(dto.message, { limit: 6 });
    const responseTerms = this.extractMeaningfulQueryTerms(response.content, {
      limit: 6,
      extraNoise: ['encontre', 'informacion', 'detalle', 'detalles', 'resumen', 'consulta'],
    });
    const mergedTerms = [...new Set([...userTerms, ...responseTerms])].slice(0, 10);
    const noteBody = `Consulta: ${this.buildExcerpt(dto.message)} Respuesta: ${this.buildExcerpt(response.content)}`;
    const notes: AssistantMemoryNote[] = [
      {
        scope: 'user',
        module,
        topicKey: `module:${module}`,
        title: `Memoria reciente del modulo ${moduleLabel}`,
        summary: noteBody,
        keywords: mergedTerms,
      },
    ];

    if (dto.context.entityType && dto.context.entityId) {
      notes.push({
        scope: 'user',
        module,
        topicKey: `entity:${dto.context.entityType}:${dto.context.entityId}`,
        title: `Seguimiento de ${dto.context.entityType}`,
        summary: `Entidad consultada dentro del modulo ${moduleLabel}. ${noteBody}`,
        keywords: [dto.context.entityType, dto.context.entityId, ...mergedTerms].slice(0, 10),
      });
    }

    const citedTitles = response.citations.map((item) => item.title).filter((item) => item.trim().length > 0);
    if (mergedTerms.length > 0) {
      notes.push({
        scope: 'user',
        module,
        topicKey: `topic:${module}:${mergedTerms.slice(0, 3).join('-')}`,
        title: `Tema recurrente en ${moduleLabel}`,
        summary: citedTitles.length > 0
          ? `${noteBody} Referencias usadas: ${citedTitles.slice(0, 3).join(', ')}.`
          : noteBody,
        keywords: [...mergedTerms, ...citedTitles.flatMap((item) => this.tokenize(item))].slice(0, 12),
      });
    }

    const filtered = notes.filter((note, index, all) => all.findIndex((item) => item.topicKey === note.topicKey) === index);
    return filtered.slice(0, 3);
  }

  private async upsertPersistentMemory(ownerId: string, userId: string, note: AssistantMemoryNote) {
    const existing = await this.prisma.$queryRaw<Array<{
      summary: string;
      keywords: Prisma.JsonValue | null;
      sourceCount: number;
    }>>(Prisma.sql`
      SELECT summary, keywords, source_count AS "sourceCount"
      FROM ai_assistant_memories
      WHERE owner_id = ${ownerId}
        AND user_id = ${userId}
        AND scope = ${note.scope}
        AND topic_key = ${note.topicKey}
      LIMIT 1
    `);

    const mergedSummary = this.mergeMemorySummary(existing[0]?.summary ?? '', note.summary);
    const mergedKeywords = this.mergeMemoryKeywords(this.parseStoredKeywords(existing[0]?.keywords ?? null), note.keywords);
    const mergedKeywordsJson = JSON.stringify(mergedKeywords);

    if (existing.length > 0) {
      await this.prisma.$executeRaw(Prisma.sql`
        UPDATE ai_assistant_memories
        SET
          module = ${note.module},
          title = ${note.title},
          summary = ${mergedSummary},
          keywords = CAST(${mergedKeywordsJson} AS JSONB),
          source_count = source_count + 1,
          last_source_at = CURRENT_TIMESTAMP,
          "updatedAt" = CURRENT_TIMESTAMP
        WHERE owner_id = ${ownerId}
          AND user_id = ${userId}
          AND scope = ${note.scope}
          AND topic_key = ${note.topicKey}
      `);
      return;
    }

    await this.prisma.$executeRaw(Prisma.sql`
      INSERT INTO ai_assistant_memories (
        id,
        owner_id,
        user_id,
        scope,
        module,
        topic_key,
        title,
        summary,
        keywords,
        source_count,
        last_source_at,
        "createdAt",
        "updatedAt"
      ) VALUES (
        gen_random_uuid(),
        ${ownerId},
        ${userId},
        ${note.scope},
        ${note.module},
        ${note.topicKey},
        ${note.title},
        ${mergedSummary},
        CAST(${mergedKeywordsJson} AS JSONB),
        1,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      )
    `);
  }

  private mergeMemorySummary(existingSummary: string, incomingSummary: string) {
    const items = [
      ...existingSummary.split('\n').map((item) => item.trim()).filter((item) => item.length > 0),
      incomingSummary.trim(),
    ];
    const deduped: string[] = [];
    const seen = new Set<string>();

    for (const item of items) {
      const key = item.toLowerCase();
      if (!key || seen.has(key)) continue;
      seen.add(key);
      deduped.push(item);
    }

    let trimmed = deduped.slice(-6);
    while (trimmed.join('\n').length > 900 && trimmed.length > 1) {
      trimmed = trimmed.slice(1);
    }
    return trimmed.join('\n');
  }

  private mergeMemoryKeywords(existing: string[], incoming: string[]) {
    return [...new Set([...existing, ...incoming].map((item) => item.trim()).filter((item) => item.length >= 3))].slice(0, 14);
  }

  private parseStoredKeywords(raw: Prisma.JsonValue | null) {
    if (!raw || !Array.isArray(raw)) return [];
    return raw.map((item) => `${item}`.trim()).filter((item) => item.length > 0);
  }

  private describeMemoryModule(module: string) {
    switch (this.normalizeModuleKey(module)) {
      case 'manual-interno':
        return 'Manual Interno';
      case 'catalogo':
        return 'Catalogo';
      case 'clientes':
        return 'Clientes';
      case 'ventas':
        return 'Ventas';
      case 'cotizaciones':
        return 'Cotizaciones';
      case 'nomina':
        return 'Nomina';
      case 'profile':
        return 'Perfil';
      default:
        return 'General';
    }
  }

  private toDateValue(value: Date | string | null) {
    if (!value) return null;
    if (value instanceof Date) return value;
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  private isSelfInfoRequest(message: string, context: NormalizedAiContext) {
    const raw = message.trim().toLowerCase();
    if (context.module === 'profile' || context.module === 'nomina') {
      return true;
    }

    return (
      /(^|\s)(mi|mis|yo|mio|mía|mias|mios)(\s|$)/i.test(raw) ||
      raw.includes('mi nombre') ||
      raw.includes('mi correo') ||
      raw.includes('mi email') ||
      raw.includes('mi telefono') ||
      raw.includes('mi teléfono') ||
      raw.includes('mi rol') ||
      raw.includes('mi usuario') ||
      raw.includes('mi perfil') ||
      raw.includes('mi cuenta') ||
      raw.includes('mis datos') ||
      raw.includes('mis pagos') ||
      raw.includes('mi contrato') ||
      raw.includes('mi salario') ||
      raw.includes('mi sueldo') ||
      raw.includes('de mi')
    );
  }

  private isOtherUserSensitiveRequest(
    user: { id: string; role: Role },
    message: string,
    context: NormalizedAiContext,
  ) {
    const targetEntityType = (context.entityType ?? '').trim().toLowerCase();
    const targetEntityId = (context.entityId ?? '').trim();
    const referencesAnotherUser = targetEntityType === 'user' && targetEntityId.length > 0 && targetEntityId !== user.id;

    if (!referencesAnotherUser) return false;

    const tokens = new Set(this.tokenize(`${message} ${context.module} ${context.screenName ?? ''}`));
    return this.hasAnyToken(tokens, [
      'usuario',
      'usuarios',
      'empleado',
      'empleados',
      'perfil',
      'correo',
      'email',
      'telefono',
      'teléfono',
      'rol',
      'nomina',
      'nómina',
      'contrato',
      'salario',
      'sueldo',
      'pago',
      'pagos',
      'datos',
      'informacion',
      'información',
    ]);
  }

  private async buildSelfKnowledge(
    user: { id: string; role: Role },
    dto: ChatAiAssistantDto,
  ): Promise<KnowledgeRecord[]> {
    const record = await this.prisma.user.findUnique({
      where: { id: user.id },
      select: {
        id: true,
        nombreCompleto: true,
        email: true,
        telefono: true,
        role: true,
        fechaIngreso: true,
        workContractJobTitle: true,
      },
    });

    if (!record) return [];

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        `app-data:self:${record.id}`,
        'profile',
        'dato-autorizado',
        'Perfil del usuario actual',
        `Tu nombre en la app es ${record.nombreCompleto}. Correo: ${record.email}. Teléfono: ${record.telefono}. Rol: ${record.role}. ${record.workContractJobTitle ? `Puesto: ${record.workContractJobTitle}. ` : ''}${record.fechaIngreso ? `Fecha de ingreso: ${record.fechaIngreso.toISOString().slice(0, 10)}.` : ''}`,
      ),
      this.createAppKnowledgeRecord(
        'app-data:self:privacy-scope',
        'profile',
        'politica-app',
        'Alcance de datos del usuario actual',
        'El asistente sí puede responder datos del usuario autenticado que está haciendo la consulta cuando esos datos fueron enviados como conocimiento autorizado. No puede responder datos personales de terceros.',
      ),
    ];

    if (dto.context.module === 'profile') {
      result.push(
        this.createAppKnowledgeRecord(
          'app-data:self:profile-help',
          'profile',
          'guia-app',
          'Ayuda del perfil',
          'En Perfil puedes revisar tu información personal dentro de la app. El asistente puede responder usando únicamente tus propios datos autorizados.',
        ),
      );
    }

    return result;
  }

  private selectKnowledgeForPrompt(input: {
    prompt: string;
    context: NormalizedAiContext;
    manualKnowledge: KnowledgeRecord[];
    staticHelp: KnowledgeRecord[];
    authorizedData: KnowledgeRecord[];
    all: KnowledgeRecord[];
  }): KnowledgeRecord[] {
    const rankedAll = this.rankKnowledgeForPrompt(input.prompt, input.context, input.all);
    const rankedManual = this.rankKnowledgeForPrompt(input.prompt, input.context, input.manualKnowledge);
    const rankedAuthorized = this.rankKnowledgeForPrompt(input.prompt, input.context, input.authorizedData);
    const rankedAuthorizedVisible = rankedAuthorized.filter((item) => this.isUserVisibleKnowledge(item));
    const rankedAuthorizedInternal = rankedAuthorized.filter((item) => !this.isUserVisibleKnowledge(item));
    const normalizedModule = this.normalizeModuleKey(input.context.module);
    const isSelfRequest = this.isSelfInfoRequest(input.prompt, input.context);
    const prioritizedSelfKnowledge = rankedAuthorizedVisible.filter(
      (item) =>
        item.id.startsWith('app-data:self:') ||
        item.id.startsWith('app-data:contract:') ||
        item.id === 'app-data:contracts-policy',
    );
    const remainingAuthorizedVisible = rankedAuthorizedVisible.filter(
      (item) => !prioritizedSelfKnowledge.some((candidate) => candidate.id === item.id),
    );
    const wantsManualDepth =
      normalizedModule === 'manual-interno' ||
      this.hasAnyToken(
        new Set(this.tokenize(`${input.prompt} ${input.context.screenName ?? ''}`)),
        ['manual', 'interno', 'politica', 'política', 'protocolo', 'regla', 'reglas'],
      );

    const limit = wantsManualDepth ? 28 : 20;
    const selected: KnowledgeRecord[] = [];
    const seenIds = new Set<string>();
    const intent = this.detectIntent(input.prompt, input.context);

    const addRecords = (items: KnowledgeRecord[], maxCount?: number) => {
      let added = 0;
      for (const item of items) {
        if (seenIds.has(item.id)) continue;
        selected.push(item);
        seenIds.add(item.id);
        added += 1;
        if (selected.length >= limit) return;
        if (maxCount != null && added >= maxCount) return;
      }
    };

    if (isSelfRequest) {
      addRecords(prioritizedSelfKnowledge, 6);
    }

    if (intent === 'explain-screen' || intent === 'explain-module') {
      // Force screen/module help to the top so "Explícame esta pantalla" never ends up using an unrelated manual entry.
      addRecords(
        rankedAuthorizedVisible.filter((item) => item.id.startsWith('app-context:')),
        6,
      );
      addRecords(
        rankedManual.filter((item) => item.category === 'modulo' && this.normalizeModuleKey(item.module) === normalizedModule),
        4,
      );
      addRecords(
        input.staticHelp.filter((item) => this.normalizeModuleKey(item.module) === normalizedModule),
        2,
      );
    }
    addRecords(
      input.staticHelp.filter(
        (item) => item.module === 'seguridad' || item.module === 'manual-interno',
      ),
      3,
    );
    addRecords(remainingAuthorizedVisible, wantsManualDepth ? 8 : 10);
    addRecords(
      rankedManual.filter(
        (item) =>
          this.normalizeModuleKey(item.module) === normalizedModule ||
          item.module === 'general' ||
          item.category === 'politicas',
      ),
      wantsManualDepth ? 14 : 8,
    );
    addRecords(rankedManual, wantsManualDepth ? 10 : 6);
    addRecords(rankedAuthorizedInternal, 3);
    addRecords(rankedAll, limit);

    return selected.slice(0, limit);
  }

  private rankKnowledgeForPrompt(prompt: string, context: NormalizedAiContext, knowledge: KnowledgeRecord[]): KnowledgeRecord[] {
    const tokens = new Set(this.tokenize(`${prompt} ${context.module} ${context.screenName ?? ''} ${context.entityType ?? ''}`));
    const normalizedModule = this.normalizeModuleKey(context.module);

    return knowledge
      .map((k) => {
        const haystack = `${k.title} ${k.summary ?? ''} ${k.content} ${k.module} ${k.category} ${(k.keywords ?? []).join(' ')}`;
        const kTokens = new Set(this.tokenize(haystack));

        let score = 0;
        for (const token of tokens) {
          if (kTokens.has(token)) score += token.length >= 5 ? 2 : 1;
        }

        if (this.normalizeModuleKey(k.module) === normalizedModule) score += 3;
        if (score === 0 && this.normalizeModuleKey(k.module) === normalizedModule) score = 1;
        if (k.severity === 'critical') score += 2;
        if (k.severity === 'warning') score += 1;

        return { k, score };
      })
      .filter((item) => item.score > 0)
      .sort((a, b) => b.score - a.score)
      .map((item) => item.k);
  }

  private buildServiceOrderWhereForUser(user: { id: string; role: Role }): Prisma.ServiceOrderWhereInput {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) {
      return {};
    }
    if (user.role === Role.TECNICO) {
      return {
        OR: [
          { assignedToId: user.id },
          { technicianConfirmedById: user.id },
          { createdById: user.id },
        ],
      };
    }

    return { createdById: user.id };
  }

  private async buildServiceOrderKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const accessibleWhere = this.buildServiceOrderWhereForUser(user);
    const count = await this.prisma.serviceOrder.count({ where: accessibleWhere });

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:service-orders-scope',
        'service-orders',
        'dato-autorizado',
        'Alcance autorizado de operaciones',
        user.role === Role.ADMIN || user.role === Role.ASISTENTE
          ? 'Puedes consultar operaciones visibles del sistema según el contexto y la pantalla actual.'
          : 'Puedo consultar operaciones relacionadas contigo o creadas por ti dentro del alcance autorizado del sistema.',
      ),
      this.createAppKnowledgeRecord(
        'app-data:service-orders-count',
        'service-orders',
        'dato-autorizado',
        'Resumen autorizado de operaciones',
        user.role === Role.ADMIN || user.role === Role.ASISTENTE
          ? `Actualmente hay ${count} órdenes de servicio visibles para esta consulta.`
          : `Actualmente tienes acceso a ${count} órdenes de servicio dentro de tu alcance operativo.`,
      ),
    ];

    const entityId = (dto.context.entityType ?? '').toLowerCase() === 'service-order'
      ? (dto.context.entityId ?? '').trim()
      : '';
    const searchTerms = this.extractMeaningfulQueryTerms(dto.message, {
      limit: 6,
      extraNoise: [
        'orden',
        'ordenes',
        'órdenes',
        'servicio',
        'servicios',
        'operacion',
        'operación',
        'operaciones',
        'tecnico',
        'técnico',
        'cliente',
        'detalle',
        'resumen',
        'busca',
        'muestrame',
        'muéstrame',
      ],
    });

    if (!entityId && searchTerms.length === 0) {
      return result;
    }

    if (entityId) {
      const order = await this.prisma.serviceOrder.findFirst({
        where: { ...accessibleWhere, id: entityId },
        include: {
          client: true,
          createdBy: { select: { id: true, nombreCompleto: true } },
          assignedTo: { select: { id: true, nombreCompleto: true } },
        },
      });
      if (order) {
        result.push(
          this.createAppKnowledgeRecord(
            `app-data:service-order:${order.id}`,
            'service-orders',
            'dato-autorizado',
            `Orden ${this.compactEntityId(order.id)}`,
            this.describeServiceOrder(order),
          ),
        );
      }
      return result;
    }

    const orderFilters: Prisma.ServiceOrderWhereInput[] = [
      ...searchTerms
        .filter((term) => this.isUuidLike(term))
        .map((term) => ({ id: term })),
      ...searchTerms.map((term) => ({
        technicalNote: { contains: term, mode: 'insensitive' as const },
      })),
      ...searchTerms.map((term) => ({
        extraRequirements: { contains: term, mode: 'insensitive' as const },
      })),
      ...searchTerms.map((term) => ({
        client: { nombre: { contains: term, mode: 'insensitive' as const } },
      })),
    ];

    const matchingOrders = await this.prisma.serviceOrder.findMany({
      where: {
        ...accessibleWhere,
        OR: orderFilters,
      },
      include: {
        client: true,
        createdBy: { select: { id: true, nombreCompleto: true } },
        assignedTo: { select: { id: true, nombreCompleto: true } },
      },
      orderBy: [{ updatedAt: 'desc' }, { createdAt: 'desc' }],
      take: 8,
    });

    if (matchingOrders.length === 0) {
      result.push(
        this.createAppKnowledgeRecord(
          'app-data:service-order-search-none',
          'service-orders',
          'dato-autorizado',
          'Operación no encontrada',
          `No encontré órdenes de servicio autorizadas que coincidan con: ${searchTerms.join(', ')}.`,
        ),
      );
      return result;
    }

    result.push(
      ...matchingOrders.map((order) =>
        this.createAppKnowledgeRecord(
          `app-data:service-order-match:${order.id}`,
          'service-orders',
          'dato-autorizado',
          `Orden ${this.compactEntityId(order.id)}`,
          this.describeServiceOrder(order),
        ),
      ),
    );

    return result;
  }

  private async buildDocumentFlowKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const accessibleOrderWhere = this.buildServiceOrderWhereForUser(user);
    const accessibleFlowWhere: Prisma.OrderDocumentFlowWhereInput = {
      order: accessibleOrderWhere,
    };
    const count = await this.prisma.orderDocumentFlow.count({ where: accessibleFlowWhere });

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:document-flows-scope',
        'document-flows',
        'dato-autorizado',
        'Alcance autorizado de flujo documental',
        'Puedo consultar flujos documentales asociados a órdenes visibles dentro de tu alcance operativo.',
      ),
      this.createAppKnowledgeRecord(
        'app-data:document-flows-count',
        'document-flows',
        'dato-autorizado',
        'Resumen autorizado de flujo documental',
        `Actualmente hay ${count} flujos documentales visibles para esta consulta.`,
      ),
    ];

    const entityId = (dto.context.entityType ?? '').toLowerCase() === 'service-order'
      ? (dto.context.entityId ?? '').trim()
      : '';
    const searchTerms = this.extractMeaningfulQueryTerms(dto.message, {
      limit: 6,
      extraNoise: [
        'flujo',
        'documental',
        'documento',
        'documentos',
        'factura',
        'garantia',
        'garantía',
        'orden',
        'servicio',
        'detalle',
        'resumen',
      ],
    });

    if (!entityId && searchTerms.length === 0) {
      return result;
    }

    if (entityId) {
      const flow = await this.prisma.orderDocumentFlow.findFirst({
        where: { ...accessibleFlowWhere, orderId: entityId },
        include: {
          order: {
            include: {
              client: true,
            },
          },
          preparedBy: { select: { id: true, nombreCompleto: true } },
          approvedBy: { select: { id: true, nombreCompleto: true } },
        },
      });
      if (flow) {
        result.push(
          this.createAppKnowledgeRecord(
            `app-data:document-flow:${flow.orderId}`,
            'document-flows',
            'dato-autorizado',
            `Flujo documental ${this.compactEntityId(flow.orderId)}`,
            this.describeDocumentFlow(flow),
          ),
        );
      }
      return result;
    }

    const documentFlowFilters: Prisma.OrderDocumentFlowWhereInput[] = [
      ...searchTerms
        .filter((term) => this.isUuidLike(term))
        .map((term) => ({ orderId: term })),
      ...searchTerms.map((term) => ({
        order: { client: { nombre: { contains: term, mode: 'insensitive' as const } } },
      })),
    ];

    const matchingFlows = await this.prisma.orderDocumentFlow.findMany({
      where: {
        ...accessibleFlowWhere,
        OR: documentFlowFilters,
      },
      include: {
        order: {
          include: {
            client: true,
          },
        },
        preparedBy: { select: { id: true, nombreCompleto: true } },
        approvedBy: { select: { id: true, nombreCompleto: true } },
      },
      orderBy: [{ updatedAt: 'desc' }, { createdAt: 'desc' }],
      take: 8,
    });

    if (matchingFlows.length === 0) {
      result.push(
        this.createAppKnowledgeRecord(
          'app-data:document-flow-search-none',
          'document-flows',
          'dato-autorizado',
          'Flujo documental no encontrado',
          `No encontré flujos documentales autorizados que coincidan con: ${searchTerms.join(', ')}.`,
        ),
      );
      return result;
    }

    result.push(
      ...matchingFlows.map((flow) =>
        this.createAppKnowledgeRecord(
          `app-data:document-flow-match:${flow.orderId}`,
          'document-flows',
          'dato-autorizado',
          `Flujo documental ${this.compactEntityId(flow.orderId)}`,
          this.describeDocumentFlow(flow),
        ),
      ),
    );

    return result;
  }

  private compactEntityId(value: string) {
    const normalized = (value ?? '').replace(/-/g, '').trim().toUpperCase();
    if (!normalized) return 'SIN-ID';
    return normalized.length > 8 ? normalized.slice(0, 8) : normalized;
  }

  private isUuidLike(value: string) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      (value ?? '').trim(),
    );
  }

  private describeServiceOrder(order: {
    id: string;
    status: unknown;
    serviceType: unknown;
    category: unknown;
    scheduledFor?: Date | string | null;
    technicalNote?: string | null;
    extraRequirements?: string | null;
    client?: { nombre?: string | null; telefono?: string | null } | null;
    createdBy?: { nombreCompleto?: string | null } | null;
    assignedTo?: { nombreCompleto?: string | null } | null;
  }) {
    const clientName = order.client?.nombre?.trim() || 'Cliente no disponible';
    const phone = order.client?.telefono?.trim();
    const assignedTo = order.assignedTo?.nombreCompleto?.trim();
    const createdBy = order.createdBy?.nombreCompleto?.trim();
    const details = [
      `Orden ${this.compactEntityId(order.id)}.`,
      `Cliente: ${clientName}${phone ? ` (${phone})` : ''}.`,
      `Estado: ${this.humanizeEnum(order.status)}.`,
      `Tipo de servicio: ${this.humanizeEnum(order.serviceType)}.`,
      `Categoría: ${this.humanizeEnum(order.category)}.`,
      assignedTo ? `Técnico asignado: ${assignedTo}.` : 'Técnico asignado: pendiente.',
      createdBy ? `Creada por: ${createdBy}.` : null,
      order.scheduledFor ? `Programada para: ${this.formatKnowledgeDate(order.scheduledFor)}.` : null,
      (order.technicalNote ?? '').trim().length > 0
        ? `Nota técnica: ${this.buildExcerpt(order.technicalNote ?? '')}.`
        : null,
      (order.extraRequirements ?? '').trim().length > 0
        ? `Requerimientos: ${this.buildExcerpt(order.extraRequirements ?? '')}.`
        : null,
    ].filter((x): x is string => !!x);
    return details.join(' ');
  }

  private describeDocumentFlow(flow: {
    orderId: string;
    status: unknown;
    sentAt?: Date | string | null;
    invoiceFinalUrl?: string | null;
    warrantyFinalUrl?: string | null;
    updatedAt?: Date | string | null;
    order?: { client?: { nombre?: string | null } | null } | null;
    preparedBy?: { nombreCompleto?: string | null } | null;
    approvedBy?: { nombreCompleto?: string | null } | null;
  }) {
    const clientName = flow.order?.client?.nombre?.trim() || 'Cliente no disponible';
    const preparedBy = flow.preparedBy?.nombreCompleto?.trim();
    const approvedBy = flow.approvedBy?.nombreCompleto?.trim();
    const details = [
      `Flujo documental de la orden ${this.compactEntityId(flow.orderId)}.`,
      `Cliente relacionado: ${clientName}.`,
      `Estado actual: ${this.humanizeEnum(flow.status)}.`,
      flow.invoiceFinalUrl ? 'Factura final: disponible.' : 'Factura final: pendiente.',
      flow.warrantyFinalUrl ? 'Garantía final: disponible.' : 'Garantía final: pendiente.',
      preparedBy ? `Preparado por: ${preparedBy}.` : null,
      approvedBy ? `Aprobado por: ${approvedBy}.` : null,
      flow.sentAt ? `Enviado al cliente: ${this.formatKnowledgeDate(flow.sentAt)}.` : 'Envío al cliente: pendiente.',
      flow.updatedAt ? `Última actualización: ${this.formatKnowledgeDate(flow.updatedAt)}.` : null,
    ].filter((x): x is string => !!x);
    return details.join(' ');
  }

  private humanizeEnum(value: unknown) {
    const normalized = String(value ?? '')
      .trim()
      .replace(/_/g, ' ')
      .toLowerCase();
    if (!normalized) return 'sin dato';
    return normalized.charAt(0).toUpperCase() + normalized.slice(1);
  }

  private async buildClientKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const isAdmin = user.role === Role.ADMIN;

    const accessibleWhere: Prisma.ClientWhereInput =
      user.role === Role.TECNICO
        ? {
            isDeleted: false,
            OR: [
              { ownerId: user.id },
              { services: { some: { OR: [{ technicianId: user.id }, { createdByUserId: user.id }] } } },
            ],
          }
        : { isDeleted: false };

    const count = await this.prisma.client.count({ where: accessibleWhere });

    const base = [
      this.createAppKnowledgeRecord(
        'app-data:clients-scope',
        'clientes',
        'dato-autorizado',
        'Alcance autorizado de clientes',
        isAdmin
          ? 'Como ADMIN puedes consultar clientes del sistema según las pantallas permitidas.'
          : 'Solo puedes consultar clientes bajo tu gestión o relacionados con tu alcance autorizado dentro del sistema.',
      ),
      this.createAppKnowledgeRecord(
        'app-data:clients-count',
        'clientes',
        'dato-autorizado',
        'Resumen autorizado de clientes',
        isAdmin ? `Actualmente hay ${count} clientes activos.` : `Actualmente tienes acceso a ${count} clientes activos.`,
      ),
    ];

    const entityId = (dto.context.entityType ?? '').toLowerCase() === 'client' ? (dto.context.entityId ?? '').trim() : '';
    const searchTerms = this.extractMeaningfulQueryTerms(dto.message, {
      limit: 6,
      extraNoise: [
        'cliente',
        'clientes',
        'nombre',
        'nombres',
        'llama',
        'llamado',
        'llamada',
        'coincidencia',
        'coincidencias',
        'verifica',
        'verificar',
        'existe',
        'tiene',
        'tengan',
        'algun',
        'alguna',
        'algunas',
        'algunos',
        'telefono',
        'teléfono',
        'correo',
        'email',
        'direccion',
        'dirección',
        'contacto',
        'muestrame',
        'muéstrame',
        'busca',
        'buscame',
        'dime',
      ],
    });
    const phoneTerms = this.extractNumericQueryTerms(dto.message);

    if (!entityId && searchTerms.length === 0 && phoneTerms.length === 0) return base;

    if (!entityId) {
      const searchWhere: Prisma.ClientWhereInput = {
        ...accessibleWhere,
        OR: [
          ...searchTerms.map((term) => ({ nombre: { contains: term, mode: 'insensitive' as const } })),
          ...searchTerms.map((term) => ({ email: { contains: term, mode: 'insensitive' as const } })),
          ...searchTerms.map((term) => ({ direccion: { contains: term, mode: 'insensitive' as const } })),
          ...searchTerms.map((term) => ({ notas: { contains: term, mode: 'insensitive' as const } })),
          ...phoneTerms.map((term) => ({ telefono: { contains: term, mode: 'insensitive' as const } })),
          ...phoneTerms.map((term) => ({ phoneNormalized: { contains: term } })),
        ],
      };

      const matchingClients = await this.prisma.client.findMany({
        where: searchWhere,
        select: {
          id: true,
          nombre: true,
          telefono: true,
          email: true,
          direccion: true,
          lastActivityAt: true,
        },
        take: 12,
        orderBy: [{ lastActivityAt: 'desc' }, { nombre: 'asc' }],
      });

      if (matchingClients.length === 0) {
        base.push(
          this.createAppKnowledgeRecord(
            'app-data:clients-search-none',
            'clientes',
            'dato-autorizado',
            'Cliente no encontrado',
            `No encontré clientes autorizados que coincidan con: ${[...searchTerms, ...phoneTerms].join(', ')}.`,
          ),
        );
        return base;
      }

      const rankedClients = matchingClients
        .map((client) => {
          let score = 0;
          for (const term of searchTerms) {
            const haystack = `${client.nombre} ${client.email ?? ''} ${client.direccion ?? ''}`.toLowerCase();
            if (client.nombre.toLowerCase().includes(term)) {
              score += 3;
            } else if (haystack.includes(term)) {
              score += 1;
            }
          }
          for (const term of phoneTerms) {
            const haystack = `${client.telefono}`.replace(/\D+/g, '');
            if (haystack.includes(term)) score += 4;
          }
          return { client, score };
        })
        .sort((a, b) => b.score - a.score || a.client.nombre.localeCompare(b.client.nombre))
        .slice(0, 5)
        .map(({ client }) => client);

      const detailedMatches = await Promise.all(
        rankedClients.slice(0, 3).map(async (client) => {
          const [salesAgg, quotesAgg, latestSale, latestQuote] = await this.prisma.$transaction([
            this.prisma.sale.aggregate({
              where: { customerId: client.id, isDeleted: false },
              _count: { _all: true },
              _sum: { totalSold: true },
              _max: { saleDate: true },
            }),
            this.prisma.cotizacion.aggregate({
              where: { customerId: client.id },
              _count: { _all: true },
              _sum: { total: true },
              _max: { updatedAt: true },
            }),
            this.prisma.sale.findFirst({
              where: { customerId: client.id, isDeleted: false },
              orderBy: { saleDate: 'desc' },
              select: { saleDate: true, totalSold: true },
            }),
            this.prisma.cotizacion.findFirst({
              where: { customerId: client.id },
              orderBy: { updatedAt: 'desc' },
              select: { updatedAt: true, total: true, customerName: true },
            }),
          ]);

          return this.createAppKnowledgeRecord(
            `app-data:client-match:${client.id}`,
            'clientes',
            'dato-autorizado',
            `Cliente encontrado: ${client.nombre}`,
            [
              `Cliente: ${client.nombre}`,
              (client.telefono ?? '').trim().length > 0 ? `Telefono: ${client.telefono}` : null,
              (client.email ?? '').trim().length > 0 ? `Email: ${client.email}` : null,
              (client.direccion ?? '').trim().length > 0 ? `Direccion: ${this.buildExcerpt(client.direccion ?? '')}` : null,
              client.lastActivityAt != null ? `Ultima actividad: ${client.lastActivityAt.toISOString().slice(0, 10)}` : null,
              `Movimientos: ${salesAgg._count._all} ventas y ${quotesAgg._count._all} cotizaciones`,
              salesAgg._sum.totalSold != null ? `Total vendido: ${Number(salesAgg._sum.totalSold).toFixed(2)}` : null,
              latestSale != null ? `Ultima venta: ${latestSale.saleDate.toISOString().slice(0, 10)} por ${Number(latestSale.totalSold).toFixed(2)}` : null,
              latestQuote != null ? `Ultima cotizacion: ${Number(latestQuote.total).toFixed(2)} actualizada el ${latestQuote.updatedAt.toISOString().slice(0, 10)}` : null,
            ].filter((item): item is string => !!item).join('\n'),
          );
        }),
      );

      base.push(...detailedMatches);

      base.push(
        this.createAppKnowledgeRecord(
          'app-data:clients-search',
          'clientes',
          'dato-autorizado',
          `Clientes relacionados con "${[...searchTerms, ...phoneTerms].join(' ')}"`,
          rankedClients
            .map((client) => {
              const details: string[] = [];
              if ((client.telefono ?? '').trim().length > 0) details.push(`Tel: ${client.telefono}`);
              if ((client.email ?? '').trim().length > 0) details.push(`Email: ${client.email}`);
              if ((client.direccion ?? '').trim().length > 0) {
                details.push(`Dirección: ${this.buildExcerpt(client.direccion ?? '')}`);
              }
              if (client.lastActivityAt != null) {
                details.push(`Última actividad: ${client.lastActivityAt.toISOString().slice(0, 10)}`);
              }
              return `- ${client.nombre}${details.length === 0 ? '' : ` | ${details.join(' | ')}`}`;
            })
            .join('\n'),
        ),
      );

      return base;
    }

    const client = await this.prisma.client.findFirst({
      where: { ...accessibleWhere, id: entityId },
      select: {
        id: true,
        nombre: true,
        lastActivityAt: true,
        notas: true,
      },
    });

    if (!client) {
      base.push(
        this.createAppKnowledgeRecord(
          'app-data:client-denied',
          'clientes',
          'dato-autorizado',
          'Cliente no accesible',
          'No tengo autorización para acceder a ese cliente (o no existe).',
        ),
      );
      return base;
    }

    const saleCount = await this.prisma.sale.count({ where: { customerId: client.id, isDeleted: false } });

    base.push(
      this.createAppKnowledgeRecord(
        `app-data:client:${client.id}`,
        'clientes',
        'dato-autorizado',
        `Cliente seleccionado: ${client.nombre}`,
        `Cliente: ${client.nombre}. Ventas registradas: ${saleCount}. Última actividad: ${client.lastActivityAt ? client.lastActivityAt.toISOString() : 'N/D'}.`,
      ),
    );

    // Avoid leaking notes unless admin (notes may contain sensitive info).
    if (isAdmin && (client.notas ?? '').trim().length > 0) {
      base.push(
        this.createAppKnowledgeRecord(
          `app-data:client:${client.id}:notes`,
          'clientes',
          'dato-autorizado',
          'Notas internas del cliente (ADMIN)',
          this.buildExcerpt(client.notas ?? ''),
        ),
      );
    }

    return base;
  }

  private async buildCatalogKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const searchTokens = this.extractMeaningfulQueryTerms(dto.message, {
      limit: 6,
      extraNoise: [
        'hay',
        'tengo',
        'tienen',
        'producto',
        'productos',
        'disponible',
        'disponibles',
        'disponibilidad',
        'precio',
        'precios',
        'catalogo',
        'catalogos',
        'catálogo',
        'app',
        'quiero',
        'buscar',
        'busca',
        'buscame',
        'muestrame',
        'muéstrame',
        'necesito',
        'dime',
        'inventario',
        'stock',
      ],
    });
    const searchVariants = this.expandSearchTerms(searchTokens);

    let total = 0;
    let categoryLines = 'No hay categorías disponibles en el catálogo.';
    let catalogSource = 'LOCAL';
    let remoteProducts: Array<{
      id: string;
      nombre: string;
      descripcion: string | null;
      codigo: string | null;
      precio: number;
      stock: number | null;
      categoria: string | null;
      categoriaNombre: string | null;
    }> = [];

    try {
      const catalog = await this.catalogProducts.findAll();
      catalogSource = catalog.source;
      remoteProducts = catalog.items.map((item) => ({
        id: item.id,
        nombre: item.nombre,
        descripcion: item.descripcion,
        codigo: item.codigo,
        precio: item.precio,
        stock: item.stock,
        categoria: item.categoria,
        categoriaNombre: item.categoriaNombre,
      }));
      total = catalog.total;

      const categories = new Map<string, number>();
      for (const item of remoteProducts) {
        const category = (item.categoriaNombre ?? item.categoria ?? 'Sin categoría').trim() || 'Sin categoría';
        categories.set(category, (categories.get(category) ?? 0) + 1);
      }
      categoryLines = [...categories.entries()]
        .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
        .slice(0, 5)
        .map(([category, count]) => `- ${category}: ${count}`)
        .join('\n');
    } catch {
      total = await this.prisma.product.count();
      const topCategories = await this.prisma.product.groupBy({
        by: ['categoria'],
        _count: { categoria: true },
        orderBy: { _count: { categoria: 'desc' } },
        take: 5,
      });
      categoryLines = topCategories.length > 0
        ? topCategories
            .map((item) => `- ${item.categoria || 'Sin categoría'}: ${item._count.categoria}`)
            .join('\n')
        : categoryLines;
    }

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:catalog-count',
        'catalogo',
        'dato-autorizado',
        'Resumen autorizado de catálogo',
        `Actualmente hay ${total} productos en el catálogo. Fuente activa para el asistente: ${catalogSource}.`,
      ),
      this.createAppKnowledgeRecord(
        'app-data:catalog-categories',
        'catalogo',
        'dato-autorizado',
        'Categorías principales del catálogo',
        categoryLines,
      ),
    ];

    if (searchTokens.length === 0) return result;

    const products = remoteProducts.length > 0
      ? remoteProducts
      : await this.prisma.product.findMany({
          where: {
            OR: [
              ...searchVariants.map((token) => ({ nombre: { contains: token, mode: 'insensitive' as const } })),
              ...searchVariants.map((token) => ({ categoria: { contains: token, mode: 'insensitive' as const } })),
            ],
          },
          select: {
            id: true,
            nombre: true,
            categoria: true,
            precio: true,
            imagen: true,
          },
          take: 24,
          orderBy: { nombre: 'asc' },
        }).then((items) => items.map((item) => ({
          id: item.id,
          nombre: item.nombre,
          descripcion: null,
          codigo: null,
          precio: Number(item.precio),
          stock: null,
          categoria: item.categoria,
          categoriaNombre: item.categoria,
        })));

    const matchingProducts = products
      .map((product) => {
        const haystack = [
          product.nombre,
          product.categoria ?? '',
          product.categoriaNombre ?? '',
          product.codigo ?? '',
          product.descripcion ?? '',
        ].join(' ').toLowerCase();

        const score = searchVariants.reduce((sum, token) => {
          if (product.nombre.toLowerCase().includes(token)) return sum + 5;
          if ((product.categoriaNombre ?? product.categoria ?? '').toLowerCase().includes(token)) return sum + 3;
          if ((product.codigo ?? '').toLowerCase().includes(token)) return sum + 3;
          if (haystack.includes(token)) return sum + 1;
          return sum;
        }, 0);

        return { product, score };
      })
      .filter((item) => item.score > 0)
      .sort((a, b) => b.score - a.score || a.product.nombre.localeCompare(b.product.nombre));

    if (matchingProducts.length === 0) {
      result.push(
        this.createAppKnowledgeRecord(
          'app-data:catalog-search-none',
          'catalogo',
          'dato-autorizado',
          'Producto no encontrado en catálogo',
          `No encontré productos en el catálogo que coincidan con: ${searchTokens.join(', ')}. Si buscas disponibilidad física o inventario en tiempo real, eso debe confirmarse en el módulo correspondiente.`,
        ),
      );
      return result;
    }

    const rankedProducts = matchingProducts
      .slice(0, 8)
      .map((item) => item.product);

    const detailedProducts = rankedProducts.slice(0, 5).map((product) => {
      const category = (product.categoriaNombre ?? product.categoria ?? 'Sin categoría').trim();
      const detailLines = [
        `Producto: ${product.nombre}`,
        `Categoria: ${category}`,
        (product.codigo ?? '').trim().length > 0 ? `Codigo: ${product.codigo}` : null,
        user.role === Role.TECNICO ? null : `Precio: ${product.precio.toFixed(2)}`,
        product.stock != null ? `Stock: ${product.stock}` : null,
        (product.descripcion ?? '').trim().length > 0 ? `Descripcion: ${this.buildExcerpt(product.descripcion ?? '')}` : null,
      ].filter((item): item is string => !!item);

      return this.createAppKnowledgeRecord(
        `app-data:product-match:${product.id}`,
        'catalogo',
        'dato-autorizado',
        `Producto encontrado: ${product.nombre}`,
        detailLines.join('\n'),
      );
    });

    result.push(...detailedProducts);

    const lines = rankedProducts.map((p) => {
      const price = user.role === Role.TECNICO ? '' : ` | Precio: ${p.precio.toFixed(2)}`;
      const category = (p.categoriaNombre ?? p.categoria ?? 'Sin categoría').trim();
      const stock = p.stock == null ? '' : ` | Stock: ${p.stock}`;
      const code = (p.codigo ?? '').trim().length === 0 ? '' : ` | Código: ${p.codigo}`;
      return `- ${p.nombre} (${category})${price}${stock}${code}`;
    });

    result.push(
      this.createAppKnowledgeRecord(
        'app-data:catalog-search',
        'catalogo',
        'dato-autorizado',
        `Productos relacionados con "${searchTokens.join(' ')}"`,
        `${lines.join('\n')}\n\nNota: ${rankedProducts.some((product) => product.stock != null) ? 'el stock mostrado proviene del catálogo actual.' : 'esto confirma coincidencias en el catálogo, no inventario físico en tiempo real.'}`,
      ),
    );

    return result;
  }

  private expandSearchTerms(searchTokens: string[]) {
    const variants = new Set<string>();

    for (const token of searchTokens) {
      if (token.trim().length === 0) continue;
      variants.add(token);

      if (token.endsWith('es') && token.length > 4) {
        variants.add(token.slice(0, -2));
      }
      if (token.endsWith('s') && token.length > 3) {
        variants.add(token.slice(0, -1));
      }
      if (!token.endsWith('s')) {
        variants.add(`${token}s`);
      }
    }

    return [...variants].filter((token) => token.trim().length >= 3);
  }

  private extractMeaningfulQueryTerms(
    message: string,
    options?: { extraNoise?: string[]; limit?: number },
  ) {
    const noise = new Set([
      'que',
      'qué',
      'como',
      'cómo',
      'cual',
      'cuál',
      'cuales',
      'cuáles',
      'hay',
      'esta',
      'este',
      'estos',
      'estas',
      'para',
      'con',
      'sin',
      'del',
      'las',
      'los',
      'una',
      'uno',
      'unos',
      'unas',
      'por',
      'favor',
      'sabe',
      'puedes',
      'puede',
      'puedo',
      'necesito',
      'quiero',
      'dime',
      'mira',
      'sobre',
      ...(options?.extraNoise ?? []),
    ].flatMap((term) => this.tokenize(term)));

    const results: string[] = [];
    for (const token of this.tokenize(message)) {
      if (noise.has(token)) continue;
      if (results.includes(token)) continue;
      results.push(token);
      if (results.length >= (options?.limit ?? 6)) break;
    }
    return results;
  }

  private extractNumericQueryTerms(message: string) {
    const matches = message.match(/\d{5,}/g) ?? [];
    return [...new Set(matches.map((item) => item.trim()).filter((item) => item.length >= 5))].slice(0, 3);
  }

  private isCatalogNoiseToken(token: string) {
    return [
      'hay',
      'tengo',
      'tienen',
      'producto',
      'productos',
      'disponible',
      'disponibles',
      'precio',
      'precios',
      'catalogo',
      'catalogos',
      'catálogo',
      'app',
      'quiero',
      'buscar',
      'busca',
      'muestrame',
      'muéstrame',
      'necesito',
      'dime',
    ].includes(token);
  }

  private async buildQuoteKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const where: Prisma.CotizacionWhereInput = user.role === Role.ADMIN
      ? {}
      : { createdByUserId: user.id };

    const totalQuotes = await this.prisma.cotizacion.count({ where });
    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:quotes-scope',
        'cotizaciones',
        'dato-autorizado',
        'Alcance autorizado de cotizaciones',
        user.role === Role.ADMIN
          ? 'Puedes consultar cotizaciones del sistema según las pantallas administrativas permitidas.'
          : 'Solo puedes consultar cotizaciones creadas bajo tu usuario dentro del alcance permitido por el sistema.',
      ),
      this.createAppKnowledgeRecord(
        'app-data:quotes-count',
        'cotizaciones',
        'dato-autorizado',
        'Resumen autorizado de cotizaciones',
        user.role === Role.ADMIN
          ? `Actualmente hay ${totalQuotes} cotizaciones registradas.`
          : `Actualmente tienes acceso a ${totalQuotes} cotizaciones registradas bajo tu usuario.`,
      ),
    ];

    const entityType = (dto.context.entityType ?? '').trim().toLowerCase();
    const entityId = (dto.context.entityId ?? '').trim();

    if (entityType === 'quote' && entityId) {
      const quote = await this.prisma.cotizacion.findFirst({
        where: { ...where, id: entityId },
        select: {
          id: true,
          customerName: true,
          total: true,
          subtotal: true,
          includeItbis: true,
          note: true,
          createdAt: true,
          items: {
            select: { id: true },
          },
        },
      });

      if (!quote) {
        result.push(
          this.createAppKnowledgeRecord(
            'app-data:quote-denied',
            'cotizaciones',
            'dato-autorizado',
            'Cotización no accesible',
            'No tengo autorización para acceder a esa cotización o no existe dentro de tu alcance.',
          ),
        );
        return result;
      }

      result.push(
        this.createAppKnowledgeRecord(
          `app-data:quote:${quote.id}`,
          'cotizaciones',
          'dato-autorizado',
          `Cotización seleccionada para ${quote.customerName}`,
          `Cliente: ${quote.customerName}. Total: ${quote.total.toFixed(2)}. Subtotal: ${quote.subtotal.toFixed(2)}. ITBIS incluido: ${quote.includeItbis ? 'sí' : 'no'}. Líneas: ${quote.items.length}. Creada: ${quote.createdAt.toISOString()}. ${quote.note ? `Nota: ${this.buildExcerpt(quote.note)}.` : ''}`,
        ),
      );
    }

    return result;
  }

  private async buildSalesKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const where: Prisma.SaleWhereInput = user.role === Role.ADMIN
      ? { isDeleted: false }
      : { userId: user.id, isDeleted: false };

    const [count, latest] = await this.prisma.$transaction([
      this.prisma.sale.count({ where }),
      this.prisma.sale.findFirst({
        where,
        orderBy: { saleDate: 'desc' },
        select: {
          id: true,
          saleDate: true,
          totalSold: true,
          commissionAmount: true,
          customer: { select: { nombre: true } },
        },
      }),
    ]);

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:sales-count',
        'ventas',
        'dato-autorizado',
        'Resumen autorizado de ventas',
        user.role === Role.ADMIN
          ? `Actualmente hay ${count} ventas activas registradas en el sistema.`
          : `Actualmente tienes ${count} ventas activas registradas bajo tu usuario.`,
      ),
    ];

    if (latest) {
      result.push(
        this.createAppKnowledgeRecord(
          `app-data:sale:latest:${latest.id}`,
          'ventas',
          'dato-autorizado',
          'Última venta autorizada',
          `Última venta registrada: ${latest.saleDate.toISOString()}. Cliente: ${latest.customer?.nombre ?? 'N/D'}. Total vendido: ${latest.totalSold.toFixed(2)}. Comisión: ${latest.commissionAmount.toFixed(2)}.`,
        ),
      );
    }

    const clientEntityId = (dto.context.entityType ?? '').toLowerCase() === 'client'
      ? (dto.context.entityId ?? '').trim()
      : '';
    if (clientEntityId) {
      const clientSalesCount = await this.prisma.sale.count({
        where: { ...where, customerId: clientEntityId },
      });
      result.push(
        this.createAppKnowledgeRecord(
          `app-data:sales-client:${clientEntityId}`,
          'ventas',
          'dato-autorizado',
          'Ventas del cliente seleccionado',
          `Ventas autorizadas relacionadas con el cliente actual: ${clientSalesCount}.`,
        ),
      );
    }

    return result;
  }

  private async buildAccountingKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const todayEnd = new Date();
    todayEnd.setHours(23, 59, 59, 999);

    const [closeCount, pendingDepositOrders, latestClose] = await this.prisma.$transaction([
      this.prisma.close.count({ where: { date: { gte: todayStart, lte: todayEnd } } }),
      this.prisma.depositOrder.count({ where: { status: DepositOrderStatus.PENDING } }),
      this.prisma.close.findFirst({
        orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
        select: {
          id: true,
          type: true,
          date: true,
          cash: true,
          transfer: true,
          card: true,
        },
      }),
    ]);

    const result: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:accounting-summary',
        'contabilidad',
        'dato-autorizado',
        'Resumen autorizado de contabilidad',
        `Cierres registrados hoy: ${closeCount}. Órdenes de depósito pendientes: ${pendingDepositOrders}.`,
      ),
    ];

    if (latestClose) {
      result.push(
        this.createAppKnowledgeRecord(
          `app-data:close:latest:${latestClose.id}`,
          'contabilidad',
          'dato-autorizado',
          'Último cierre registrado',
          `Tipo: ${latestClose.type}. Fecha: ${latestClose.date.toISOString()}. Efectivo: ${latestClose.cash.toFixed(2)}. Transferencia: ${latestClose.transfer.toFixed(2)}. Tarjeta: ${latestClose.card.toFixed(2)}.`,
        ),
      );
    }

    return result;
  }

  private async buildContractKnowledge(user: { id: string; role: Role }, dto: ChatAiAssistantDto): Promise<KnowledgeRecord[]> {
    const base: KnowledgeRecord[] = [
      this.createAppKnowledgeRecord(
        'app-data:contracts-policy',
        'nomina',
        'politica-app',
        'Acceso a contratos y nómina',
        'Los contratos y la nómina contienen información sensible. Solo se permite acceso según el rol y el alcance del usuario. Por defecto, un usuario solo puede consultar su propio contrato.',
      ),
    ];

    if (!this.canAccessContractData(user.role, dto.context?.route)) {
      return base;
    }

    const contractSelect = {
      id: true,
      nombreCompleto: true,
      email: true,
      telefono: true,
      role: true,
      fechaIngreso: true,
      workContractSignatureUrl: true,
      workContractSignedAt: true,
      workContractVersion: true,
      workContractJobTitle: true,
      workContractStartDate: true,
      workContractWorkSchedule: true,
      workContractWorkLocation: true,
      workContractSalary: true,
      workContractPaymentFrequency: true,
      workContractPaymentMethod: true,
      workContractClauseOverrides: true,
      workContractCustomClauses: true,
    };

    const targetRecord = await this.prisma.user.findUnique({
      where: { id: user.id },
      select: contractSelect,
    });
    if (!targetRecord) return base;

    base.push(
      this.createAppKnowledgeRecord(
        `app-data:contract:${targetRecord.id}`,
        'nomina',
        'dato-autorizado',
        'Contrato laboral (alcance personal)',
        this.formatContractKnowledge(targetRecord),
      ),
    );

    return base;
  }

  private inferSeverity(kind: CompanyManualEntryKind, title: string, content: string): 'info' | 'warning' | 'critical' {
    const text = `${title} ${content}`.toLowerCase();
    if (text.includes('prohib') || text.includes('no permitido') || text.includes('obligatorio')) {
      return 'critical';
    }
    if (
      kind === CompanyManualEntryKind.PRICE_RULE ||
      kind === CompanyManualEntryKind.WARRANTY_POLICY ||
      text.includes('mínimo') ||
      text.includes('minimo')
    ) {
      return 'warning';
    }
    return 'info';
  }

  private createAppKnowledgeRecord(id: string, module: string, category: string, title: string, content: string): KnowledgeRecord {
    return {
      id,
      module,
      category,
      title,
      content,
      summary: null,
      keywords: this.tokenize(`${title} ${content} ${module} ${category}`).slice(0, 18),
      severity: 'info',
      active: true,
      createdAt: null,
      updatedAt: null,
    };
  }

  private buildRuleOnlyFallback(
    message: string,
    knowledge: KnowledgeRecord[],
    currentUserName?: string | null,
  ): AiAssistantChatResponse {
    const normalizedMessage = message.trim().toLowerCase();
    const hasMeaningfulQuestion = this.tokenize(normalizedMessage).length > 0;
    const matched = hasMeaningfulQuestion ? this.rankRulesForPrompt(message, knowledge).slice(0, 2) : [];
    const visibleKnowledge = knowledge.filter((item) => this.isUserVisibleKnowledge(item));
    const visibleMatched = matched.filter((item) => this.isUserVisibleKnowledge(item));
    const hasMeaningfulMatch = visibleMatched.length > 0;
    const top = visibleMatched[0] ?? visibleKnowledge[0] ?? matched[0] ?? knowledge[0];

    if (!top) {
      return {
        source: 'rules-only',
        content: this.personalizeContent(AiAssistantService.notEnoughDataMessage, currentUserName),
        citations: [],
      };
    }

    if (!hasMeaningfulMatch) {
      return {
        source: 'rules-only',
        content: this.personalizeContent(
          'No encontré una coincidencia suficientemente clara para responder esa pregunta con precisión. Intenta decirme el tema exacto, la regla, el cliente, la orden, el módulo o la pantalla que quieres revisar.',
          currentUserName,
        ),
        citations: [],
        denied: false,
      };
    }

    const selected = visibleMatched.length ? visibleMatched : [top];
    const citations = this.toUserVisibleCitations(selected);

    const clientMatches = selected.filter((k) => k.id.startsWith('app-data:client-match:'));
    if (clientMatches.length > 0) {
      const intro = clientMatches.length == 1
        ? 'Si, encontre una coincidencia con ese cliente:'
        : `Si, encontre ${clientMatches.length} coincidencias con ese nombre:`;
      const blocks = clientMatches
        .map((k) => k.content.trim())
        .filter((x) => x.length > 0)
        .join('\n\n');

      return {
        source: 'rules-only',
        content: this.personalizeContent(`${intro}\n\n${blocks}`, currentUserName),
        citations: this.toUserVisibleCitations(clientMatches),
        denied: false,
      };
    }

    const productMatches = selected.filter((k) => k.id.startsWith('app-data:product-match:'));
    if (productMatches.length > 0) {
      const intro = productMatches.length == 1
        ? 'Si, encontre este producto relacionado con tu consulta:'
        : `Si, encontre ${productMatches.length} productos relacionados con tu consulta:`;
      const blocks = productMatches
        .map((k) => k.content.trim())
        .filter((x) => x.length > 0)
        .join('\n\n');

      return {
        source: 'rules-only',
        content: this.personalizeContent(`${intro}\n\n${blocks}`, currentUserName),
        citations: this.toUserVisibleCitations(productMatches),
        denied: false,
      };
    }

    const serviceOrderMatches = selected.filter(
      (k) => k.id.startsWith('app-data:service-order:') || k.id.startsWith('app-data:service-order-match:'),
    );
    if (serviceOrderMatches.length > 0) {
      const intro = serviceOrderMatches.length === 1
        ? 'Sí, encontré esta orden de servicio relacionada con tu consulta:'
        : `Sí, encontré ${serviceOrderMatches.length} órdenes de servicio relacionadas con tu consulta:`;
      const blocks = serviceOrderMatches
        .map((k) => k.content.trim())
        .filter((x) => x.length > 0)
        .join('\n\n');

      return {
        source: 'rules-only',
        content: this.personalizeContent(`${intro}\n\n${blocks}`, currentUserName),
        citations: this.toUserVisibleCitations(serviceOrderMatches),
        denied: false,
      };
    }

    const documentFlowMatches = selected.filter(
      (k) => k.id.startsWith('app-data:document-flow:') || k.id.startsWith('app-data:document-flow-match:'),
    );
    if (documentFlowMatches.length > 0) {
      const intro = documentFlowMatches.length === 1
        ? 'Sí, encontré este flujo documental relacionado con tu consulta:'
        : `Sí, encontré ${documentFlowMatches.length} flujos documentales relacionados con tu consulta:`;
      const blocks = documentFlowMatches
        .map((k) => k.content.trim())
        .filter((x) => x.length > 0)
        .join('\n\n');

      return {
        source: 'rules-only',
        content: this.personalizeContent(`${intro}\n\n${blocks}`, currentUserName),
        citations: this.toUserVisibleCitations(documentFlowMatches),
        denied: false,
      };
    }

    const contractMatches = selected.filter(
      (k) => k.id.startsWith('app-data:contract:') || k.id.startsWith('app-data:contract-match:'),
    );
    if (contractMatches.length > 0) {
      const intro = contractMatches.length === 1
        ? 'Si, encontre la informacion del contrato laboral relacionada con tu consulta:'
        : `Si, encontre ${contractMatches.length} contratos laborales relacionados con tu consulta:`;
      const blocks = contractMatches
        .map((k) => k.content.trim())
        .filter((x) => x.length > 0)
        .join('\n\n');

      return {
        source: 'rules-only',
        content: this.personalizeContent(
          `${intro}\n\nResumen del contrato:\n${blocks}\n\nSi necesitas que te explique una clausula, forma de pago, fecha de inicio, puesto o cualquier detalle del contrato, dime exactamente cual parte quieres revisar.`,
          currentUserName,
        ),
        citations: this.toUserVisibleCitations(contractMatches),
        denied: false,
      };
    }

    const isGrowthQuestion = this.hasAnyToken(new Set(this.tokenize(message)), [
      'aprender',
      'aprende',
      'aprendiendo',
      'aprendizaje',
      'crecer',
      'creciendo',
      'actualizar',
      'actualizando',
      'datos',
      'tablas',
      'conocimiento',
      'memoria',
      'sistema',
    ]);
    const growthMatches = selected.filter((k) => k.id.startsWith('app-data:growth-'));
    if (isGrowthQuestion && growthMatches.length > 0) {
      const blocks = growthMatches
        .map((k) => k.content.trim())
        .filter((x) => x.length > 0)
        .join('\n\n');

      return {
        source: 'rules-only',
        content: this.personalizeContent(
          `${blocks}\n\nSi quieres, tambien puedo explicarte por modulo como va creciendo el conocimiento en clientes, productos, contratos, ventas, servicios o normas.`,
          currentUserName,
        ),
        citations: [],
        denied: false,
      };
    }

    const isManualQuestion = this.hasAnyToken(new Set(this.tokenize(message)), [
      'manual',
      'norma',
      'normas',
      'regla',
      'reglas',
      'politica',
      'política',
      'politicas',
      'políticas',
      'protocolo',
      'protocolos',
    ]);
    const manualEntries = knowledge.filter(
      (k) => k.module === 'manual-interno' || k.category === 'politicas',
    );
    const concreteManualEntries = manualEntries.filter((k) => !k.id.startsWith('app-help:'));

    if (isManualQuestion && manualEntries.length > 0) {
      const categoryLabels = Array.from(
        new Set(
          concreteManualEntries
            .map((k) => this.describeManualCategory(k.category))
            .filter((value) => value.length > 0),
        ),
      ).slice(0, 5);
      const generalLines = [
        'Si, tengo conocimiento de las normas y del Manual Interno disponible para tu rol.',
        'En general puedo orientarte sobre politicas, reglas operativas, protocolos, responsabilidades y guias de trabajo por modulo o proceso.',
      ];

      if (concreteManualEntries.length > 0) {
        generalLines.push(`Actualmente tengo acceso a ${concreteManualEntries.length} normas o entradas publicadas relacionadas con el Manual Interno.`);
      }

      if (categoryLabels.length > 0) {
        generalLines.push(`Los temas que cubre con mas frecuencia son: ${categoryLabels.join(', ')}.`);
      }

      const highlightedRules = (matched.length ? matched : concreteManualEntries)
        .filter((k) => !k.id.startsWith('app-help:'))
        .slice(0, 3)
        .map((k) => `- ${k.title}: ${this.buildExcerpt((k.summary ?? '').trim().length ? (k.summary as string) : k.content)}`)
        .join('\n');

      const contentParts = [generalLines.join(' ')];
      if (highlightedRules.length > 0) {
        contentParts.push(`Detalle general relacionado con tu consulta:\n${highlightedRules}`);
      }
      contentParts.push('Si tienes una pregunta mas especifica, dime la norma, politica, regla o area que quieres revisar y te la explico con mas detalle.');

      return {
        source: 'rules-only',
        content: this.personalizeContent(contentParts.join('\n\n'), currentUserName),
        citations: this.toUserVisibleCitations((visibleMatched.length ? visibleMatched : manualEntries).slice(0, 3)),
        denied: false,
      };
    }

    const parts = selected
      .map((k, index) => {
        const excerpt = this.buildExcerpt((k.summary ?? '').trim().length ? (k.summary as string) : k.content);
        const prefix = index === 0 ? `Según "${k.title}"` : `También aplica "${k.title}"`;
        return excerpt.length ? `${prefix}: ${excerpt}` : prefix;
      })
      .filter((x) => x.trim().length > 0);

    return {
      source: 'rules-only',
      content: this.personalizeContent(
        parts.length ? parts.join(' ') : AiAssistantService.notEnoughDataMessage,
        currentUserName,
      ),
      citations: this.toUserVisibleCitations(selected),
      denied: false,
    };
  }

  private personalizeContent(content: string, currentUserName?: string | null) {
    const trimmed = content.trim();
    if (!trimmed || !currentUserName || currentUserName.trim().length === 0) {
      return trimmed;
    }

    const safeName = currentUserName.trim();
    const lower = trimmed.toLowerCase();
    if (lower.startsWith(`${safeName.toLowerCase()},`) || lower.startsWith(`hola ${safeName.toLowerCase()}`)) {
      return trimmed;
    }

    if (trimmed === AiAssistantService.notEnoughDataMessage) {
      return `${safeName}, ${trimmed.charAt(0).toLowerCase()}${trimmed.slice(1)}`;
    }

    const intro = this.buildPersonalizedIntro(safeName, lower);
    return `${intro}\n\n${trimmed}`;
  }

  private buildPersonalizedIntro(currentUserName: string, normalizedContent: string) {
    if (
      normalizedContent.includes('contrato laboral') ||
      normalizedContent.includes('resumen del contrato') ||
      normalizedContent.includes('salario:') ||
      normalizedContent.includes('frecuencia de pago')
    ) {
      return `${currentUserName}, aqui tienes el resumen de contrato que encontre para ti.`;
    }

    if (
      normalizedContent.includes('manual interno') ||
      normalizedContent.includes('norma') ||
      normalizedContent.includes('politica') ||
      normalizedContent.includes('regla') ||
      normalizedContent.includes('protocolo')
    ) {
      return `${currentUserName}, te comparto un resumen claro de las normas y lineamientos disponibles.`;
    }

    if (
      normalizedContent.includes('coincidencia con ese cliente') ||
      normalizedContent.includes('cliente:') ||
      normalizedContent.includes('movimientos del cliente')
    ) {
      return `${currentUserName}, esto es lo que encontre sobre el cliente consultado.`;
    }

    if (
      normalizedContent.includes('producto:') ||
      normalizedContent.includes('precio:') ||
      normalizedContent.includes('stock:') ||
      normalizedContent.includes('productos relacionados con tu consulta')
    ) {
      return `${currentUserName}, esto es lo que encontre del producto que consultaste.`;
    }

    return `${currentUserName}, aqui tienes la informacion que encontre.`;
  }

  private async getCurrentUserPreferredName(userId: string) {
    const record = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { nombreCompleto: true },
    });

    const raw = (record?.nombreCompleto ?? '').trim();
    if (!raw) return null;

    const [firstName] = raw.split(/\s+/).filter((part) => part.trim().length > 0);
    return firstName?.trim() || raw;
  }

  private rankRulesForPrompt(message: string, knowledge: KnowledgeRecord[]) {
    const tokens = new Set(this.tokenize(message));

    return knowledge
      .map((k) => {
        const kTokens = new Set(this.tokenize(`${k.title} ${k.summary ?? ''} ${k.content} ${k.module} ${k.category}`));
        let score = 0;
        for (const token of tokens) {
          if (kTokens.has(token)) score += token.length >= 5 ? 2 : 1;
        }
        if (k.severity === 'critical') score += 2;
        if (k.severity === 'warning') score += 1;
        return { k, score };
      })
      .filter((x) => x.score > 0)
      .sort((a, b) => b.score - a.score)
      .map((x) => x.k);
  }

  private toCitation(k: KnowledgeRecord) {
    return { id: k.id, module: k.module, category: k.category, title: k.title };
  }

  private tokenize(value: string) {
    return value
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .split(/[^a-z0-9]+/)
      .map((item) => item.trim())
      .filter((item) => item.length >= 3);
  }

  private hasAnyToken(tokens: Set<string>, candidates: string[]) {
    for (const c of candidates) {
      const normalized = this.tokenize(c).join(' ');
      for (const token of this.tokenize(normalized)) {
        if (tokens.has(token)) return true;
      }
      if (tokens.has(this.tokenize(c).join(''))) return true;
    }
    return false;
  }

  private buildExcerpt(content: string) {
    const normalized = content.replace(/\s+/g, ' ').trim();
    if (normalized.length <= 240) return normalized;
    return `${normalized.slice(0, 237).trim()}...`;
  }

  private formatContractKnowledge(record: {
    id: string;
    nombreCompleto: string;
    email: string;
    telefono: string;
    role: Role;
    fechaIngreso: Date | null;
    workContractSignatureUrl: string | null;
    workContractSignedAt: Date | null;
    workContractVersion: string | null;
    workContractJobTitle: string | null;
    workContractStartDate: Date | null;
    workContractWorkSchedule: string | null;
    workContractWorkLocation: string | null;
    workContractSalary: string | null;
    workContractPaymentFrequency: string | null;
    workContractPaymentMethod: string | null;
    workContractClauseOverrides: Prisma.JsonValue | null;
    workContractCustomClauses: string | null;
  }) {
    const clauseSummary = this.summarizeContractClauses(record.workContractClauseOverrides, record.workContractCustomClauses);
    const lines = [
      `Empleado: ${record.nombreCompleto}`,
      `Rol: ${record.role}`,
      `Correo: ${record.email}`,
      `Telefono: ${record.telefono}`,
      `Puesto: ${record.workContractJobTitle ?? 'N/D'}`,
      `Inicio de contrato: ${record.workContractStartDate ? record.workContractStartDate.toISOString().slice(0, 10) : 'N/D'}`,
      `Fecha de ingreso: ${record.fechaIngreso ? record.fechaIngreso.toISOString().slice(0, 10) : 'N/D'}`,
      `Horario laboral: ${record.workContractWorkSchedule ?? 'N/D'}`,
      `Lugar de trabajo: ${record.workContractWorkLocation ?? 'N/D'}`,
      `Salario: ${record.workContractSalary ?? 'N/D'}`,
      `Frecuencia de pago: ${record.workContractPaymentFrequency ?? 'N/D'}`,
      `Metodo de pago: ${record.workContractPaymentMethod ?? 'N/D'}`,
      `Version del contrato: ${record.workContractVersion ?? 'N/D'}`,
      `Estado de firma: ${record.workContractSignedAt ? `Firmado el ${record.workContractSignedAt.toISOString()}` : 'Pendiente o no registrado'}`,
      record.workContractSignatureUrl ? 'Firma digital o archivo del contrato: disponible' : 'Firma digital o archivo del contrato: no registrado',
      clauseSummary,
    ].filter((item) => item.trim().length > 0);

    return lines.join('\n');
  }

  private summarizeContractClauses(
    overrides: Prisma.JsonValue | null,
    customClauses: string | null,
  ) {
    const parts: string[] = [];

    if (customClauses && customClauses.trim().length > 0) {
      parts.push(`Clausulas personalizadas: ${this.buildExcerpt(customClauses)}`);
    }

    if (overrides && typeof overrides === 'object') {
      const overrideCount = Array.isArray(overrides) ? overrides.length : Object.keys(overrides as Record<string, unknown>).length;
      if (overrideCount > 0) {
        parts.push(`Ajustes o clausulas sobrescritas: ${overrideCount} registradas.`);
      }
    }

    if (parts.length === 0) {
      return 'Clausulas adicionales: no registradas.';
    }

    return parts.join(' ');
  }

  private describeManualCategory(category: string) {
    switch ((category ?? '').trim().toLowerCase()) {
      case 'politicas':
        return 'politicas internas';
      case 'precios':
        return 'reglas de precios';
      case 'garantias':
        return 'politicas de garantia';
      case 'servicios':
        return 'protocolos de servicio';
      case 'productos':
        return 'lineamientos de productos y servicios';
      case 'modulo':
        return 'guias por modulo';
      case 'general':
        return 'reglas generales y responsabilidades';
      default:
        return category.trim();
    }
  }

  private isUserVisibleKnowledge(record: KnowledgeRecord) {
    if (record.category === 'memoria') return false;
    if (record.id === 'app-data:conversation-context') return false;
    if (record.id.startsWith('app-memory:')) return false;
    return true;
  }

  private toUserVisibleCitations(records: KnowledgeRecord[]) {
    return records
      .filter((record) => this.isUserVisibleKnowledge(record))
      .map((record) => this.toCitation(record));
  }

  private formatKnowledgeDate(value: Date | string | null) {
    if (!value) return 'sin fecha';
    const parsed = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(parsed.getTime())) return 'sin fecha';
    return parsed.toISOString().slice(0, 19).replace('T', ' ');
  }

  private normalizeOptionalString(value: unknown) {
    if (typeof value !== 'string') return null;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  private normalizeCitations(raw: unknown, knowledge: KnowledgeRecord[]) {
    if (!Array.isArray(raw)) return [];
    return raw
      .map((item) => {
        if (typeof item !== 'object' || item === null || Array.isArray(item)) return null;
        const row = item as Record<string, unknown>;
        const id = this.normalizeOptionalString(row.id);
        const entry = knowledge.find((k) => k.id === id);
        if (!entry) return null;
        return this.toCitation(entry);
      })
      .filter((x): x is NonNullable<typeof x> => !!x);
  }

  private async resolveCompanyOwnerId(fallbackUserId: string) {
    const admin = await this.prisma.user.findFirst({
      where: { role: Role.ADMIN },
      orderBy: { createdAt: 'asc' },
      select: { id: true },
    });
    return admin?.id ?? fallbackUserId;
  }

  /**
   * Genera texto libre usando OpenAI (sin estructura JSON).
   * Usado por CrmBotService.evaluateAndRespond() para respuestas automáticas del bot.
   */
  async generateText(systemPrompt: string): Promise<string> {
    const runtime = await this.getOpenAiRuntimeConfig();
    if (!runtime.apiKey) {
      throw new BadRequestException('OpenAI API key no configurada');
    }

    const candidates = this.getOpenAiModelCandidates(runtime.model);

    for (const candidate of candidates) {
      try {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${runtime.apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model: candidate,
            temperature: 0.3,
            messages: [
              { role: 'system', content: systemPrompt },
            ],
          }),
        });

        if (!response.ok) {
          this.logDebug('openai.generateText.http_error', { candidate, status: response.status });
          continue;
        }

        const payload = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> };
        const content = payload.choices?.[0]?.message?.content?.trim();
        if (content) {
          return content;
        }
      } catch (error) {
        this.logDebug('openai.generateText.error', {
          candidate,
          message: error instanceof Error ? error.message : `${error}`,
        });
      }
    }

    throw new BadRequestException('No se pudo generar texto desde OpenAI.');
  }

  private async getOpenAiRuntimeConfig(): Promise<AiRuntimeConfig> {
    const envKey = (this.config.get<string>('OPENAI_API_KEY') ?? process.env.OPENAI_API_KEY ?? '').trim();
    const envModel = (this.config.get<string>('OPENAI_MODEL') ?? process.env.OPENAI_MODEL ?? '').trim();

    let appConfig: { openAiApiKey: string | null; openAiModel: string | null; companyName: string | null } | null = null;

    try {
      appConfig = await this.prisma.appConfig.findUnique({
        where: { id: 'global' },
        select: { openAiApiKey: true, openAiModel: true, companyName: true },
      });
    } catch {
      appConfig = null;
    }

    return {
      apiKey: envKey.length > 0 ? envKey : (appConfig?.openAiApiKey ?? '').trim(),
      model: envModel.length > 0 ? envModel : ((appConfig?.openAiModel ?? '').trim() || 'gpt-4o-mini'),
      companyName: (appConfig?.companyName ?? 'FULLTECH').trim() || 'FULLTECH',
    };
  }

  private getOpenAiModelCandidates(preferredModel: string) {
    const autoCandidatesEnv = (process.env.OPENAI_MODEL_CANDIDATES ?? '').trim();
    const autoCandidates = autoCandidatesEnv.length > 0
      ? autoCandidatesEnv.split(',').map((x) => x.trim()).filter((x) => x.length > 0)
      : ['gpt-5', 'gpt-4.1', 'gpt-4o', 'gpt-4o-mini'];

    return [preferredModel, ...autoCandidates].filter((value, index, list) => value.length > 0 && list.indexOf(value) === index);
  }

  private extractJsonObject(raw: string) {
    const trimmed = raw.trim();
    const fenced = trimmed.startsWith('```')
      ? trimmed.replace(/^```(?:json)?\s*/i, '').replace(/```$/i, '').trim()
      : trimmed;
    const firstBrace = fenced.indexOf('{');
    const lastBrace = fenced.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return fenced.slice(firstBrace, lastBrace + 1);
    }
    return fenced;
  }

  private async requestStrictJsonFromOpenAi<T>({
    runtime,
    systemPrompt,
    userPrompt,
    temperature,
  }: {
    runtime: AiRuntimeConfig;
    systemPrompt: string;
    userPrompt: string;
    temperature: number;
  }): Promise<T> {
    const candidates = this.getOpenAiModelCandidates(runtime.model);

    for (const candidate of candidates) {
      try {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${runtime.apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model: candidate,
            temperature,
            messages: [
              { role: 'system', content: systemPrompt },
              { role: 'user', content: userPrompt },
            ],
          }),
        });

        if (!response.ok) {
          this.logDebug('openai.http_error', { candidate, status: response.status });
          continue;
        }

        const payload = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> };
        const content = payload.choices?.[0]?.message?.content?.trim();
        if (!content) continue;

        return JSON.parse(this.extractJsonObject(content)) as T;
      } catch (error) {
        this.logDebug('openai.parse_error', {
          candidate,
          message: error instanceof Error ? error.message : `${error}`,
        });
      }
    }

    throw new BadRequestException('No se pudo generar una respuesta válida desde OpenAI para el asistente.');
  }

  private logDebug(label: string, payload: unknown) {
    if (process.env.NODE_ENV === 'production' && process.env.AI_DEBUG !== '1') {
      return;
    }
    this.logger.debug(`${label}: ${JSON.stringify(payload)}`);
  }
}
