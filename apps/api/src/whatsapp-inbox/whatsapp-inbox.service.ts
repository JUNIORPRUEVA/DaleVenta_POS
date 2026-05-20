import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
  forwardRef,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import {
  Prisma,
  WhatsappMessageDirection,
  WhatsappMessageType,
} from '@prisma/client';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';
import { WhatsappService } from '../whatsapp/whatsapp.service';
import { R2Service } from '../storage/r2.service';
import { RedisService } from '../common/redis/redis.service';
import * as bcrypt from 'bcryptjs';
import { createHash, randomUUID } from 'node:crypto';
import {
  normalizeInstanceName,
  normalizeWhatsappIdentity,
  normalizeWhatsappPhone,
} from './whatsapp-identity.util';
import { CrmBotService } from '../crm-commercial/crm-bot.service';

export interface ParsedWhatsappMessage {
  evolutionId: string;
  externalMessageId: string;
  instanceName: string | null;
  eventName: string | null;
  remoteJid: string;
  remotePhone: string | null;
  fromMe: boolean;
  messageType: WhatsappMessageType;
  body: string | null;
  mediaUrl: string | null;
  mediaMimeType: string | null;
  caption: string | null;
  senderName: string | null;
  sentAt: Date;
  rawPayload: unknown;
}

type JsonRecord = Record<string, unknown>;

type DetectedMediaType = { ext: string; mime: string };
type PreparedWhatsappMedia = {
  mediaUrl: string;
  mediaMimeType: string;
  mediaStorageKey: string;
  mediaFileSize: number;
  originalFileName: string | null;
  playableStorageKey: string | null;
  playableMimeType: string | null;
  mediaStatus: 'ready' | 'failed';
  mediaError: string | null;
};

type OutgoingWhatsappMediaType = 'image' | 'video' | 'audio' | 'document';

type WhatsappAiFilter =
  | 'today'
  | 'yesterday'
  | 'last7Days'
  | 'thisMonth'
  | 'custom';

type WhatsappAiScope = 'conversation' | 'filter';

type WhatsappResponsibilityOption =
  | 'Cliente no respondio'
  | 'Vendedor no respondio'
  | 'Conversacion normal'
  | 'Requiere seguimiento del vendedor'
  | 'No hay evidencia suficiente';

type WhatsappAiAnalysisInput = {
  userId?: string;
  conversationId?: string;
  scope: WhatsappAiScope;
  filter: WhatsappAiFilter;
  customDate?: string;
  forceRefresh?: boolean;
  generatedBy?: string | null;
};

type WhatsappAiMediaContext = {
  messageId: string;
  type: string;
  mimeType: string | null;
  status: string;
  summary: string | null;
  transcriptionStatus: string;
  transcriptionText: string | null;
};

type WhatsappAiMessageContext = {
  id: string;
  timestamp: string;
  time: string;
  direction: 'inbound' | 'outbound';
  senderRole: 'cliente' | 'vendedor';
  senderName: string | null;
  senderPhone: string | null;
  instanceName: string;
  fromMe: boolean;
  body: string;
  type: string;
  messageType: string;
  text: string;
  media: WhatsappAiMediaContext | null;
};

type WhatsappAiConversationContext = {
  conversationId: string;
  contact: string;
  phone: string | null;
  instanceName: string;
  userName: string;
  firstMessageAt: string | null;
  lastMessageAt: string | null;
  totalMessages: number;
  incomingMessages: number;
  outgoingMessages: number;
  averageResponseMinutes: number | null;
  maxResponseMinutes: number | null;
  unansweredIncomingMessages: number;
  lastMessageBy: 'cliente' | 'vendedor' | 'desconocido';
  responsibilityDetected: WhatsappResponsibilityOption;
  messages: WhatsappAiMessageContext[];
};

type WhatsappAiAskInput = {
  analysisReportId: string;
  question: string;
  conversationId?: string;
  dateRange?: unknown;
  generatedBy?: string | null;
};

type WhatsappAiReport = {
  estadoGeneral: string;
  resumenEjecutivo: string;
  totalConversacionesAnalizadas: number;
  totalMensajesAnalizados: number;
  casosNormales: number;
  casosConAlerta: number;
  casosCriticos: number;
  posiblesFraudesDetectados: number;
  clientesSinRespuesta: number;
  recomendacionesConcretas: string[];
  conversacionesProblematicas: Array<{
    conversationId?: string;
    contacto: string;
    telefono?: string | null;
    motivo: string;
    evidencia: string;
    prioridad: string;
    accionRecomendada: string;
    clasificacion: string;
  }>;
  responsabilidadDetectada?: Array<{
    conversationId?: string;
    cliente: string;
    atendidoPor: string;
    estado: WhatsappResponsibilityOption | string;
    evidencia: string;
    ultimoMensajeDe: string;
    accion: string;
  }>;
};

function asRecord(value: unknown): JsonRecord | undefined {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as JsonRecord)
    : undefined;
}

function asString(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : undefined;
}

function asBoolean(value: unknown): boolean | undefined {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const v = value.trim().toLowerCase();
    if (v === 'true' || v === '1' || v === 'yes') return true;
    if (v === 'false' || v === '0' || v === 'no') return false;
  }
  if (typeof value === 'number') {
    if (value === 1) return true;
    if (value === 0) return false;
  }
  return undefined;
}

function whatsappMessageTypeFromMediaType(
  value: OutgoingWhatsappMediaType,
): WhatsappMessageType {
  switch (value) {
    case 'image':
      return WhatsappMessageType.IMAGE;
    case 'video':
      return WhatsappMessageType.VIDEO;
    case 'audio':
      return WhatsappMessageType.AUDIO;
    case 'document':
      return WhatsappMessageType.DOCUMENT;
  }
}

function normalizeEventName(value: unknown): string | null {
  const raw = asString(value);
  if (!raw) return null;
  return raw.toUpperCase().replace(/\./g, '_').replace(/\s+/g, '_');
}

function isOutgoingEventName(value: string | null): boolean {
  if (!value) return false;
  return value.includes('SEND_MESSAGE') || value.includes('MESSAGES_UPDATE');
}

const configuredDailySummaryAiTimeoutMs = Number(
  process.env.WHATSAPP_DAILY_SUMMARY_AI_TIMEOUT_MS ?? 10000,
);
const DAILY_SUMMARY_AI_TIMEOUT_MS = Number.isFinite(
  configuredDailySummaryAiTimeoutMs,
)
  ? Math.max(3000, Math.min(configuredDailySummaryAiTimeoutMs, 14000))
  : 10000;

function parseTimestamp(value: unknown): Date | null {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return value;

  if (typeof value === 'number' && Number.isFinite(value)) {
    const ms = value > 1e12 ? value : value * 1000;
    const date = new Date(ms);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return null;
    if (/^\d+$/.test(trimmed)) {
      return parseTimestamp(Number(trimmed));
    }
    const parsed = new Date(trimmed);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  return null;
}

function phoneFromIdentifier(value: unknown): string | null {
  return normalizeWhatsappPhone(value);
}

function firstPhone(...values: unknown[]): string | null {
  for (const value of values) {
    const phone = phoneFromIdentifier(value);
    if (phone) return phone;
  }
  return null;
}

async function findExistingWhatsappConversation(
  prisma: PrismaService,
  instanceId: string,
  normalizedJid: string,
  remotePhone: string | null,
) {
  if (remotePhone) {
    const byPhone = await prisma.whatsappConversation.findFirst({
      where: {
        instanceId,
        remotePhone,
      },
      orderBy: [{ lastMessageAt: 'desc' }, { updatedAt: 'desc' }],
    });
    if (byPhone) {
      if (
        byPhone.remoteJid !== normalizedJid &&
        !normalizedJid.startsWith('me@')
      ) {
        const updated = await prisma.whatsappConversation.update({
          where: { id: byPhone.id },
          data: {
            remoteJid: normalizedJid,
            remotePhone,
          },
        });
        return { conversation: updated, merged: true };
      }
      return { conversation: byPhone, merged: false };
    }
  }

  const byJid = await prisma.whatsappConversation.findUnique({
    where: {
      instanceId_remoteJid: { instanceId, remoteJid: normalizedJid },
    },
  });
  if (byJid) return { conversation: byJid, merged: false };

  return null;
}

function readableSenderName(
  name: unknown,
  fallbackPhone: string | null,
): string | null {
  const raw = asString(name);
  if (!raw) return fallbackPhone;
  if (raw.includes('@')) return fallbackPhone;
  const digits = raw.replace(/\D/g, '');
  if (digits.length > 15) return fallbackPhone;
  return raw;
}

function mediaMime(
  media: JsonRecord | undefined,
  data: JsonRecord,
  fallback: string | null,
) {
  return (
    asString(media?.mimetype) ??
    asString(media?.mimeType) ??
    asString(data.mimetype) ??
    asString(data.mimeType) ??
    fallback
  );
}

function mediaUrlFromPayload(
  media: JsonRecord | undefined,
  messageObj: JsonRecord,
  data: JsonRecord,
  mimeType: string | null,
) {
  const base64 =
    asString(media?.base64) ??
    asString(messageObj.base64) ??
    asString(data.base64) ??
    null;
  if (base64) {
    if (base64.startsWith('data:')) return base64;
    return `data:${mimeType ?? 'application/octet-stream'};base64,${base64}`;
  }

  return (
    asString(media?.mediaUrl) ??
    asString(media?.url) ??
    asString(messageObj.mediaUrl) ??
    asString(messageObj.url) ??
    asString(data.mediaUrl) ??
    asString(data.url) ??
    null
  );
}

function evolutionMediaMessageFromPayload(payload: unknown): unknown {
  const root = asRecord(payload);
  const data = asRecord(root?.data) ?? asRecord(root?.message) ?? root;
  if (data && (asRecord(data.key) || asRecord(data.message))) return data;
  return payload;
}

function mediaRecordFromPayload(payload: unknown): JsonRecord | undefined {
  const root = asRecord(payload);
  const data = asRecord(root?.data) ?? asRecord(root?.message) ?? root;
  const messageObj =
    asRecord(data?.message) ??
    asRecord(data?.messageData) ??
    asRecord(data?.messageContent) ??
    {};
  return (
    asRecord(messageObj.imageMessage) ??
    asRecord(messageObj.audioMessage) ??
    asRecord(messageObj.pttMessage) ??
    asRecord(messageObj.videoMessage) ??
    asRecord(messageObj.documentMessage) ??
    asRecord(messageObj.stickerMessage) ??
    messageObj
  );
}

function mediaPayloadDiagnostic(payload: unknown, parsed: ParsedWhatsappMessage) {
  const root = asRecord(payload);
  const data = asRecord(root?.data) ?? asRecord(root?.message) ?? root;
  const messageObj =
    asRecord(data?.message) ??
    asRecord(data?.messageData) ??
    asRecord(data?.messageContent) ??
    {};
  const media = mediaRecordFromPayload(payload);
  const base64 =
    asString(media?.base64) ??
    asString(messageObj.base64) ??
    asString(data?.base64) ??
    null;
  const mediaUrl =
    asString(media?.mediaUrl) ??
    asString(messageObj.mediaUrl) ??
    asString(data?.mediaUrl) ??
    null;
  const url =
    asString(media?.url) ?? asString(messageObj.url) ?? asString(data?.url) ?? null;
  return {
    event: parsed.eventName,
    messageType: parsed.messageType,
    mimetype: mediaMime(media, data ?? {}, parsed.mediaMimeType),
    hasBase64: !!base64,
    base64Size: base64?.length ?? 0,
    hasMediaUrl: !!mediaUrl,
    hasDirectPath: !!asString(media?.directPath),
    hasMediaKey: !!asString(media?.mediaKey),
    hasUrl: !!url,
    remoteJid: parsed.remoteJid,
    messageId: parsed.externalMessageId,
  };
}

function mediaNeedsEvolutionBase64(mediaUrl: string | null): boolean {
  if (!mediaUrl) return true;
  const lower = mediaUrl.toLowerCase();
  return lower.includes('mmg.whatsapp.net') || lower.includes('.enc?');
}

function findBase64InResponse(value: unknown): string | null {
  if (!value) return null;
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return null;
    if (trimmed.startsWith('data:') || trimmed.length > 100) return trimmed;
    return null;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findBase64InResponse(item);
      if (found) return found;
    }
    return null;
  }
  const record = asRecord(value);
  if (!record) return null;
  for (const key of [
    'base64',
    'media',
    'data',
    'file',
    'buffer',
    'mediaBase64',
    'base64Data',
  ]) {
    const found = findBase64InResponse(record[key]);
    if (found) return found;
  }
  return null;
}

function normalizeMimeType(value: unknown): string | null {
  const raw = asString(value)?.toLowerCase();
  if (!raw) return null;
  const [mime] = raw.split(';').map((part) => part.trim());
  if (!mime || !mime.includes('/')) return null;
  if (mime === 'audio/opus') return 'audio/ogg';
  if (mime === 'image/jpg') return 'image/jpeg';
  return mime;
}

function extensionForMime(mime: string | null): string | null {
  switch (normalizeMimeType(mime)) {
    case 'audio/ogg':
      return 'ogg';
    case 'audio/mpeg':
      return 'mp3';
    case 'audio/mp4':
    case 'audio/aac':
      return 'm4a';
    case 'audio/wav':
    case 'audio/x-wav':
      return 'wav';
    case 'image/jpeg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'video/mp4':
      return 'mp4';
    case 'video/webm':
      return 'webm';
    case 'video/3gpp':
      return '3gp';
    case 'application/pdf':
      return 'pdf';
    default:
      return null;
  }
}

function outgoingMediaTypeFromMime(
  mime: string | null,
): OutgoingWhatsappMediaType {
  const normalized = normalizeMimeType(mime) ?? 'application/octet-stream';
  if (normalized.startsWith('image/')) return 'image';
  if (normalized.startsWith('video/')) return 'video';
  if (normalized.startsWith('audio/')) return 'audio';
  return 'document';
}

function ensureFilenameExtension(fileName: string, ext: string): string {
  const trimmed = fileName.trim();
  const safeBase =
    trimmed.replace(/[\\/:*?"<>|]+/g, '-').replace(/\s+/g, ' ').trim() ||
    `media-${Date.now()}`;
  const dotExt = `.${ext}`;
  if (safeBase.toLowerCase().endsWith(dotExt.toLowerCase())) {
    return safeBase;
  }
  const withoutExt = safeBase.replace(/\.[a-z0-9]{1,8}$/i, '');
  return `${withoutExt}${dotExt}`;
}

function replaceObjectKeyExtension(objectKey: string, ext: string): string {
  const cleanKey = objectKey.trim().replace(/\/+$/, '');
  const dotExt = `.${ext}`;
  if (!cleanKey) return cleanKey;
  if (cleanKey.toLowerCase().endsWith(dotExt.toLowerCase())) {
    return cleanKey;
  }
  return cleanKey.replace(/\.[a-z0-9]{1,8}$/i, '') + dotExt;
}

function fallbackDetectMediaType(buffer: Buffer): DetectedMediaType | null {
  if (buffer.length < 4) return null;
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return { ext: 'jpg', mime: 'image/jpeg' };
  }
  if (
    buffer.length >= 8 &&
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47 &&
    buffer[4] === 0x0d &&
    buffer[5] === 0x0a &&
    buffer[6] === 0x1a &&
    buffer[7] === 0x0a
  ) {
    return { ext: 'png', mime: 'image/png' };
  }
  if (
    buffer.length >= 12 &&
    buffer.toString('ascii', 0, 4) === 'RIFF' &&
    buffer.toString('ascii', 8, 12) === 'WEBP'
  ) {
    return { ext: 'webp', mime: 'image/webp' };
  }
  if (buffer.toString('ascii', 0, 4) === '%PDF') {
    return { ext: 'pdf', mime: 'application/pdf' };
  }
  if (buffer.toString('ascii', 0, 4) === 'OggS') {
    return { ext: 'ogg', mime: 'audio/ogg' };
  }
  if (buffer.toString('ascii', 0, 3) === 'ID3') {
    return { ext: 'mp3', mime: 'audio/mpeg' };
  }
  if (buffer[0] === 0xff && (buffer[1] & 0xe0) === 0xe0) {
    return { ext: 'mp3', mime: 'audio/mpeg' };
  }
  if (
    buffer.length >= 12 &&
    buffer.toString('ascii', 0, 4) === 'RIFF' &&
    buffer.toString('ascii', 8, 12) === 'WAVE'
  ) {
    return { ext: 'wav', mime: 'audio/wav' };
  }
  if (
    buffer.length >= 12 &&
    buffer.toString('ascii', 4, 8) === 'ftyp'
  ) {
    const brand = buffer.toString('ascii', 8, 12).toLowerCase();
    return brand.includes('3g')
      ? { ext: '3gp', mime: 'video/3gpp' }
      : { ext: 'mp4', mime: 'video/mp4' };
  }
  if (
    buffer.length >= 4 &&
    buffer[0] === 0x1a &&
    buffer[1] === 0x45 &&
    buffer[2] === 0xdf &&
    buffer[3] === 0xa3
  ) {
    return { ext: 'webm', mime: 'video/webm' };
  }
  return null;
}

async function detectMediaType(
  buffer: Buffer,
  hintedMime: string | null,
): Promise<DetectedMediaType> {
  try {
    const mod = await import('file-type');
    const detected = await mod.fileTypeFromBuffer(buffer);
    if (detected?.mime && detected.ext) {
      const mime = normalizeMimeType(detected.mime) ?? detected.mime;
      return { ext: extensionForMime(mime) ?? detected.ext, mime };
    }
  } catch (error) {
    console.warn(
      `[WhatsappInbox][Media] file-type no disponible, usando fallback: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  }

  const fallback = fallbackDetectMediaType(buffer);
  if (fallback) return fallback;

  const mime = normalizeMimeType(hintedMime) ?? 'application/octet-stream';
  return { ext: extensionForMime(mime) ?? 'bin', mime };
}

function parseDataUriMedia(value: string): { buffer: Buffer; mime: string | null } | null {
  const commaIdx = value.indexOf(',');
  if (!value.startsWith('data:') || commaIdx === -1) return null;
  const header = value.substring(5, commaIdx);
  const mime = normalizeMimeType(header.split(';')[0]);
  const base64 = value.substring(commaIdx + 1).trim();
  if (!base64) return null;
  return { buffer: Buffer.from(base64, 'base64'), mime };
}

function sanitizeObjectSegment(value: string): string {
  return value
    .trim()
    .replace(/[^a-zA-Z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}

function originalFileNameFromPayload(payload: unknown): string | null {
  const root = asRecord(payload);
  const data = asRecord(root?.data) ?? asRecord(root?.message) ?? root;
  const message =
    asRecord(data?.message) ??
    asRecord(data?.messageData) ??
    asRecord(data?.messageContent) ??
    {};
  for (const record of [
    asRecord(message.documentMessage),
    asRecord(message.imageMessage),
    asRecord(message.videoMessage),
    asRecord(message.audioMessage),
    message,
    data,
  ]) {
    const name = asString(record?.fileName) ?? asString(record?.filename);
    if (name) return name.slice(0, 180);
  }
  return null;
}

function collectEvolutionMessageRecords(value: unknown): unknown[] {
  if (Array.isArray(value)) return value;
  const record = asRecord(value);
  if (!record) return [];

  for (const key of [
    'messages',
    'records',
    'data',
    'items',
    'rows',
    'message',
    'messageData',
    'messageContent',
  ]) {
    const nested = record[key];
    if (Array.isArray(nested)) return nested;
    const nestedRecord = asRecord(nested);
    if (nestedRecord) {
      const nestedMessages = collectEvolutionMessageRecords(nestedRecord);
      if (nestedMessages.length > 0) return nestedMessages;
    }
  }
  return [];
}

function conversationIdentityKeys(
  remoteJid: unknown,
  remotePhone: unknown,
): string[] {
  const keys: string[] = [];
  const phone = firstPhone(remotePhone, remoteJid);
  if (phone) keys.push(`phone:${phone}`);

  const jid = asString(remoteJid)?.toLowerCase();
  if (jid) keys.push(`jid:${jid}`);

  return Array.from(new Set(keys));
}

function extractChatAvatarUrl(chatRecord: JsonRecord): string | null {
  const contact =
    asRecord(chatRecord.contact) ?? asRecord(chatRecord.contactInfo);
  const picture = asRecord(chatRecord.picture) ?? asRecord(contact?.picture);

  return (
    asString(chatRecord.profilePicUrl) ??
    asString(chatRecord.profilePictureUrl) ??
    asString(chatRecord.avatarUrl) ??
    asString(chatRecord.photoUrl) ??
    asString(chatRecord.pictureUrl) ??
    asString(contact?.profilePicUrl) ??
    asString(contact?.profilePictureUrl) ??
    asString(contact?.avatarUrl) ??
    asString(contact?.photoUrl) ??
    asString(contact?.pictureUrl) ??
    asString(picture?.url) ??
    null
  );
}

function payloadKeyRemoteJid(value: unknown): string | null {
  const root = asRecord(value);
  const data = asRecord(root?.data) ?? asRecord(root?.message) ?? root;
  const message =
    asRecord(data?.message) ??
    asRecord(data?.messageData) ??
    asRecord(data?.messageContent);
  const key =
    asRecord(data?.key) ?? asRecord(message?.key) ?? asRecord(root?.key);
  return asString(key?.remoteJid) ?? null;
}

function payloadPreviousRemoteJid(value: unknown): string | null {
  const root = asRecord(value);
  const data = asRecord(root?.data) ?? asRecord(root?.message) ?? root;
  const message =
    asRecord(data?.message) ??
    asRecord(data?.messageData) ??
    asRecord(data?.messageContent);
  const key =
    asRecord(data?.key) ?? asRecord(message?.key) ?? asRecord(root?.key);
  return asString(key?.previousRemoteJid) ?? null;
}

export type ResolvedWhatsappConversationIdentity = {
  customerJid: string;
  customerPhone: string | null;
  customerName: string | null;
  fromMe: boolean;
  messageId: string;
  text: string | null;
  keyRemoteJid: string | null;
  participant: string | null;
  sender: string | null;
  instancePhone: string | null;
};

export function resolveWhatsappConversationIdentity(
  payload: unknown,
  instance?: {
    phoneNumber?: string | null;
    instanceName?: string | null;
  } | null,
  context?: { eventName?: string | null },
): ResolvedWhatsappConversationIdentity | null {
  const p = asRecord(payload);
  if (!p) return null;
  const data = asRecord(p.data) ?? asRecord(p.message) ?? p;
  const messageObj =
    asRecord(data.message) ??
    asRecord(data.messageData) ??
    asRecord(data.messageContent) ??
    {};
  const key = asRecord(data.key) ?? asRecord(messageObj.key) ?? asRecord(p.key);
  if (!key) return null;

  const eventName =
    normalizeEventName(p.event) ??
    normalizeEventName((p as JsonRecord).eventName) ??
    normalizeEventName((p as JsonRecord).type) ??
    normalizeEventName(data.event) ??
    normalizeEventName((data as JsonRecord).eventName) ??
    normalizeEventName((data as JsonRecord).type) ??
    normalizeEventName(context?.eventName) ??
    null;
  const fromMe =
    asBoolean(key.fromMe) ??
    asBoolean(data.fromMe) ??
    asBoolean(asRecord(data.contextInfo)?.fromMe) ??
    asBoolean(p.fromMe) ??
    asBoolean((p as JsonRecord)['from_me']) ??
    (isOutgoingEventName(eventName) ||
      asString(data.from)?.toLowerCase() === 'me' ||
      asString(data.from)?.toLowerCase() === 'self' ||
      asString(data.owner)?.toLowerCase() === 'me');

  const keyRemoteJid = asString(key.remoteJid);
  const participant =
    asString(key.participant) ??
    asString(data.participant) ??
    asString(data.sender) ??
    asString(data.senderPn) ??
    null;
  const sender = asString(data.sender) ?? asString(data.from) ?? null;

  // Baileys/Evolution keeps the customer chat in key.remoteJid for both incoming
  // and outgoing messages. Never resolve a conversation from "sender", "from",
  // the company instance phone, or the literal "me".
  const customerRaw =
    keyRemoteJid ??
    asString(data.remoteJid) ??
    asString(data.chatId) ??
    asString(data.to) ??
    asString(data.number) ??
    asString(data.recipient) ??
    null;
  const customerIdentity = normalizeWhatsappIdentity(customerRaw);
  const customerJid = customerIdentity.normalizedJid ?? customerRaw;
  if (!customerJid || customerJid === 'status@broadcast') return null;

  const instancePhone = normalizeWhatsappPhone(instance?.phoneNumber);
  const customerPhone =
    customerIdentity.normalizedPhone ??
    firstPhone(
      data.remotePhone,
      data.phone,
      data.number,
      data.to,
      data.recipient,
      customerJid,
    );

  const pushName =
    asString(data.pushName) ??
    asString(data.notifyName) ??
    asString(data.contactName) ??
    null;
  const customerName = fromMe
    ? null
    : readableSenderName(pushName, customerPhone);
  const messageId =
    asString(key.id) ??
    asString(data.id) ??
    asString(asRecord(data.message)?.['id']) ??
    asString(asRecord(data.message)?.['messageId']) ??
    asString(asRecord(data.messageInfo)?.['id']) ??
    asString(data.messageId) ??
    '';
  const text =
    asString(messageObj.conversation) ??
    asString(asRecord(messageObj.extendedTextMessage)?.text) ??
    asString(data.text) ??
    asString(data.body) ??
    asString(data.messageText) ??
    null;

  return {
    customerJid,
    customerPhone,
    customerName,
    fromMe,
    messageId,
    text,
    keyRemoteJid: keyRemoteJid ?? null,
    participant,
    sender,
    instancePhone,
  };
}

@Injectable()
export class WhatsappInboxService {
  private whatsappMediaColumnsAvailableCache: boolean | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: CatalogRealtimeRelayService,
    private readonly config: ConfigService,
    private readonly whatsappService: WhatsappService,
    private readonly r2: R2Service,
    private readonly redis: RedisService,
    @Inject(forwardRef(() => CrmBotService))
    private readonly crmBotService?: CrmBotService,
  ) {}

  private conversationsCacheKey(instanceId: string, limit: number) {
    return `whatsapp-inbox:conversations:${instanceId}:limit:${limit}`;
  }

  private avatarsCacheKey(instanceId: string) {
    return `whatsapp-inbox:avatars:${instanceId}`;
  }

  private avatarsRefreshLockKey(instanceId: string) {
    return `whatsapp-inbox:avatars-refresh:${instanceId}`;
  }

  private messagesCacheKey(conversationId: string, limit: number) {
    return `whatsapp-inbox:messages:${conversationId}:limit:${limit}`;
  }

  private mapToAvatarCachePayload(
    avatarByConversationKey: Map<string, string>,
  ): Record<string, string> {
    const payload: Record<string, string> = {};
    for (const [key, value] of avatarByConversationKey.entries()) {
      const normalizedKey = key.trim();
      const normalizedValue = value.trim();
      if (!normalizedKey || !normalizedValue) continue;
      payload[normalizedKey] = normalizedValue;
    }
    return payload;
  }

  private avatarCachePayloadToMap(
    payload: unknown,
  ): Map<string, string> {
    if (!payload || typeof payload !== 'object') {
      return new Map<string, string>();
    }
    const record = payload as Record<string, unknown>;
    const map = new Map<string, string>();
    for (const [key, value] of Object.entries(record)) {
      const normalizedKey = key.trim();
      const normalizedValue =
        typeof value === 'string' ? value.trim() : String(value ?? '').trim();
      if (!normalizedKey || !normalizedValue) continue;
      map.set(normalizedKey, normalizedValue);
    }
    return map;
  }

  private async loadAvatarCache(
    instanceId: string,
  ): Promise<Map<string, string>> {
    const payload = await this.redis.get<unknown>(this.avatarsCacheKey(instanceId));
    return this.avatarCachePayloadToMap(payload);
  }

  private async saveAvatarCache(
    instanceId: string,
    avatarByConversationKey: Map<string, string>,
  ) {
    const payload = this.mapToAvatarCachePayload(avatarByConversationKey);
    if (Object.keys(payload).length === 0) return;
    await this.redis.set(this.avatarsCacheKey(instanceId), payload, 1800);
  }

  private mergeAvatarCache(
    base: Map<string, string>,
    incoming: Map<string, string>,
  ): Map<string, string> {
    const merged = new Map<string, string>(base);
    for (const [key, value] of incoming.entries()) {
      const normalizedKey = key.trim();
      const normalizedValue = value.trim();
      if (!normalizedKey || !normalizedValue) continue;
      merged.set(normalizedKey, normalizedValue);
    }
    return merged;
  }

  private async refreshAvatarCacheFromEvolution(
    instanceId: string,
    current: Map<string, string>,
  ): Promise<Map<string, string>> {
    const lockAcquired = await this.redis.tryLock(
      this.avatarsRefreshLockKey(instanceId),
      30,
    );
    if (!lockAcquired) {
      return current;
    }
    try {
      const sync = await this.syncRecentChatsFromEvolution(instanceId);
      const merged = this.mergeAvatarCache(current, sync.avatarByConversationKey);
      await this.saveAvatarCache(instanceId, merged);
      return merged;
    } catch (error) {
      console.warn(
        `[WhatsappInbox] No se pudo refrescar avatar cache para instancia ${instanceId}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return current;
    }
  }

  private async invalidateWhatsappInboxCache(
    instanceId: string,
    conversationId?: string | null,
  ) {
    await Promise.all([
      this.redis.delByPattern(`whatsapp-inbox:conversations:${instanceId}:*`),
      conversationId
        ? this.redis.delByPattern(`whatsapp-inbox:messages:${conversationId}:*`)
        : Promise.resolve(0),
    ]).catch((error) => {
      console.warn('[WhatsappInbox][RedisInvalidate]', {
        instanceId,
        conversationId,
        error: error instanceof Error ? error.message : String(error),
      });
    });
  }

  private logRealtimeTiming(
    label: string,
    startedAt: number | undefined,
    extra?: Record<string, unknown>,
  ) {
    console.log(label, {
      elapsedMs: startedAt ? Date.now() - startedAt : null,
      ...(extra ?? {}),
    });
  }

  private async hasWhatsappMediaColumns(): Promise<boolean> {
    if (this.whatsappMediaColumnsAvailableCache !== null) {
      return this.whatsappMediaColumnsAvailableCache;
    }
    try {
      const rows = await this.prisma.$queryRaw<
        Array<{ column_name: string }>
      >`
        SELECT column_name
        FROM information_schema.columns
        WHERE table_name = 'whatsapp_messages'
          AND column_name IN (
            'media_storage_key',
            'media_file_size',
            'original_file_name',
            'playable_storage_key',
            'playable_mime_type',
            'media_status',
            'media_error'
          )
      `;
      const names = new Set(rows.map((row) => row.column_name));
      this.whatsappMediaColumnsAvailableCache =
        names.has('media_storage_key') &&
        names.has('media_file_size') &&
        names.has('original_file_name') &&
        names.has('media_status') &&
        names.has('media_error');
      if (!this.whatsappMediaColumnsAvailableCache) {
        console.warn('[WhatsappInbox][MediaOptionalError]', {
          reason: 'media_columns_missing',
          found: Array.from(names),
        });
      }
      return this.whatsappMediaColumnsAvailableCache;
    } catch (error) {
      this.whatsappMediaColumnsAvailableCache = false;
      console.warn('[WhatsappInbox][MediaOptionalError]', {
        reason: 'media_columns_check_failed',
        error: error instanceof Error ? error.message : String(error),
      });
      return false;
    }
  }

  private whatsappMessageBaseSelect() {
    return {
      id: true,
      conversationId: true,
      evolutionId: true,
      direction: true,
      messageType: true,
      body: true,
      mediaUrl: true,
      mediaMimeType: true,
      caption: true,
      senderName: true,
      sentAt: true,
      createdAt: true,
      rawPayload: true,
    };
  }

  private emitWhatsappMessageRealtime(params: {
    instanceId: string;
    conversation: {
      id: string;
      instanceId: string;
      remoteJid: string;
      remotePhone: string | null;
      remoteName: string | null;
      lastMessageAt: Date | null;
      unreadCount: number;
    };
    message: {
      id: string;
      sentAt: Date;
      createdAt?: Date;
      direction: WhatsappMessageDirection;
      messageType: WhatsappMessageType;
      body: string | null;
      mediaUrl?: string | null;
      mediaMimeType?: string | null;
      caption: string | null;
      senderName: string | null;
      evolutionId: string | null;
      mediaStorageKey?: string | null;
      mediaFileSize?: number | null;
      mediaStatus?: string | null;
      mediaError?: string | null;
      originalFileName?: string | null;
    };
    realtimeStartedAt?: number;
  }) {
    const { instanceId, conversation, message, realtimeStartedAt } = params;
    const payload = {
      eventId: message.id,
      conversationId: conversation.id,
      instanceId,
      message: {
        id: message.id,
        direction: message.direction,
        createdAt: message.sentAt,
        messageType: message.messageType,
        text: message.body,
        body: message.body,
        mediaUrl: message.mediaStorageKey
          ? this.buildStoredMediaUrl({
              messageId: message.id,
              storageKey: message.mediaStorageKey,
              mimeType: message.mediaMimeType,
              fileSize: message.mediaFileSize,
            })
          : message.mediaUrl ?? null,
        mediaMimeType: message.mediaMimeType ?? null,
        mediaStorageKey: message.mediaStorageKey ?? null,
        mediaFileSize: message.mediaFileSize ?? null,
        mediaStatus: message.mediaStorageKey
          ? 'ready'
          : message.mediaStatus ?? null,
        mediaError: message.mediaError ?? null,
        originalFileName: message.originalFileName ?? null,
        caption: message.caption,
        senderName: message.senderName,
        sentAt: message.sentAt,
        evolutionId: message.evolutionId,
      },
      conversation: {
        id: conversation.id,
        instanceId,
        remoteJid: conversation.remoteJid,
        remotePhone: conversation.remotePhone,
        remoteName: conversation.remoteName,
        lastMessageAt: conversation.lastMessageAt,
        unreadCount: conversation.unreadCount,
      },
    };

    void this.publishWhatsappRealtimeAccelerators(
      instanceId,
      conversation.id,
      payload,
      realtimeStartedAt,
    );

    this.realtime.emitTo('ops:role:admin', 'whatsapp.message', payload);
    this.logRealtimeTiming('[WhatsAppRealtime][SocketEmitted]', realtimeStartedAt, {
      messageId: message.id,
      conversationId: conversation.id,
    });
  }

  private async publishWhatsappRealtimeAccelerators(
    instanceId: string,
    conversationId: string,
    payload: unknown,
    startedAt?: number,
  ) {
    await Promise.all([
      this.redis.publish('whatsapp-inbox:message', payload),
      this.redis.set(`whatsapp-inbox:last-message:${conversationId}`, payload, 60),
      this.redis.set(`whatsapp-inbox:last-conversation:${instanceId}`, payload, 60),
    ]);
    this.logRealtimeTiming('[WhatsAppRealtime][RedisPublished]', startedAt, {
      conversationId,
    });
  }

  private buildApiMediaUrl(messageId: string): string {
    return `/whatsapp-inbox/media/${messageId}`;
  }

  private buildWhatsappMediaVersion(params: {
    storageKey?: string | null;
    mimeType?: string | null;
    fileSize?: number | null;
    playableStorageKey?: string | null;
    playableMimeType?: string | null;
  }): string {
    const seed = [
      params.storageKey?.trim() ?? '',
      normalizeMimeType(params.mimeType) ?? '',
      params.fileSize != null ? String(params.fileSize) : '',
      params.playableStorageKey?.trim() ?? '',
      normalizeMimeType(params.playableMimeType) ?? '',
    ].join('|');
    return createHash('sha1').update(seed).digest('hex').slice(0, 12);
  }

  private buildStoredMediaUrl(params: {
    messageId: string;
    storageKey?: string | null;
    mimeType?: string | null;
    fileSize?: number | null;
    playableStorageKey?: string | null;
    playableMimeType?: string | null;
  }): string {
    const version = this.buildWhatsappMediaVersion(params);
    return `${this.buildApiMediaUrl(params.messageId)}?v=${version}`;
  }

  private buildWhatsappMediaKey(params: {
    instanceId: string;
    messageId: string;
    messageType: WhatsappMessageType;
    ext: string;
  }): string {
    const now = new Date();
    const yyyy = String(now.getUTCFullYear());
    const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
    const type = params.messageType.toLowerCase();
    const id = sanitizeObjectSegment(params.messageId) || randomUUID();
    return `whatsapp/inbox/${params.instanceId}/${yyyy}/${mm}/${type}/${id}.${params.ext}`;
  }

  private async downloadRemoteMedia(url: string): Promise<{
    buffer: Buffer;
    mime: string | null;
  }> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch(url, { signal: controller.signal });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      const responseMime = normalizeMimeType(response.headers.get('content-type'));
      const arrayBuffer = await response.arrayBuffer();
      const buffer = Buffer.from(arrayBuffer);
      const preview = buffer.subarray(0, 80).toString('utf8').trim();
      if (
        responseMime === 'application/json' ||
        responseMime === 'text/html' ||
        preview.startsWith('{') ||
        preview.startsWith('<!DOCTYPE') ||
        preview.startsWith('<html')
      ) {
        throw new Error(
          `URL de media devolvio contenido no binario (${responseMime ?? 'sin content-type'})`,
        );
      }
      return {
        buffer,
        mime: responseMime,
      };
    } finally {
      clearTimeout(timeout);
    }
  }

  private async resolveMediaBuffer(
    parsed: ParsedWhatsappMessage,
    instanceName?: string | null,
  ): Promise<{ buffer: Buffer; hintedMime: string | null; source: string }> {
    const dataUri = parsed.mediaUrl ? parseDataUriMedia(parsed.mediaUrl) : null;
    if (dataUri) {
      return {
        buffer: dataUri.buffer,
        hintedMime: dataUri.mime ?? parsed.mediaMimeType,
        source: 'payload_data_uri',
      };
    }

    if (
      parsed.mediaUrl &&
      /^https?:\/\//i.test(parsed.mediaUrl) &&
      !mediaNeedsEvolutionBase64(parsed.mediaUrl)
    ) {
      const downloaded = await this.downloadRemoteMedia(parsed.mediaUrl);
      return {
        buffer: downloaded.buffer,
        hintedMime: downloaded.mime ?? parsed.mediaMimeType,
        source: 'payload_url',
      };
    }

    if (!instanceName) {
      throw new Error('No hay instancia Evolution para descargar media');
    }

    const candidates = [
      evolutionMediaMessageFromPayload(parsed.rawPayload),
      parsed.rawPayload,
    ];
    let base64: string | null = null;
    let lastError: string | null = null;
    for (const candidate of candidates) {
      try {
        const raw = await this.whatsappService.getBase64FromMediaMessage(
          instanceName,
          candidate,
        );
        base64 = findBase64InResponse(raw);
        if (base64) break;
      } catch (error) {
        lastError = error instanceof Error ? error.message : String(error);
      }
    }
    if (!base64) {
      throw new Error(
        lastError
          ? `Evolution no devolvio base64 de media: ${lastError}`
          : 'Evolution no devolvio base64 de media',
      );
    }
    const fromEvolution = base64.startsWith('data:')
      ? parseDataUriMedia(base64)
      : { buffer: Buffer.from(base64, 'base64'), mime: parsed.mediaMimeType };
    if (!fromEvolution?.buffer?.length) {
      throw new Error('Media base64 vacia o invalida');
    }
    return {
      buffer: fromEvolution.buffer,
      hintedMime: fromEvolution.mime ?? parsed.mediaMimeType,
      source: 'evolution_base64',
    };
  }

  private async prepareWhatsappMedia(params: {
    messageId: string;
    instanceId: string;
    parsed: ParsedWhatsappMessage;
  }): Promise<PreparedWhatsappMedia | null> {
    const { parsed } = params;
    if (parsed.messageType === WhatsappMessageType.TEXT) return null;

    try {
      if (!parsed.fromMe) {
        console.log('[WhatsappInbox][IncomingMedia][Payload]', {
          ...mediaPayloadDiagnostic(parsed.rawPayload, parsed),
          instanceName: parsed.instanceName,
          fromMe: parsed.fromMe,
        });
      }
      console.log('[WhatsappInbox][Media] start', {
        messageId: params.messageId,
        type: parsed.messageType,
        payloadMime: parsed.mediaMimeType,
        hasPayloadUrl: !!parsed.mediaUrl,
      });
      const resolved = await this.resolveMediaBuffer(parsed, parsed.instanceName);
      if (resolved.buffer.length === 0) throw new Error('Buffer de media vacio');
      const detected = await detectMediaType(
        resolved.buffer,
        resolved.hintedMime ?? parsed.mediaMimeType,
      );
      const objectKey = this.buildWhatsappMediaKey({
        instanceId: params.instanceId,
        messageId: params.messageId,
        messageType: parsed.messageType,
        ext: detected.ext,
      });

      console.log('[WhatsappInbox][Media] upload', {
        messageId: params.messageId,
        source: resolved.source,
        bytes: resolved.buffer.length,
        payloadMime: parsed.mediaMimeType,
        hintedMime: resolved.hintedMime,
        detectedMime: detected.mime,
        ext: detected.ext,
        objectKey,
      });

      await this.r2.putObject({
        objectKey,
        body: resolved.buffer,
        contentType: detected.mime,
      });

      if (!parsed.fromMe) {
        console.log('[WhatsappInbox][IncomingMedia]', {
          messageId: params.messageId,
          instanceName: parsed.instanceName,
          fromMe: parsed.fromMe,
          messageType: parsed.messageType,
          source: resolved.source,
          receivedMime: resolved.hintedMime ?? parsed.mediaMimeType,
          detectedMime: detected.mime,
          bufferSize: resolved.buffer.length,
          r2Key: objectKey,
          status: 'ready',
        });
      }

      return {
        mediaUrl: this.buildStoredMediaUrl({
          messageId: params.messageId,
          storageKey: objectKey,
          mimeType: detected.mime,
          fileSize: resolved.buffer.length,
        }),
        mediaMimeType: detected.mime,
        mediaStorageKey: objectKey,
        mediaFileSize: resolved.buffer.length,
        originalFileName: originalFileNameFromPayload(parsed.rawPayload),
        playableStorageKey: null,
        playableMimeType: null,
        mediaStatus: 'ready',
        mediaError: null,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!parsed.fromMe) {
        console.error('[WhatsappInbox][IncomingMedia]', {
          messageId: params.messageId,
          instanceName: parsed.instanceName,
          fromMe: parsed.fromMe,
          messageType: parsed.messageType,
          source: 'failed',
          receivedMime: parsed.mediaMimeType,
          detectedMime: null,
          bufferSize: 0,
          r2Key: null,
          status: 'failed',
          error: message,
        });
      }
      console.error('[WhatsappInbox][Media] failed', {
        messageId: params.messageId,
        type: parsed.messageType,
        payloadMime: parsed.mediaMimeType,
        error: message,
      });
      return {
        mediaUrl: parsed.mediaUrl ?? this.buildApiMediaUrl(params.messageId),
        mediaMimeType:
          normalizeMimeType(parsed.mediaMimeType) ?? 'application/octet-stream',
        mediaStorageKey: '',
        mediaFileSize: 0,
        originalFileName: originalFileNameFromPayload(parsed.rawPayload),
        playableStorageKey: null,
        playableMimeType: null,
        mediaStatus: 'failed',
        mediaError: message,
      };
    }
  }

  private async ensureMessageMediaStored<
    T extends {
      id: string;
      messageType: WhatsappMessageType;
      mediaStorageKey?: string | null;
      mediaUrl?: string | null;
    },
  >(message: T, instanceId: string, parsed: ParsedWhatsappMessage): Promise<T> {
    if (message.messageType === WhatsappMessageType.TEXT) {
      return message;
    }

    if (!(await this.hasWhatsappMediaColumns())) {
      return message;
    }

    if (message.mediaStorageKey) {
      const mediaUrl = this.buildStoredMediaUrl({
        messageId: message.id,
        storageKey: message.mediaStorageKey,
      });
      if (message.mediaUrl !== mediaUrl) {
        return (await this.prisma.whatsappMessage.update({
          where: { id: message.id },
          data: { mediaUrl, mediaStatus: 'ready', mediaError: null },
        })) as unknown as T;
      }
      return message;
    }

    const prepared = await this.prepareWhatsappMedia({
      messageId: message.id,
      instanceId,
      parsed,
    });
    if (!prepared) return message;

    const data =
      prepared.mediaStatus === 'ready'
        ? {
            mediaUrl: prepared.mediaUrl,
            mediaMimeType: prepared.mediaMimeType,
            mediaStorageKey: prepared.mediaStorageKey,
            mediaFileSize: prepared.mediaFileSize,
            originalFileName: prepared.originalFileName,
            playableStorageKey: prepared.playableStorageKey,
            playableMimeType: prepared.playableMimeType,
            mediaStatus: prepared.mediaStatus,
            mediaError: null,
          }
        : {
            mediaMimeType: prepared.mediaMimeType,
            originalFileName: prepared.originalFileName,
            mediaStatus: prepared.mediaStatus,
            mediaError: prepared.mediaError,
          };

    return (await this.prisma.whatsappMessage.update({
      where: { id: message.id },
      data,
    })) as unknown as T;
  }

  private materializeMessageMediaInBackground(params: {
    message: {
      id: string;
      messageType: WhatsappMessageType;
      mediaUrl?: string | null;
      mediaStorageKey?: string | null;
      rawPayload?: unknown;
    };
    instanceId: string;
    instanceName: string;
    instance?: { phoneNumber?: string | null; instanceName?: string | null } | null;
    conversation?: {
      id: string;
      instanceId: string;
      remoteJid: string;
      remotePhone: string | null;
      remoteName: string | null;
      lastMessageAt: Date | null;
      unreadCount: number;
    };
  }) {
    const { message, instanceId, instanceName, instance, conversation } = params;
    if (
      message.messageType === WhatsappMessageType.TEXT ||
      message.mediaStorageKey ||
      !message.rawPayload
    ) {
      return;
    }

    void (async () => {
      try {
        if (!(await this.hasWhatsappMediaColumns())) return;
        const parsed = this.parseEvolutionPayload(message.rawPayload, {
          instanceName,
          instance: instance ?? { instanceName },
        });
        if (!parsed) return;
        const ready = await this.ensureMessageMediaStored(message, instanceId, parsed);
        if (conversation) {
          this.emitWhatsappMessageRealtime({
            instanceId,
            conversation,
            message: ready as typeof ready & {
              sentAt: Date;
              createdAt?: Date;
              direction: WhatsappMessageDirection;
              body: string | null;
              mediaMimeType: string | null;
              caption: string | null;
              senderName: string | null;
              evolutionId: string | null;
              mediaFileSize?: number | null;
              mediaStatus?: string | null;
              mediaError?: string | null;
              originalFileName?: string | null;
            },
          });
        }
      } catch (error) {
        console.warn('[WhatsappInbox][MediaOptionalError]', {
          messageId: message.id,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    })();
  }

  async getMediaBytes(messageId: string, range?: string | null) {
    const message = await this.prisma.whatsappMessage.findUnique({
      where: { id: messageId },
      select: {
        id: true,
        body: true,
        messageType: true,
        mediaStorageKey: true,
        mediaMimeType: true,
        mediaFileSize: true,
        originalFileName: true,
        mediaStatus: true,
      },
    });
    if (!message) throw new NotFoundException('Media no encontrada');
    if (!message.mediaStorageKey || message.mediaStatus === 'failed') {
      throw new NotFoundException('Archivo no disponible');
    }

    const rangeHeader = range?.trim();
    const object = rangeHeader?.startsWith('bytes=')
      ? await this.r2.getObjectRange(message.mediaStorageKey, rangeHeader)
      : await this.r2.getObject(message.mediaStorageKey);
    const filename =
      message.originalFileName ??
      `${message.messageType.toLowerCase()}-${message.id}.${
        extensionForMime(message.mediaMimeType) ?? 'bin'
      }`;
    return {
      body: object.body,
      contentType:
        object.contentType ?? message.mediaMimeType ?? 'application/octet-stream',
      contentLength: object.contentLength,
      contentRange: 'contentRange' in object ? object.contentRange : null,
      filename,
      partial: !!rangeHeader?.startsWith('bytes='),
    };
  }

  async auditExistingMedia(options?: { execute?: boolean; limit?: number }) {
    const execute = !!options?.execute;
    const limit = Math.max(1, Math.min(options?.limit ?? 100, 1000));
    const messages = await this.prisma.whatsappMessage.findMany({
      where: {
        messageType: { not: WhatsappMessageType.TEXT },
      },
      include: {
        conversation: {
          include: { instance: { select: { id: true, instanceName: true } } },
        },
      },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });

    const results: Array<{
      id: string;
      type: string;
      status: string;
      beforeMime: string | null;
      afterMime?: string | null;
      storageKey?: string | null;
      error?: string | null;
    }> = [];

    for (const message of messages) {
      try {
        if (message.mediaStorageKey) {
          const object = await this.r2.getObject(message.mediaStorageKey);
          const detected = await detectMediaType(
            object.body,
            object.contentType ?? message.mediaMimeType,
          );
          const normalizedObjectMime = normalizeMimeType(object.contentType);
          const repairedStorageKey = replaceObjectKeyExtension(
            message.mediaStorageKey,
            detected.ext,
          );
          const mismatch =
            normalizeMimeType(message.mediaMimeType) !== detected.mime ||
            normalizedObjectMime !== detected.mime ||
            repairedStorageKey !== message.mediaStorageKey ||
            message.mediaFileSize !== object.body.length;
          if (execute && mismatch) {
            await this.r2.putObject({
              objectKey: repairedStorageKey,
              body: object.body,
              contentType: detected.mime,
            });
            await this.prisma.whatsappMessage.update({
              where: { id: message.id },
              data: {
                mediaUrl: this.buildStoredMediaUrl({
                  messageId: message.id,
                  storageKey: repairedStorageKey,
                  mimeType: detected.mime,
                  fileSize: object.body.length,
                }),
                mediaMimeType: detected.mime,
                mediaStorageKey: repairedStorageKey,
                mediaFileSize: object.body.length,
                mediaStatus: 'ready',
                mediaError: null,
              },
            });
          }
          results.push({
            id: message.id,
            type: message.messageType,
            status: mismatch
              ? execute
                ? repairedStorageKey !== message.mediaStorageKey ||
                  normalizedObjectMime !== detected.mime
                  ? 'repaired_object'
                  : 'updated_metadata'
                : 'mismatch'
              : 'ok',
            beforeMime: message.mediaMimeType,
            afterMime: detected.mime,
            storageKey:
              mismatch && execute ? repairedStorageKey : message.mediaStorageKey,
          });
          continue;
        }

        if (!execute) {
          results.push({
            id: message.id,
            type: message.messageType,
            status: 'missing_storage_key',
            beforeMime: message.mediaMimeType,
            storageKey: null,
          });
          continue;
        }

        const parsed = this.parseEvolutionPayload(message.rawPayload, {
          instanceName: message.conversation.instance.instanceName,
          instance: message.conversation.instance,
        });
        if (!parsed) {
          await this.prisma.whatsappMessage.update({
            where: { id: message.id },
            data: { mediaStatus: 'failed', mediaError: 'Payload no parseable' },
          });
          results.push({
            id: message.id,
            type: message.messageType,
            status: 'failed',
            beforeMime: message.mediaMimeType,
            error: 'Payload no parseable',
          });
          continue;
        }
        const repaired = await this.ensureMessageMediaStored(
          message,
          message.conversation.instanceId,
          parsed,
        );
        results.push({
          id: message.id,
          type: message.messageType,
          status: repaired.mediaStorageKey ? 'repaired' : 'failed',
          beforeMime: message.mediaMimeType,
          afterMime: repaired.mediaMimeType,
          storageKey: repaired.mediaStorageKey,
          error: repaired.mediaError,
        });
      } catch (error) {
        const messageText = error instanceof Error ? error.message : String(error);
        if (execute) {
          await this.prisma.whatsappMessage.update({
            where: { id: message.id },
            data: { mediaStatus: 'failed', mediaError: messageText },
          });
        }
        results.push({
          id: message.id,
          type: message.messageType,
          status: 'failed',
          beforeMime: message.mediaMimeType,
          error: messageText,
        });
      }
    }

    const summary = results.reduce(
      (acc, item) => {
        acc[item.status] = (acc[item.status] ?? 0) + 1;
        return acc;
      },
      {} as Record<string, number>,
    );
    return { execute, scanned: messages.length, summary, results };
  }

  async debugMediaMessage(messageId: string) {
    const message = await this.prisma.whatsappMessage.findUnique({
      where: { id: messageId },
      include: {
        conversation: {
          include: { instance: { select: { id: true, instanceName: true, phoneNumber: true } } },
        },
      },
    });
    if (!message) throw new NotFoundException('Mensaje no encontrado');

    const parsed = message.rawPayload
      ? this.parseEvolutionPayload(message.rawPayload, {
          instanceName: message.conversation.instance.instanceName,
          instance: message.conversation.instance,
        })
      : null;

    let r2Head: unknown = null;
    let r2Error: string | null = null;
    if (message.mediaStorageKey) {
      try {
        r2Head = await this.r2.headObject(message.mediaStorageKey);
      } catch (error) {
        r2Error = error instanceof Error ? error.message : String(error);
      }
    }

    let resolved: unknown = null;
    if (parsed) {
      try {
        const bytes = await this.resolveMediaBuffer(
          parsed,
          message.conversation.instance.instanceName,
        );
        const detected = await detectMediaType(
          bytes.buffer,
          bytes.hintedMime ?? parsed.mediaMimeType,
        );
        resolved = {
          canResolve: true,
          source: bytes.source,
          bufferSize: bytes.buffer.length,
          receivedMime: bytes.hintedMime ?? parsed.mediaMimeType,
          detectedMime: detected.mime,
          detectedExt: detected.ext,
        };
      } catch (error) {
        resolved = {
          canResolve: false,
          error: error instanceof Error ? error.message : String(error),
        };
      }
    }

    let endpoint: unknown = null;
    try {
      const object = await this.getMediaBytes(messageId);
      endpoint = {
        wouldReturn: true,
        status: 200,
        contentType: object.contentType,
        contentLength: object.contentLength,
        isBinary: object.body.length > 0,
      };
    } catch (error) {
      endpoint = {
        wouldReturn: false,
        error: error instanceof Error ? error.message : String(error),
      };
    }

    return {
      message: {
        id: message.id,
        evolutionId: message.evolutionId,
        direction: message.direction,
        fromMe: message.direction === WhatsappMessageDirection.OUTGOING,
        messageType: message.messageType,
        mediaUrl: message.mediaUrl,
        mediaMimeType: message.mediaMimeType,
        mediaStorageKey: message.mediaStorageKey,
        mediaFileSize: message.mediaFileSize,
        mediaStatus: message.mediaStatus,
        mediaError: message.mediaError,
        hasRawPayload: !!message.rawPayload,
      },
      payload: parsed
        ? mediaPayloadDiagnostic(message.rawPayload, parsed)
        : { parseable: false },
      resolved,
      r2: { hasObject: !!message.mediaStorageKey && !r2Error, head: r2Head, error: r2Error },
      endpoint,
    };
  }

  private normalizeConversationForResponse<
    T extends {
      remoteJid: string;
      remotePhone: string | null;
      remoteName: string | null;
    },
  >(conversation: T): T {
    const cleanPhone =
      phoneFromIdentifier(conversation.remotePhone) ??
      phoneFromIdentifier(conversation.remoteJid);
    return {
      ...conversation,
      remotePhone: cleanPhone,
      remoteName: readableSenderName(conversation.remoteName, cleanPhone),
    };
  }

  private hydrateMessageMedia<
    T extends {
      mediaUrl: string | null;
      mediaMimeType: string | null;
      rawPayload?: unknown;
    },
  >(message: T): T {
    if (message.mediaUrl || !message.rawPayload) return message;
    const parsed = this.parseEvolutionPayload(message.rawPayload);
    if (!parsed?.mediaUrl) return message;
    return {
      ...message,
      mediaUrl: parsed.mediaUrl,
      mediaMimeType: parsed.mediaMimeType ?? message.mediaMimeType,
    };
  }

  private async hydratePlayableMessageMedia<
    T extends {
      id: string;
      mediaUrl: string | null;
      mediaMimeType: string | null;
      rawPayload?: unknown;
    },
  >(message: T, instanceName?: string | null): Promise<T> {
    const hydrated = this.hydrateMessageMedia(message);
    if (
      !instanceName ||
      !hydrated.rawPayload ||
      !mediaNeedsEvolutionBase64(hydrated.mediaUrl)
    ) {
      return hydrated;
    }

    try {
      const raw = await this.whatsappService.getBase64FromMediaMessage(
        instanceName,
        evolutionMediaMessageFromPayload(hydrated.rawPayload),
      );
      const base64 = findBase64InResponse(raw);
      if (!base64) return hydrated;
      const mediaUrl = base64.startsWith('data:')
        ? base64
        : `data:${hydrated.mediaMimeType ?? 'application/octet-stream'};base64,${base64}`;
      await this.prisma.whatsappMessage.update({
        where: { id: hydrated.id },
        data: { mediaUrl },
      });
      return { ...hydrated, mediaUrl };
    } catch (error) {
      console.warn(
        `[WhatsappInbox] No se pudo obtener media base64 para mensaje ${message.id}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return hydrated;
    }
  }

  // ─── Parse Evolution API webhook payload ───────────────────────────────

  parseEvolutionPayloads(
    payload: unknown,
    context?: {
      instanceName?: string | null;
      eventName?: string | null;
      instance?: {
        phoneNumber?: string | null;
        instanceName?: string | null;
      } | null;
    },
  ): ParsedWhatsappMessage[] {
    const p = asRecord(payload);
    if (!p) return [];

    const records = collectEvolutionMessageRecords(payload);
    if (records.length > 0) {
      return records
        .map((item) =>
          this.parseEvolutionPayload({ ...p, data: item }, context),
        )
        .filter((item): item is ParsedWhatsappMessage => !!item);
    }

    const parsed = this.parseEvolutionPayload(payload, context);
    return parsed ? [parsed] : [];
  }

  async handleIncomingWebhook(
    instanceName: string,
    payload: unknown,
    eventNameFromRoute?: string,
  ) {
    const realtimeStartedAt = Date.now();
    this.logRealtimeTiming('[WhatsAppRealtime][WebhookReceived]', realtimeStartedAt, {
      instanceName,
      eventName: eventNameFromRoute ?? null,
    });
    const instance = await this.findInstanceByName(instanceName);
    if (!instance) {
      console.warn(
        `[WhatsappInbox][Webhook] instanceName=${instanceName} eventName=${eventNameFromRoute ?? '-'} action=ignored reason=instance_not_registered`,
      );
      return { ok: true, ignored: true, reason: 'instance_not_registered' };
    }

    const payloadRecord = asRecord(payload);
    const payloadEvent =
      normalizeEventName(payloadRecord?.event) ??
      normalizeEventName(payloadRecord?.eventName) ??
      normalizeEventName(payloadRecord?.type);
    const eventName =
      normalizeEventName(eventNameFromRoute) ??
      payloadEvent ??
      'MESSAGES_UPSERT';

    const parsedMessages = this.parseEvolutionPayloads(payload, {
      instanceName,
      eventName,
      instance,
    });
    console.log(
      `[WhatsappInbox][Webhook] instanceName=${instanceName} eventName=${eventName} parsed=${parsedMessages.length} instanceId=${instance.id}`,
    );
    if (parsedMessages.length === 0) {
      console.warn(
        `[WhatsappInbox][Webhook] instanceName=${instanceName} eventName=${eventName} action=invalid reason=unparseable_payload`,
      );
      if (isOutgoingEventName(eventName) || eventName === 'UNKNOWN') {
        console.warn(
          'Manual WhatsApp outgoing event not received from Evolution. Check webhook events configuration.',
        );
      }
      return { ok: true, ignored: true, reason: 'unparseable_payload' };
    }

    let saved = 0;
    let duplicates = 0;
    let outgoingObserved = false;
    for (const parsed of parsedMessages) {
      const normalizedIdentity = normalizeWhatsappIdentity(parsed.remoteJid);
      const normalizedJid =
        normalizedIdentity.normalizedJid ?? parsed.remoteJid;
      const customerPhone =
        parsed.remotePhone ??
        normalizedIdentity.normalizedPhone ??
        phoneFromIdentifier(parsed.remoteJid);
      const existingByPhone = customerPhone
        ? await this.prisma.whatsappConversation.findFirst({
            where: { instanceId: instance.id, remotePhone: customerPhone },
            select: { id: true },
            orderBy: [{ lastMessageAt: 'desc' }, { updatedAt: 'desc' }],
          })
        : null;
      const existingByJid = existingByPhone
        ? null
        : await this.prisma.whatsappConversation.findUnique({
            where: {
              instanceId_remoteJid: {
                instanceId: instance.id,
                remoteJid: normalizedJid,
              },
            },
            select: { id: true },
          });
      const identity = resolveWhatsappConversationIdentity(
        parsed.rawPayload,
        instance,
        { eventName: parsed.eventName ?? eventName },
      );
      console.log('[WA-INBOX][IDENTITY]', {
        eventName: parsed.eventName ?? eventName,
        fromMe: parsed.fromMe,
        keyRemoteJid: identity?.keyRemoteJid ?? parsed.remoteJid,
        participant: identity?.participant ?? null,
        sender: identity?.sender ?? null,
        resolvedCustomerJid: parsed.remoteJid,
        resolvedCustomerPhone: customerPhone,
        instancePhone:
          identity?.instancePhone ??
          normalizeWhatsappPhone(instance.phoneNumber),
        existingConversationId:
          existingByPhone?.id ?? existingByJid?.id ?? null,
        willCreateNewConversation: !existingByPhone && !existingByJid,
      });
      const result = await this.saveMessage(instance.id, parsed, {
        realtimeStartedAt,
      });
      const action = result.action;
      if (result.duplicate) {
        duplicates++;
      } else {
        saved++;
      }
      if (parsed.fromMe) outgoingObserved = true;

      console.log('[WA-INBOX][SAVED]', {
        messageId: parsed.externalMessageId || result.message.id,
        direction: parsed.fromMe ? 'outgoing' : 'incoming',
        conversationId: result.conversation.id,
        customerPhone: parsed.remotePhone ?? null,
        action,
      });

      // ─── Trigger CRM Bot auto-responder for incoming customer messages ───
      if (
        !parsed.fromMe &&
        !result.duplicate &&
        this.crmBotService &&
        (parsed.body || parsed.caption)
      ) {
        const messageBody = (parsed.caption || parsed.body || '').trim();
        if (messageBody) {
          // Fire and forget – do not block the webhook response
          this.crmBotService.evaluateAndRespond(
            result.conversation.id,
            messageBody,
            result.message.id,
          ).catch((err: unknown) => {
            console.error('[CRM-BOT][AutoResponderError]', {
              conversationId: result.conversation.id,
              messageId: result.message.id,
              error: err instanceof Error ? err.message : String(err),
            });
          });
        }
      }
    }

    if (
      !outgoingObserved &&
      (isOutgoingEventName(eventName) || eventName === 'UNKNOWN')
    ) {
      console.warn(
        'Manual WhatsApp outgoing event not received from Evolution. Check webhook events configuration.',
      );
    }

    return { ok: true, saved, duplicate: duplicates };
  }

  private async findInstanceByName(instanceName: string) {
    let instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { instanceName },
      select: { id: true, userId: true, instanceName: true, phoneNumber: true },
    });

    if (!instance) {
      const normalizedInput = normalizeInstanceName(instanceName);
      if (normalizedInput) {
        const instances = await this.prisma.userWhatsappInstance.findMany({
          select: {
            id: true,
            userId: true,
            instanceName: true,
            phoneNumber: true,
          },
        });
        const byNormalized = instances.find(
          (item) =>
            normalizeInstanceName(item.instanceName) === normalizedInput,
        );
        if (byNormalized) {
          instance = {
            id: byNormalized.id,
            userId: byNormalized.userId,
            instanceName: byNormalized.instanceName,
            phoneNumber: byNormalized.phoneNumber,
          };
        }
      }
    }

    if (!instance) {
      const appConfig = await this.prisma.appConfig.findUnique({
        where: { id: 'global' },
        select: { evolutionApiInstanceName: true },
      });
      const configName = appConfig?.evolutionApiInstanceName ?? '';
      const sameCompanyInstance =
        configName === instanceName ||
        normalizeInstanceName(configName) ===
          normalizeInstanceName(instanceName);
      if (sameCompanyInstance) {
        const adminUser = await this.prisma.user.findFirst({
          where: { role: 'ADMIN' },
          select: { id: true },
        });
        if (adminUser) {
          instance = await this.prisma.userWhatsappInstance.upsert({
            where: { instanceName },
            create: {
              instanceName,
              userId: adminUser.id,
              status: 'connected',
              webhookEnabled: true,
            },
            update: {},
            select: {
              id: true,
              userId: true,
              instanceName: true,
              phoneNumber: true,
            },
          });
        }
      }
    }

    return instance;
  }

  parseEvolutionPayload(
    payload: unknown,
    context?: {
      instanceName?: string | null;
      eventName?: string | null;
      instance?: {
        phoneNumber?: string | null;
        instanceName?: string | null;
      } | null;
    },
  ): ParsedWhatsappMessage | null {
    try {
      const p = asRecord(payload);
      if (!p) return null;
      // Evolution API wraps message data in p.data
      const data = asRecord(p.data) ?? asRecord(p.message) ?? p;
      const messageObj =
        asRecord(data.message) ??
        asRecord(data.messageData) ??
        asRecord(data.messageContent) ??
        {};
      const key =
        asRecord(data.key) ?? asRecord(messageObj.key) ?? asRecord(p.key);
      if (!key) return null;
      const identity = resolveWhatsappConversationIdentity(
        payload,
        context?.instance ?? null,
        { eventName: context?.eventName ?? null },
      );
      if (!identity) return null;

      const eventName =
        normalizeEventName(p.event) ??
        normalizeEventName((p as JsonRecord).eventName) ??
        normalizeEventName((p as JsonRecord).type) ??
        normalizeEventName(data.event) ??
        normalizeEventName((data as JsonRecord).eventName) ??
        normalizeEventName((data as JsonRecord).type) ??
        normalizeEventName(context?.eventName) ??
        null;
      const instanceName =
        asString(p.instance) ??
        asString(p.instanceName) ??
        asString(p.instance_name) ??
        asString(data.instance) ??
        asString(data.instanceName) ??
        asString(data.instance_name) ??
        asString(context?.instanceName) ??
        null;

      const remoteJid = identity.customerJid;
      const remoteJidLower = remoteJid.toLowerCase();
      if (
        !remoteJid ||
        remoteJid === 'status@broadcast' ||
        remoteJidLower.endsWith('@g.us') ||
        remoteJidLower.includes('@g.us')
      ) {
        return null;
      }

      const fromMe = identity.fromMe;
      const evolutionId = identity.messageId;
      const pushName = asString(data.pushName) ?? null;
      const rawMessageType =
        asString(data.messageType) ??
        asString(data.type) ??
        (asString(messageObj.conversation)
          ? 'conversation'
          : messageObj.extendedTextMessage
            ? 'extendedTextMessage'
            : '');
      const participantJid = identity.participant;
      const remotePhone = identity.customerPhone;
      const senderName = fromMe
        ? readableSenderName(context?.instance?.instanceName, remotePhone)
        : readableSenderName(pushName, remotePhone);
      const normalizedMessageType = rawMessageType.toLowerCase();
      const sentAt =
        parseTimestamp(data.messageTimestamp) ??
        parseTimestamp(data.timestamp) ??
        parseTimestamp(asRecord(data.message)?.['timestamp']) ??
        parseTimestamp((asRecord(data.messageInfo) ?? {})['timestamp']) ??
        new Date();

      let messageType: WhatsappMessageType = WhatsappMessageType.OTHER;
      let body: string | null = null;
      let mediaUrl: string | null = null;
      let mediaMimeType: string | null = null;
      let caption: string | null = null;

      if (
        normalizedMessageType === 'conversation' ||
        normalizedMessageType === 'extendedtextmessage' ||
        normalizedMessageType === 'text'
      ) {
        messageType = WhatsappMessageType.TEXT;
        body =
          (messageObj.conversation as string | undefined) ??
          ((
            messageObj.extendedTextMessage as
              | Record<string, unknown>
              | undefined
          )?.text as string | undefined) ??
          null;
      } else if (
        normalizedMessageType === 'imagemessage' ||
        normalizedMessageType === 'image' ||
        messageObj.imageMessage
      ) {
        messageType = WhatsappMessageType.IMAGE;
        const img = asRecord(messageObj.imageMessage) ?? messageObj;
        mediaMimeType = mediaMime(img, data, 'image/jpeg');
        mediaUrl = mediaUrlFromPayload(img, messageObj, data, mediaMimeType);
        caption = (img?.caption as string | undefined) ?? null;
        body = caption;
      } else if (
        normalizedMessageType === 'audiomessage' ||
        normalizedMessageType === 'pttmessage' ||
        normalizedMessageType === 'audio' ||
        normalizedMessageType === 'ptt' ||
        messageObj.audioMessage ||
        messageObj.pttMessage
      ) {
        messageType = WhatsappMessageType.AUDIO;
        const audio =
          asRecord(messageObj.audioMessage) ??
          asRecord(messageObj.pttMessage) ??
          messageObj;
        mediaMimeType = mediaMime(audio, data, 'audio/ogg');
        mediaUrl = mediaUrlFromPayload(audio, messageObj, data, mediaMimeType);
      } else if (
        normalizedMessageType === 'videomessage' ||
        normalizedMessageType === 'video' ||
        messageObj.videoMessage
      ) {
        messageType = WhatsappMessageType.VIDEO;
        const vid = asRecord(messageObj.videoMessage) ?? messageObj;
        mediaMimeType = mediaMime(vid, data, 'video/mp4');
        mediaUrl = mediaUrlFromPayload(vid, messageObj, data, mediaMimeType);
        caption = (vid?.caption as string | undefined) ?? null;
        body = caption;
      } else if (
        normalizedMessageType === 'documentmessage' ||
        normalizedMessageType === 'document' ||
        messageObj.documentMessage
      ) {
        messageType = WhatsappMessageType.DOCUMENT;
        const doc = asRecord(messageObj.documentMessage) ?? messageObj;
        mediaMimeType = mediaMime(doc, data, null);
        mediaUrl = mediaUrlFromPayload(doc, messageObj, data, mediaMimeType);
        body = (doc?.fileName as string | undefined) ?? null;
      } else if (
        normalizedMessageType === 'stickermessage' ||
        normalizedMessageType === 'sticker' ||
        messageObj.stickerMessage
      ) {
        messageType = WhatsappMessageType.STICKER;
        const sticker = asRecord(messageObj.stickerMessage) ?? messageObj;
        mediaMimeType = mediaMime(sticker, data, 'image/webp');
        mediaUrl = mediaUrlFromPayload(
          sticker,
          messageObj,
          data,
          mediaMimeType,
        );
      } else if (
        normalizedMessageType === 'reactionmessage' ||
        messageObj.reactionMessage
      ) {
        messageType = WhatsappMessageType.TEXT;
        const reaction = asRecord(messageObj.reactionMessage) ?? messageObj;
        const reactionText = asString(reaction?.text);
        body = reactionText
          ? `Reacción: ${reactionText}`
          : 'Reaccionó a un mensaje';
      } else if (
        normalizedMessageType === 'protocolmessage' ||
        messageObj.protocolMessage
      ) {
        messageType = WhatsappMessageType.OTHER;
        body = 'Actualización de WhatsApp';
      } else if (
        normalizedMessageType === 'senderkeydistributionmessage' ||
        messageObj.senderKeyDistributionMessage
      ) {
        messageType = WhatsappMessageType.OTHER;
        body = 'Mensaje de sistema WhatsApp';
      } else {
        const text =
          asString(messageObj.conversation) ??
          asString(asRecord(messageObj.extendedTextMessage)?.text) ??
          asString(data.text) ??
          asString(data.body) ??
          asString(data.messageText) ??
          null;
        if (text) {
          messageType = WhatsappMessageType.TEXT;
          body = text;
        } else {
          body = 'Mensaje técnico de WhatsApp';
        }
      }

      return {
        evolutionId,
        externalMessageId: evolutionId,
        instanceName,
        eventName,
        remoteJid,
        remotePhone,
        fromMe,
        messageType,
        body,
        mediaUrl,
        mediaMimeType,
        caption,
        senderName,
        sentAt,
        rawPayload: payload,
      };
    } catch (err) {
      console.error('[WhatsappInbox] parseEvolutionPayload error:', err);
      return null;
    }
  }

  // ─── Save incoming/outgoing message to DB ──────────────────────────────

  async saveMessage(
    instanceId: string,
    parsed: ParsedWhatsappMessage,
    options?: { realtimeStartedAt?: number },
  ) {
    const hasMediaColumns = await this.hasWhatsappMediaColumns();
    const messageSelect = hasMediaColumns
      ? {
          ...this.whatsappMessageBaseSelect(),
          mediaStorageKey: true,
          mediaFileSize: true,
          originalFileName: true,
          playableStorageKey: true,
          playableMimeType: true,
          mediaStatus: true,
          mediaError: true,
        }
      : this.whatsappMessageBaseSelect();
    const direction = parsed.fromMe
      ? WhatsappMessageDirection.OUTGOING
      : WhatsappMessageDirection.INCOMING;

    const normalizedIdentity = normalizeWhatsappIdentity(parsed.remoteJid);
    let normalizedJid = normalizedIdentity.normalizedJid ?? parsed.remoteJid;
    let remotePhone =
      parsed.remotePhone ??
      normalizedIdentity.normalizedPhone ??
      phoneFromIdentifier(parsed.remoteJid);
    const aliasPhone = await this.resolveKnownCustomerPhoneAlias(
      instanceId,
      parsed.rawPayload,
      remotePhone,
    );
    if (aliasPhone) {
      remotePhone = aliasPhone;
      normalizedJid = `${aliasPhone}@s.whatsapp.net`;
    }
    const remoteName =
      direction === WhatsappMessageDirection.INCOMING
        ? readableSenderName(parsed.senderName, remotePhone)
        : remotePhone;

    const existingConversation = await findExistingWhatsappConversation(
      this.prisma,
      instanceId,
      normalizedJid,
      remotePhone,
    );

    const wasMerged = existingConversation?.merged ?? false;

    const conversation = existingConversation
      ? await this.prisma.whatsappConversation.update({
          where: { id: existingConversation.conversation.id },
          data: {
            lastMessageAt: parsed.sentAt,
            remoteJid: normalizedJid,
            ...(remotePhone ? { remotePhone } : {}),
            ...(direction === WhatsappMessageDirection.INCOMING && remoteName
              ? { remoteName }
              : {}),
            ...(direction === WhatsappMessageDirection.INCOMING
              ? { unreadCount: { increment: 1 } }
              : {}),
          },
        })
      : await this.prisma.whatsappConversation.create({
          data: {
            instanceId,
            remoteJid: normalizedJid,
            remotePhone,
            remoteName,
            lastMessageAt: parsed.sentAt,
            unreadCount:
              direction === WhatsappMessageDirection.INCOMING ? 1 : 0,
          },
        });
    await this.mergePreviousRemoteJidConversation(
      instanceId,
      conversation.id,
      parsed.rawPayload,
      remotePhone,
    );
    void this.invalidateWhatsappInboxCache(instanceId, conversation.id);

    // Skip duplicate Evolution IDs
    if (parsed.evolutionId) {
      const existing = await this.prisma.whatsappMessage.findUnique({
        where: { evolutionId: parsed.evolutionId },
        select: messageSelect,
      });
      if (existing) {
        const existingWithMedia = existing as typeof existing & {
          mediaStorageKey?: string | null;
        };
        const hasStoredMedia = !!existingWithMedia.mediaStorageKey;
        const updatedExisting = await this.prisma.whatsappMessage.update({
          where: { id: existing.id },
          data: {
            rawPayload: parsed.rawPayload as object,
            ...(hasStoredMedia
              ? {
                  mediaUrl: this.buildStoredMediaUrl({
                    messageId: existing.id,
                    storageKey: existingWithMedia.mediaStorageKey,
                    mimeType:
                      'mediaMimeType' in existingWithMedia
                        ? (existingWithMedia.mediaMimeType as string | null)
                        : null,
                    fileSize:
                      'mediaFileSize' in existingWithMedia
                        ? (existingWithMedia.mediaFileSize as number | null)
                        : null,
                  }),
                  mediaStatus: 'ready',
                }
              : {
                  ...(parsed.mediaUrl ? { mediaUrl: parsed.mediaUrl } : {}),
                  ...(parsed.mediaMimeType
                    ? { mediaMimeType: parsed.mediaMimeType }
                    : {}),
                }),
            caption: parsed.caption,
            body: parsed.body,
          },
          select: messageSelect,
        });
        const readyExisting = updatedExisting;
        if (hasMediaColumns) {
          this.materializeMessageMediaInBackground({
            message: updatedExisting,
            instanceId,
            instanceName: parsed.instanceName ?? '',
            conversation,
          });
        }
        this.logRealtimeTiming('[WhatsAppRealtime][MessageSaved]', options?.realtimeStartedAt, {
          messageId: readyExisting.id,
          conversationId: conversation.id,
          duplicate: true,
        });
        this.emitWhatsappMessageRealtime({
          instanceId,
          conversation,
          message: readyExisting as typeof readyExisting & {
            mediaStorageKey?: string | null;
            mediaFileSize?: number | null;
            mediaStatus?: string | null;
            mediaError?: string | null;
            originalFileName?: string | null;
          },
          realtimeStartedAt: options?.realtimeStartedAt,
        });
        return {
          conversation,
          message: readyExisting,
          duplicate: true,
          action: wasMerged ? 'merged' : 'duplicate',
        };
      }

      // For outgoing messages: if a local optimistic record exists (null evolutionId,
      // same body, sent within the last 90 seconds), update it instead of creating a duplicate.
      if (direction === WhatsappMessageDirection.OUTGOING) {
        const since = new Date(Date.now() - 90_000);
        const optimistic = await this.prisma.whatsappMessage.findFirst({
          where: {
            conversationId: conversation.id,
            direction: WhatsappMessageDirection.OUTGOING,
            evolutionId: null,
            sentAt: { gte: since },
            body: parsed.body,
          },
          orderBy: { sentAt: 'desc' },
          select: messageSelect,
        });
        if (optimistic) {
          const updated = await this.prisma.whatsappMessage.update({
            where: { id: optimistic.id },
            data: {
              evolutionId: parsed.evolutionId,
              mediaUrl: parsed.mediaUrl ?? optimistic.mediaUrl,
              mediaMimeType: parsed.mediaMimeType ?? optimistic.mediaMimeType,
            },
            select: messageSelect,
          });
          const readyUpdated = updated;
          if (hasMediaColumns) {
            this.materializeMessageMediaInBackground({
              message: updated,
              instanceId,
              instanceName: parsed.instanceName ?? '',
              conversation,
            });
          }
          this.logRealtimeTiming('[WhatsAppRealtime][MessageSaved]', options?.realtimeStartedAt, {
            messageId: readyUpdated.id,
            conversationId: conversation.id,
            duplicate: false,
          });
          this.emitWhatsappMessageRealtime({
            instanceId,
            conversation,
            message: readyUpdated as typeof readyUpdated & {
              mediaStorageKey?: string | null;
              mediaFileSize?: number | null;
              mediaStatus?: string | null;
              mediaError?: string | null;
              originalFileName?: string | null;
            },
            realtimeStartedAt: options?.realtimeStartedAt,
          });
          return {
            conversation,
            message: readyUpdated,
            duplicate: false,
            action: wasMerged ? 'merged' : 'saved',
          };
        }
      }
    }

    // Fallback idempotency for events without message id: prevent duplicates within the same second.
    if (!parsed.evolutionId) {
      const dupeByFingerprint = await this.prisma.whatsappMessage.findFirst({
        where: {
          conversationId: conversation.id,
          direction,
          body: parsed.body,
          messageType: parsed.messageType,
          sentAt: parsed.sentAt,
        },
        orderBy: { createdAt: 'desc' },
        select: messageSelect,
      });
      if (dupeByFingerprint) {
        return {
          conversation,
          message: dupeByFingerprint,
          duplicate: true,
          action: wasMerged ? 'merged' : 'duplicate',
        };
      }
    }

    const createdMessage = await this.prisma.whatsappMessage.create({
      data: {
        conversationId: conversation.id,
        evolutionId: parsed.evolutionId || null,
        direction,
        messageType: parsed.messageType,
        body: parsed.body,
        mediaUrl: parsed.mediaUrl,
        mediaMimeType: parsed.mediaMimeType,
        ...(hasMediaColumns && parsed.messageType !== WhatsappMessageType.TEXT
          ? { mediaStatus: 'pending' }
          : {}),
        caption: parsed.caption,
        senderName: parsed.senderName,
        sentAt: parsed.sentAt,
        rawPayload: parsed.rawPayload as object,
      },
      select: messageSelect,
    });
    const message = createdMessage;

    const messageWithOptionalMedia = message as typeof message & {
      mediaStorageKey?: string | null;
      mediaFileSize?: number | null;
      mediaStatus?: string | null;
      mediaError?: string | null;
      originalFileName?: string | null;
    };

    this.logRealtimeTiming('[WhatsAppRealtime][MessageSaved]', options?.realtimeStartedAt, {
      messageId: messageWithOptionalMedia.id,
      conversationId: conversation.id,
      duplicate: false,
    });
    this.emitWhatsappMessageRealtime({
      instanceId,
      conversation,
      message: messageWithOptionalMedia,
      realtimeStartedAt: options?.realtimeStartedAt,
    });

    if (hasMediaColumns) {
      this.materializeMessageMediaInBackground({
        message: createdMessage,
        instanceId,
        instanceName: parsed.instanceName ?? '',
        conversation,
      });
    }

    return {
      conversation,
      message,
      duplicate: false,
      action: wasMerged ? 'merged' : 'saved',
    };
  }

  // ─── Query conversations for an instance ──────────────────────────────

  async getConversations(instanceId: string, limit = 50, updatedAfter?: Date) {
    console.log('[WhatsappInbox][LoadChats]', { instanceId, limit });
    const canUseCache = !updatedAfter || Number.isNaN(updatedAfter.getTime());
    const cacheKey = this.conversationsCacheKey(instanceId, limit);
    if (canUseCache) {
      const cached = await this.redis.get<unknown[]>(cacheKey);
      if (cached) return cached;
    }

    let avatarByConversationKey = await this.loadAvatarCache(instanceId);
    if (avatarByConversationKey.size === 0) {
      avatarByConversationKey = await this.refreshAvatarCacheFromEvolution(
        instanceId,
        avatarByConversationKey,
      );
    } else {
      void this.refreshAvatarCacheFromEvolution(instanceId, avatarByConversationKey);
    }

    try {
      const conversations = await this.prisma.whatsappConversation.findMany({
        where: {
          instanceId,
          NOT: [{ remoteJid: { contains: '@g.us' } }],
          ...(updatedAfter && !Number.isNaN(updatedAfter.getTime())
            ? {
                OR: [
                  { updatedAt: { gt: updatedAfter } },
                  { lastMessageAt: { gt: updatedAfter } },
                ],
              }
            : {}),
        },
        orderBy: [{ lastMessageAt: 'desc' }, { updatedAt: 'desc' }],
        take: limit,
        include: {
          _count: { select: { messages: true } },
          messages: {
            orderBy: { sentAt: 'desc' },
            take: 1,
            select: {
              id: true,
              direction: true,
              messageType: true,
              body: true,
              caption: true,
              sentAt: true,
            },
          },
        },
      });
      const response = conversations.map((conversation) => {
        const normalized = this.normalizeConversationForResponse(conversation);
        const avatarUrl =
          conversationIdentityKeys(normalized.remoteJid, normalized.remotePhone)
            .map((key) => avatarByConversationKey.get(key) ?? null)
            .find((value) => value != null && value.trim().length > 0) ?? null;
        return {
          ...normalized,
          messageCount:
            '_count' in conversation
              ? (conversation._count as { messages?: number }).messages ?? 0
              : 0,
          remoteAvatarUrl: avatarUrl,
        };
      });
      if (canUseCache) {
        void this.redis.set(cacheKey, response, 20);
      }
      return response;
    } catch (error) {
      console.error('[WhatsappInbox][LoadChats]', {
        instanceId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }

  // ─── Query messages for a conversation ───────────────────────────────

  async syncRecentChatsFromEvolution(
    instanceId: string,
  ): Promise<{ synced: number; avatarByConversationKey: Map<string, string> }> {
    const instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { id: instanceId },
      select: { id: true, instanceName: true, phoneNumber: true },
    });
    if (!instance) {
      return { synced: 0, avatarByConversationKey: new Map<string, string>() };
    }

    const raw = await this.whatsappService.findChats(instance.instanceName, 40);
    const chats = Array.isArray(raw)
      ? raw
      : collectEvolutionMessageRecords(raw);
    let synced = 0;
    const avatarByConversationKey = new Map<string, string>();

    for (const chat of chats) {
      const chatRecord = asRecord(chat);
      if (!chatRecord) continue;
      const lastMessage = asRecord(chatRecord.lastMessage);
      if (!lastMessage) continue;
      const chatRemoteJid = asString(chatRecord.remoteJid);
      const avatarUrl = extractChatAvatarUrl(chatRecord);
      if (avatarUrl) {
        for (const key of conversationIdentityKeys(
          chatRemoteJid,
          chatRecord.remotePhone,
        )) {
          avatarByConversationKey.set(key, avatarUrl);
        }
      }
      const payload = {
        data: {
          ...lastMessage,
          pushName:
            asString(lastMessage.pushName) ??
            asString(chatRecord.pushName) ??
            null,
          key: {
            ...(asRecord(lastMessage.key) ?? {}),
            remoteJid:
              asString(asRecord(lastMessage.key)?.remoteJid) ?? chatRemoteJid,
          },
        },
      };
      const parsed = this.parseEvolutionPayload(payload, {
        instanceName: instance.instanceName,
        instance,
        eventName: 'CHAT_RECENT_SYNC',
      });
      if (!parsed) continue;
      const result = await this.saveMessage(instance.id, parsed);
      if (!result.duplicate) synced++;
    }

    return { synced, avatarByConversationKey };
  }

  private async resolveKnownCustomerPhoneAlias(
    instanceId: string,
    rawPayload: unknown,
    currentPhone: string | null,
  ): Promise<string | null> {
    const remoteJid = payloadKeyRemoteJid(rawPayload);
    if (!remoteJid?.toLowerCase().endsWith('@lid')) return null;

    const rows = await this.prisma.$queryRaw<
      Array<{ remote_phone: string | null }>
    >`
      SELECT c.remote_phone
      FROM whatsapp_messages m
      JOIN whatsapp_conversations c ON c.id = m.conversation_id
      WHERE c.instance_id = ${instanceId}::uuid
        AND c.remote_phone IS NOT NULL
        AND (
          m.raw_payload #>> '{data,key,previousRemoteJid}' = ${remoteJid}
          OR m.raw_payload #>> '{data,key,remoteJid}' = ${remoteJid}
        )
        AND c.remote_phone <> ${currentPhone ?? ''}
      ORDER BY m.sent_at DESC
      LIMIT 1
    `;

    const alias = normalizeWhatsappPhone(rows[0]?.remote_phone);
    return alias && alias !== currentPhone ? alias : null;
  }

  private async mergePreviousRemoteJidConversation(
    instanceId: string,
    keepConversationId: string,
    rawPayload: unknown,
    remotePhone: string | null,
  ) {
    const previousRemoteJid = payloadPreviousRemoteJid(rawPayload);
    const previousPhone = normalizeWhatsappPhone(previousRemoteJid);
    if (!previousRemoteJid?.toLowerCase().endsWith('@lid') || !previousPhone) {
      return;
    }
    if (remotePhone && previousPhone === remotePhone) return;

    const duplicate = await this.prisma.whatsappConversation.findFirst({
      where: {
        instanceId,
        remotePhone: previousPhone,
        id: { not: keepConversationId },
      },
      select: { id: true },
    });
    if (!duplicate) return;

    await this.prisma.whatsappMessage.updateMany({
      where: { conversationId: duplicate.id },
      data: { conversationId: keepConversationId },
    });
    await this.prisma.whatsappConversation.delete({
      where: { id: duplicate.id },
    });
    console.log('[WA-INBOX][MERGED_ALIAS]', {
      instanceId,
      previousRemoteJid,
      previousPhone,
      remotePhone,
      keepConversationId,
      duplicateConversationId: duplicate.id,
    });
  }

  async getMessages(
    conversationId: string,
    limit = 50,
    before?: Date,
    after?: Date,
  ) {
    console.log('[WhatsappInbox][LoadMessages]', {
      conversationId,
      limit,
      before: before?.toISOString() ?? null,
      after: after?.toISOString() ?? null,
    });
    if (!before && !after) {
      void this.syncConversationFromEvolution(conversationId).catch(
        (error) => {
          console.warn(
            `[WhatsappInbox] No se pudo sincronizar conversacion ${conversationId}: ${
              error instanceof Error ? error.message : String(error)
            }`,
          );
        },
      );
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      include: { instance: { select: { id: true, instanceName: true, phoneNumber: true } } },
    });

    const hasMediaColumns = await this.hasWhatsappMediaColumns();
    const select = hasMediaColumns
      ? {
          ...this.whatsappMessageBaseSelect(),
          mediaStorageKey: true,
          mediaFileSize: true,
          originalFileName: true,
          playableStorageKey: true,
          playableMimeType: true,
          mediaStatus: true,
          mediaError: true,
        }
      : this.whatsappMessageBaseSelect();

    try {
      const canUseCache = !before && !after;
      const cacheKey = this.messagesCacheKey(conversationId, limit);
      if (canUseCache) {
        const cached = await this.redis.get<unknown[]>(cacheKey);
        if (cached) return cached;
      }
      const messages = await this.prisma.whatsappMessage.findMany({
        where: {
          conversationId,
          ...(before ? { sentAt: { lt: before } } : {}),
          ...(after && !Number.isNaN(after.getTime())
            ? { sentAt: { gt: after } }
            : {}),
        },
        orderBy: { sentAt: 'desc' },
        take: limit,
        select,
      });
      const response = messages.map((message) => {
        const current = message as typeof message & {
          mediaStorageKey?: string | null;
          mediaMimeType?: string | null;
          mediaFileSize?: number | null;
          playableStorageKey?: string | null;
          playableMimeType?: string | null;
          mediaStatus?: string | null;
        };
        if (current.mediaStorageKey) {
          return {
            ...current,
            mediaUrl: this.buildStoredMediaUrl({
              messageId: current.id,
              storageKey: current.mediaStorageKey,
              mimeType: current.mediaMimeType,
              fileSize: current.mediaFileSize,
              playableStorageKey: current.playableStorageKey,
              playableMimeType: current.playableMimeType,
            }),
          };
        }

        if (conversation?.instance && hasMediaColumns) {
          this.materializeMessageMediaInBackground({
            message: current,
            instanceId: conversation.instanceId,
            instanceName: conversation.instance.instanceName,
            instance: conversation.instance,
          });
        }

        return current;
      });
      if (canUseCache) {
        void this.redis.set(cacheKey, response, 20);
      }
      return response;
    } catch (error) {
      console.error('[WhatsappInbox][LoadMessages]', {
        conversationId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }

  async syncConversationFromEvolution(conversationId: string) {
    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      include: { instance: true },
    });
    if (!conversation) return { synced: 0 };

    const raw = await this.whatsappService.findChatMessages(
      conversation.instance.instanceName,
      conversation.remoteJid,
    );
    const records = collectEvolutionMessageRecords(raw);
    let synced = 0;

    for (const record of records) {
      const parsed = this.parseEvolutionPayload(
        { data: record },
        {
          instanceName: conversation.instance.instanceName,
          instance: conversation.instance,
        },
      );
      if (!parsed) continue;
      const parsedPhone =
        parsed.remotePhone ?? phoneFromIdentifier(parsed.remoteJid);
      const conversationPhone =
        phoneFromIdentifier(conversation.remotePhone) ??
        phoneFromIdentifier(conversation.remoteJid);
      const sameConversation =
        parsed.remoteJid === conversation.remoteJid ||
        (!!parsedPhone &&
          !!conversationPhone &&
          parsedPhone === conversationPhone);
      if (!sameConversation) continue;
      const result = await this.saveMessage(conversation.instanceId, parsed);
      if (!result.duplicate) synced++;
    }

    return { synced };
  }

  // ─── Mark conversation as read ────────────────────────────────────────

  async markRead(conversationId: string) {
    const updated = await this.prisma.whatsappConversation.update({
      where: { id: conversationId },
      data: { unreadCount: 0 },
    });
    void this.invalidateWhatsappInboxCache(updated.instanceId, conversationId);
    return updated;
  }

  // ─── List users with whatsapp instances (for admin user selector) ────

  async listUsersWithInstances() {
    return this.prisma.userWhatsappInstance.findMany({
      include: {
        user: {
          select: {
            id: true,
            nombreCompleto: true,
            role: true,
            telefono: true,
          },
        },
      },
      orderBy: { createdAt: 'asc' },
    });
  }

  // ─── Get instance by userId ──────────────────────────────────────────

  async getInstanceByUserId(userId: string) {
    const instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
    });
    if (!instance) throw new NotFoundException('Instance not found for user');
    return instance;
  }

  async validateAdminComposePassword(
    actor: { id?: string; role?: string },
    password: string,
  ) {
    if (actor.role !== 'ADMIN') {
      throw new ForbiddenException(
        'Solo un administrador puede desbloquear el envio.',
      );
    }
    if (!actor.id) {
      throw new ForbiddenException('No autorizado.');
    }
    const cleaned = (password ?? '').trim();
    if (!cleaned) {
      throw new BadRequestException(
        'Debes colocar la contrasena de administrador.',
      );
    }
    const user = await this.prisma.user.findUnique({
      where: { id: actor.id },
      select: { passwordHash: true },
    });
    if (!user) throw new ForbiddenException('No autorizado.');
    const ok = await bcrypt.compare(cleaned, user.passwordHash);
    if (!ok) throw new ForbiddenException('Contrasena incorrecta.');
    return { ok: true };
  }

  // ─── Record a message sent via Evolution API (outgoing) ──────────────

  async recordOutgoingMessage(
    instanceId: string,
    remoteJid: string,
    body: string,
    evolutionId?: string,
  ) {
    const instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { id: instanceId },
      select: { instanceName: true },
    });
    const parsed: ParsedWhatsappMessage = {
      evolutionId: evolutionId ?? '',
      externalMessageId: evolutionId ?? '',
      instanceName: null,
      eventName: 'APP_SEND',
      remoteJid,
      remotePhone: phoneFromIdentifier(remoteJid),
      fromMe: true,
      messageType: WhatsappMessageType.TEXT,
      body,
      mediaUrl: null,
      mediaMimeType: null,
      caption: null,
      senderName: instance?.instanceName ?? null,
      sentAt: new Date(),
      rawPayload: null,
    };
    return this.saveMessage(instanceId, parsed);
  }

  async recordOutgoingMediaMessage(params: {
    instanceId: string;
    remoteJid: string;
    bytes: Buffer | Uint8Array;
    mediaType: OutgoingWhatsappMediaType;
    mimeType: string;
    fileName: string;
    caption?: string | null;
    evolutionId?: string | null;
    evolutionResult?: unknown;
  }) {
    const instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { id: params.instanceId },
      select: { instanceName: true },
    });
    const bytes = Buffer.from(params.bytes);
    const detected = await detectMediaType(bytes, params.mimeType);
    const mimeType = detected.mime;
    const mediaType = outgoingMediaTypeFromMime(mimeType);
    const caption = params.caption?.trim() || null;
    const fileName = ensureFilenameExtension(params.fileName, detected.ext);
    const parsed: ParsedWhatsappMessage = {
      evolutionId: params.evolutionId?.trim() ?? '',
      externalMessageId: params.evolutionId?.trim() ?? '',
      instanceName: instance?.instanceName ?? null,
      eventName: 'APP_SEND_MEDIA',
      remoteJid: params.remoteJid,
      remotePhone: phoneFromIdentifier(params.remoteJid),
      fromMe: true,
      messageType: whatsappMessageTypeFromMediaType(mediaType),
      body: caption ?? fileName,
      mediaUrl: `data:${mimeType};base64,${bytes.toString('base64')}`,
      mediaMimeType: mimeType,
      caption,
      senderName: instance?.instanceName ?? null,
      sentAt: new Date(),
      rawPayload: {
        event: 'APP_SEND_MEDIA',
        data: {
          key: {
            id: params.evolutionId ?? null,
            fromMe: true,
            remoteJid: params.remoteJid,
          },
          messageType: `${mediaType}Message`,
          message: {
            [`${mediaType}Message`]: {
              mimetype: mimeType,
              fileName,
              caption,
            },
          },
          fileName,
          mimetype: mimeType,
          caption,
          evolutionResult: params.evolutionResult ?? null,
        },
      },
    };
    return this.saveMessage(params.instanceId, parsed);
  }

  async detectOutgoingUploadMedia(params: {
    bytes: Buffer | Uint8Array;
    mimeType?: string | null;
    fileName?: string | null;
  }): Promise<{
    mimeType: string;
    mediaType: OutgoingWhatsappMediaType;
    fileName: string;
  }> {
    const bytes = Buffer.from(params.bytes);
    const detected = await detectMediaType(bytes, params.mimeType ?? null);
    return {
      mimeType: detected.mime,
      mediaType: outgoingMediaTypeFromMime(detected.mime),
      fileName: ensureFilenameExtension(
        params.fileName?.trim() || `media-${Date.now()}`,
        detected.ext,
      ),
    };
  }

  async attachEvolutionIdToMessage(
    messageId: string,
    evolutionId?: string | null,
  ) {
    const cleanId = (evolutionId ?? '').trim();
    if (!cleanId) return null;

    const existing = await this.prisma.whatsappMessage.findUnique({
      where: { evolutionId: cleanId },
      select: { id: true },
    });
    if (existing) return existing;

    return this.prisma.whatsappMessage.update({
      where: { id: messageId },
      data: { evolutionId: cleanId },
      select: { id: true },
    });
  }

  async summarizeDailyActivity(userId: string, dateIso: string) {
    const date = /^\d{4}-\d{2}-\d{2}$/.test(dateIso)
      ? dateIso
      : new Date(dateIso).toISOString().slice(0, 10);
    if (!date) throw new BadRequestException('Fecha invalida');

    const instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
      include: {
        user: { select: { id: true, nombreCompleto: true, role: true } },
      },
    });
    if (!instance) throw new NotFoundException('Instance not found for user');

    const start = new Date(`${date}T00:00:00-04:00`);
    const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);

    const messages = await this.prisma.whatsappMessage.findMany({
      where: {
        sentAt: { gte: start, lt: end },
        conversation: { instanceId: instance.id },
      },
      orderBy: { sentAt: 'asc' },
      include: {
        conversation: {
          select: {
            id: true,
            remoteJid: true,
            remotePhone: true,
            remoteName: true,
          },
        },
      },
      take: 1200,
    });

    const contacts = new Set(messages.map((m) => m.conversationId));
    const incoming = messages.filter(
      (m) => m.direction === WhatsappMessageDirection.INCOMING,
    );
    const outgoing = messages.filter(
      (m) => m.direction === WhatsappMessageDirection.OUTGOING,
    );
    const media = messages.filter(
      (m) => m.messageType !== WhatsappMessageType.TEXT,
    );

    const stats = {
      date,
      userName: instance.user?.nombreCompleto ?? instance.instanceName,
      instanceName: instance.instanceName,
      totalMessages: messages.length,
      incomingMessages: incoming.length,
      outgoingMessages: outgoing.length,
      contacts: contacts.size,
      mediaMessages: media.length,
    };

    if (messages.length === 0) {
      return {
        source: 'rules-only',
        stats,
        summary:
          'No hay mensajes registrados para este usuario en la fecha seleccionada. Verifica que el webhook de la instancia este activo y que Evolution este enviando los eventos MESSAGES_UPSERT y SEND_MESSAGE.',
        alerts: [],
        conversationAnalysis: [],
      };
    }

    const runtime = await this.getOpenAiRuntimeConfig();

    // ─── Build per-conversation map ────────────────────────────────────
    const convMap = new Map<
      string,
      {
        contact: string;
        msgs: Array<{
          time: string;
          direction: string;
          type: string;
          text: string;
          mediaUrl: string | null;
          mimeType: string | null;
        }>;
      }
    >();
    for (const m of messages) {
      const contactName =
        readableSenderName(
          m.conversation.remoteName,
          m.conversation.remotePhone,
        ) ??
        m.conversation.remotePhone ??
        m.conversation.remoteJid;
      if (!convMap.has(m.conversationId)) {
        convMap.set(m.conversationId, { contact: contactName, msgs: [] });
      }
      convMap.get(m.conversationId)!.msgs.push({
        time: m.sentAt.toISOString().slice(11, 16),
        direction:
          m.direction === WhatsappMessageDirection.OUTGOING
            ? 'usuario'
            : 'cliente',
        type: m.messageType,
        text: (m.body ?? m.caption ?? '').replace(/\s+/g, ' ').trim().slice(0, 800),
        mediaUrl: m.mediaUrl,
        mimeType: m.mediaMimeType,
      });
    }

    // ─── Collect images & transcribe audio ────────────────────────────
    const imageEntries: Array<{ contact: string; url: string }> = [];
    const audioTranscriptions: Array<{ contact: string; text: string }> = [];

    if (runtime.apiKey) {
      for (const [, conv] of convMap) {
        for (const msg of conv.msgs) {
          if (
            msg.type === WhatsappMessageType.IMAGE &&
            msg.mediaUrl?.startsWith('data:image')
          ) {
            if (imageEntries.length < 5) {
              imageEntries.push({ contact: conv.contact, url: msg.mediaUrl });
            }
          }
          if (
            (msg.type === WhatsappMessageType.AUDIO ||
              msg.type === ('PTT' as WhatsappMessageType)) &&
            msg.mediaUrl?.startsWith('data:audio')
          ) {
            if (audioTranscriptions.length < 4) {
              const transcription = await this.transcribeAudioBase64(
                msg.mediaUrl,
                msg.mimeType ?? 'audio/ogg',
                runtime.apiKey,
              ).catch(() => null);
              if (transcription) {
                audioTranscriptions.push({
                  contact: conv.contact,
                  text: transcription,
                });
                // Replace the placeholder text in the transcript entry
                msg.text = `[Audio transcrito: ${transcription.slice(0, 500)}]`;
              }
            }
          }
        }
      }
    }

    // ─── Build flat transcript for AI ─────────────────────────────────
    const transcript = messages.map((m) => ({
      time: m.sentAt.toISOString().slice(11, 16),
      direction:
        m.direction === WhatsappMessageDirection.OUTGOING
          ? 'usuario'
          : 'cliente',
      contact:
        readableSenderName(
          m.conversation.remoteName,
          m.conversation.remotePhone,
        ) ??
        m.conversation.remotePhone ??
        m.conversation.remoteJid,
      type: m.messageType,
      text: convMap
        .get(m.conversationId)
        ?.msgs.find((x) => x.time === m.sentAt.toISOString().slice(11, 16) && x.direction === (m.direction === WhatsappMessageDirection.OUTGOING ? 'usuario' : 'cliente'))
        ?.text ??
        (m.body ?? m.caption ?? '').replace(/\s+/g, ' ').trim().slice(0, 800),
    }));

    if (!runtime.apiKey) {
      return {
        source: 'rules-only',
        stats,
        summary: this.buildDeterministicDailySummary(stats, transcript),
        alerts: [],
        conversationAnalysis: [],
      };
    }

    try {
      const ai = await this.withTimeout(
        this.requestDailySummaryFromOpenAi(runtime, {
          stats,
          transcript,
          images: imageEntries,
          audioTranscriptions,
          conversationIds: Array.from(convMap.entries()).map(([, v]) => ({
            contact: v.contact,
            messageCount: v.msgs.length,
            hasIncoming: v.msgs.some((x) => x.direction === 'cliente'),
            hasOutgoing: v.msgs.some((x) => x.direction === 'usuario'),
            hasMedia: v.msgs.some((x) => x.type !== WhatsappMessageType.TEXT),
          })),
        }),
        DAILY_SUMMARY_AI_TIMEOUT_MS,
        'OpenAI daily summary timed out',
      );
      return {
        source: 'openai',
        stats,
        summary:
          ai.summary || this.buildDeterministicDailySummary(stats, transcript),
        alerts: ai.alerts ?? [],
        conversationAnalysis: ai.conversationAnalysis ?? [],
      };
    } catch (error) {
      console.warn(
        `[WhatsappInbox] Daily AI summary fallback for user=${userId} date=${date}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return {
        source: 'rules-only',
        stats,
        summary: this.buildDeterministicDailySummary(stats, transcript),
        alerts: [],
        conversationAnalysis: [],
      };
    }
  }

  async analyzeCrmConversations(input: WhatsappAiAnalysisInput) {
    const range = this.resolveWhatsappAiDateRange(input.filter, input.customDate);
    const runtime = await this.getOpenAiRuntimeConfig();
    const scope = input.scope === 'conversation' ? 'conversation' : 'filter';

    const messages = await this.loadWhatsappAiMessages({
      scope,
      userId: input.userId,
      conversationId: input.conversationId,
      start: range.start,
      end: range.end,
    });

    const fingerprint = this.buildWhatsappAiFingerprint(messages);
    const cacheKey = `${scope}:${range.key}:${input.conversationId ?? input.userId ?? 'all'}`;
    const cached = input.forceRefresh
      ? null
      : await this.findCachedWhatsappAiReport({
          scope,
          conversationId: scope === 'conversation' ? input.conversationId : null,
          dateRangeKey: cacheKey,
          fingerprint,
        });
    if (cached) return cached;

    const mediaSummaries = await this.ensureWhatsappAiMediaSummaries(
      messages,
      runtime,
    );
    const conversations = this.buildWhatsappAiConversationContext(
      messages,
      mediaSummaries,
    );
    const stats = this.buildWhatsappAiStats(conversations, range, scope);

    const report = runtime.apiKey
      ? await this.requestWhatsappAiAnalysisFromOpenAi(runtime, {
          range,
          scope,
          stats,
          conversations,
        }).catch(() => this.buildDeterministicWhatsappAiReport(conversations, stats))
      : this.buildDeterministicWhatsappAiReport(conversations, stats);

    const response = this.normalizeWhatsappAiResponse({
      source: runtime.apiKey ? 'openai' : 'rules-only',
      cached: false,
      range,
      stats,
      report,
      conversations,
      mediaSummaries,
    });

    const analysisReportId = await this.saveWhatsappAiReport({
      scope,
      conversationId: scope === 'conversation' ? input.conversationId : null,
      dateRangeKey: cacheKey,
      startAt: range.start,
      endAt: range.end,
      fingerprint,
      report: response,
      generatedBy: input.generatedBy ?? null,
    }).catch(() => null);

    return { ...response, analysisReportId };
  }

  async askWhatsappAiAnalysis(input: WhatsappAiAskInput) {
    const question = input.question.trim();
    if (!question) throw new BadRequestException('La pregunta es requerida.');

    type Row = { id: string; report: Prisma.JsonValue; generated_at: Date };
    const rows = input.generatedBy
      ? await this.prisma.$queryRaw<Row[]>`
          SELECT id, report, generated_at
          FROM whatsapp_ai_analysis_reports
          WHERE id = ${input.analysisReportId}::uuid
            AND generated_by = ${input.generatedBy}::uuid
          LIMIT 1
        `.catch(() => [] as Row[])
      : await this.prisma.$queryRaw<Row[]>`
          SELECT id, report, generated_at
          FROM whatsapp_ai_analysis_reports
          WHERE id = ${input.analysisReportId}::uuid
          LIMIT 1
        `.catch(() => [] as Row[]);
    const row = rows[0];
    if (!row || !row.report || typeof row.report !== 'object' || Array.isArray(row.report)) {
      throw new NotFoundException('Reporte de IA no encontrado.');
    }

    const report = row.report as Record<string, unknown>;
    const scopedReport = this.scopeWhatsappAiReportForQuestion(
      report,
      input.conversationId,
    );
    const runtime = await this.getOpenAiRuntimeConfig();
    const answer = runtime.apiKey
      ? await this.requestWhatsappAiReportAnswer(runtime, {
          question,
          report: scopedReport,
        }).catch(() => this.buildDeterministicWhatsappAiAnswer(question, scopedReport))
      : this.buildDeterministicWhatsappAiAnswer(question, scopedReport);

    return {
      source: runtime.apiKey ? 'openai' : 'rules-only',
      analysisReportId: input.analysisReportId,
      question,
      answer,
      generatedAt: new Date().toISOString(),
    };
  }

  private scopeWhatsappAiReportForQuestion(
    report: Record<string, unknown>,
    conversationId?: string,
  ) {
    if (!conversationId) return report;
    const clone = JSON.parse(JSON.stringify(report)) as Record<string, unknown>;
    const analyzed = Array.isArray(clone.analyzedConversations)
      ? clone.analyzedConversations.filter((item: any) => item?.conversationId === conversationId)
      : [];
    clone.analyzedConversations = analyzed;
    const rawReport = clone.report as Record<string, unknown> | undefined;
    if (rawReport) {
      if (Array.isArray(rawReport.conversacionesProblematicas)) {
        rawReport.conversacionesProblematicas = rawReport.conversacionesProblematicas.filter(
          (item: any) => item?.conversationId === conversationId,
        );
      }
      if (Array.isArray(rawReport.responsabilidadDetectada)) {
        rawReport.responsabilidadDetectada = rawReport.responsabilidadDetectada.filter(
          (item: any) => item?.conversationId === conversationId,
        );
      }
    }
    return clone;
  }

  private async requestWhatsappAiReportAnswer(
    runtime: { apiKey: string; model: string; companyName: string },
    payload: { question: string; report: Record<string, unknown> },
  ) {
    const candidates = [runtime.model, 'gpt-5', 'gpt-4.1', 'gpt-4o', 'gpt-4o-mini'].filter(
      (value, index, list) => value && list.indexOf(value) === index,
    );
    const systemPrompt =
      `Responde preguntas sobre un reporte de CRM WhatsApp de ${runtime.companyName}. ` +
      'Debes basarte SOLO en el reporte, los mensajes analizados, resumenes de media y metadatos incluidos. ' +
      'fromMe=true/direction=outbound/senderRole=vendedor significa empresa o vendedor. fromMe=false/direction=inbound/senderRole=cliente significa cliente externo. Nunca inviertas roles. ' +
      'Si el reporte no contiene evidencia suficiente, responde exactamente: No hay evidencia suficiente en el reporte para afirmar eso. ' +
      'No reveles datos sensibles completos; resume evidencia.';

    for (const model of candidates) {
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 12000);
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          signal: controller.signal,
          headers: {
            Authorization: `Bearer ${runtime.apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model,
            temperature: 0.05,
            max_tokens: 900,
            messages: [
              { role: 'system', content: systemPrompt },
              {
                role: 'user',
                content: `Pregunta: ${payload.question}\n\nReporte/contexto JSON:\n${JSON.stringify(payload.report).slice(0, 55000)}`,
              },
            ],
          }),
        }).finally(() => clearTimeout(timeout));
        if (!response.ok) continue;
        const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> };
        const content = data.choices?.[0]?.message?.content?.trim();
        if (content) return content;
      } catch {
        continue;
      }
    }
    return this.buildDeterministicWhatsappAiAnswer(payload.question, payload.report);
  }

  private buildDeterministicWhatsappAiAnswer(
    question: string,
    report: Record<string, unknown>,
  ) {
    const text = question.toLowerCase();
    const analyzed = Array.isArray(report.analyzedConversations)
      ? (report.analyzedConversations as Array<any>)
      : [];
    const responsibilities = ((report.report as any)?.responsabilidadDetectada ?? report.responsabilidadDetectada ?? []) as Array<any>;
    const problems = ((report.report as any)?.conversacionesProblematicas ?? []) as Array<any>;
    const responsibility = responsibilities[0] ?? null;

    if (text.includes('ultimo') || text.includes('último') || text.includes('escribio') || text.includes('escribió')) {
      if (!responsibility) return 'No hay evidencia suficiente en el reporte para afirmar eso.';
      return [
        `El ultimo mensaje importante registrado fue de: ${responsibility.ultimoMensajeDe ?? 'desconocido'}.`,
        `Cliente: ${responsibility.cliente ?? 'No identificado'}.`,
        `Atendido por: ${responsibility.atendidoPor ?? 'No identificado'}.`,
        `Evidencia: ${responsibility.evidencia ?? 'No hay evidencia suficiente'}.`,
      ].join('\n');
    }

    if (text.includes('quien') || text.includes('quién') || text.includes('respond')) {
      const evidence = responsibility;
      if (!evidence) return 'No hay evidencia suficiente en el reporte para afirmar eso.';
      return [
        `Responsabilidad detectada: ${evidence.estado ?? 'No hay evidencia suficiente'}.`,
        `Cliente: ${evidence.cliente ?? 'No identificado'}.`,
        `Atendido por: ${evidence.atendidoPor ?? 'No identificado'}.`,
        `Ultimo mensaje de: ${evidence.ultimoMensajeDe ?? 'desconocido'}.`,
        `Evidencia: ${evidence.evidencia ?? 'No hay evidencia suficiente'}.`,
      ].join('\n');
    }

    if (text.includes('vendedor') || text.includes('atend')) {
      const conv = analyzed[0];
      if (!conv) return 'No hay evidencia suficiente en el reporte para afirmar eso.';
      return `Atendido por: ${conv.atendidoPor?.usuario ?? 'Usuario no identificado'} / instancia ${conv.atendidoPor?.instancia ?? 'No identificada'}.`;
    }

    if (text.includes('fraude')) {
      const fraud = problems.find((item) => `${item.clasificacion ?? ''} ${item.motivo ?? ''}`.toLowerCase().includes('fraude'));
      if (!fraud) return 'No hay evidencia suficiente en el reporte para afirmar eso.';
      return `Posible fraude: ${fraud.motivo}. Evidencia: ${fraud.evidencia}. Acción recomendada: ${fraud.accionRecomendada}.`;
    }

    if (text.includes('evidencia') || text.includes('problema') || text.includes('por que') || text.includes('por qué')) {
      if (responsibility) {
        return `Evidencia disponible: ${responsibility.evidencia ?? 'No hay evidencia suficiente'}. Responsabilidad detectada: ${responsibility.estado ?? 'No hay evidencia suficiente'}.`;
      }
      const firstProblem = problems[0];
      if (firstProblem) return `Evidencia: ${firstProblem.evidencia}. Motivo: ${firstProblem.motivo}.`;
      return 'No hay evidencia suficiente en el reporte para afirmar eso.';
    }

    if (text.includes('hacer') || text.includes('ahora') || text.includes('accion') || text.includes('acción') || text.includes('siguiente')) {
      if (responsibility?.accion) return `Accion recomendada: ${responsibility.accion}`;
      const firstProblem = problems[0];
      if (firstProblem?.accionRecomendada) return `Accion recomendada: ${firstProblem.accionRecomendada}`;
      return 'No hay evidencia suficiente en el reporte para afirmar eso.';
    }

    if (text.includes('correctamente') || text.includes('correcto') || text.includes('atencion') || text.includes('atención')) {
      if (!responsibility) return 'No hay evidencia suficiente en el reporte para afirmar eso.';
      const estado = `${responsibility.estado ?? ''}`;
      if (estado === 'Vendedor no respondio' || estado === 'Requiere seguimiento del vendedor') {
        return `No se puede afirmar que fue atendido correctamente. Responsabilidad detectada: ${estado}. Evidencia: ${responsibility.evidencia ?? 'No hay evidencia suficiente'}.`;
      }
      return `No hay evidencia suficiente de mala atencion en este reporte. Responsabilidad detectada: ${estado || 'No hay evidencia suficiente'}. Evidencia: ${responsibility.evidencia ?? 'No hay evidencia suficiente'}.`;
    }

    const firstProblem = problems[0];
    if (firstProblem) {
      return `Motivo: ${firstProblem.motivo}. Evidencia: ${firstProblem.evidencia}. Acción recomendada: ${firstProblem.accionRecomendada}.`;
    }
    return 'No hay evidencia suficiente en el reporte para afirmar eso.';
  }

  private resolveWhatsappAiDateRange(filter: WhatsappAiFilter, customDate?: string) {
    const now = new Date();
    const localDay = (value: Date) => value.toLocaleDateString('en-CA', {
      timeZone: 'America/Santo_Domingo',
    });
    const startOfLocalDay = (day: string) => new Date(`${day}T00:00:00-04:00`);
    const todayStart = startOfLocalDay(localDay(now));
    let start = todayStart;
    let end = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
    let label = 'Hoy';

    if (filter === 'yesterday') {
      start = new Date(todayStart.getTime() - 24 * 60 * 60 * 1000);
      end = todayStart;
      label = 'Ayer';
    } else if (filter === 'last7Days') {
      start = new Date(todayStart.getTime() - 6 * 24 * 60 * 60 * 1000);
      end = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
      label = 'Ultimos 7 dias';
    } else if (filter === 'thisMonth') {
      const parts = localDay(now).split('-').map((x) => Number(x));
      start = startOfLocalDay(`${parts[0]}-${String(parts[1]).padStart(2, '0')}-01`);
      end = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
      label = 'Este mes';
    } else if (filter === 'custom') {
      const day = /^\d{4}-\d{2}-\d{2}$/.test(customDate ?? '')
        ? customDate!
        : customDate
          ? new Date(customDate).toISOString().slice(0, 10)
          : localDay(now);
      start = startOfLocalDay(day);
      end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
      label = `Fecha personalizada ${day}`;
    }

    return {
      filter,
      label,
      start,
      end,
      key: `${filter}:${start.toISOString()}:${end.toISOString()}`,
      startIso: start.toISOString(),
      endIso: end.toISOString(),
    };
  }

  private async loadWhatsappAiMessages(input: {
    scope: WhatsappAiScope;
    userId?: string;
    conversationId?: string;
    start: Date;
    end: Date;
  }) {
    if (input.scope === 'conversation') {
      if (!input.conversationId) {
        throw new BadRequestException('conversationId es requerido.');
      }
      return this.prisma.whatsappMessage.findMany({
        where: {
          conversationId: input.conversationId,
          sentAt: { gte: input.start, lt: input.end },
        },
        orderBy: { sentAt: 'asc' },
        include: {
          conversation: {
            include: {
              instance: {
                include: {
                  user: { select: { id: true, nombreCompleto: true, role: true } },
                },
              },
            },
          },
        },
        take: 1500,
      });
    }

    if (!input.userId) throw new BadRequestException('userId es requerido.');
    const instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId: input.userId },
      select: { id: true },
    });
    if (!instance) throw new NotFoundException('Instance not found for user');

    return this.prisma.whatsappMessage.findMany({
      where: {
        sentAt: { gte: input.start, lt: input.end },
        conversation: { instanceId: instance.id },
      },
      orderBy: { sentAt: 'asc' },
      include: {
        conversation: {
          include: {
            instance: {
              include: {
                user: { select: { id: true, nombreCompleto: true, role: true } },
              },
            },
          },
        },
      },
      take: 1500,
    });
  }

  private buildWhatsappAiFingerprint(messages: Array<{ id: string; sentAt: Date; messageType: WhatsappMessageType; mediaStatus: string | null; body: string | null; caption: string | null }>) {
    const source = messages
      .map((m) => [m.id, m.sentAt.toISOString(), m.messageType, m.mediaStatus ?? '', (m.body ?? '').length, (m.caption ?? '').length].join('|'))
      .join('\n');
    return createHash('sha256').update(source).digest('hex');
  }

  private async findCachedWhatsappAiReport(input: {
    scope: WhatsappAiScope;
    conversationId?: string | null;
    dateRangeKey: string;
    fingerprint: string;
  }) {
    type Row = { id: string; report: Prisma.JsonValue; generated_at: Date };
    const rows = await this.prisma.$queryRaw<Row[]>`
      SELECT id, report, generated_at
      FROM whatsapp_ai_analysis_reports
      WHERE scope = ${input.scope}
        AND date_range_key = ${input.dateRangeKey}
        AND message_fingerprint = ${input.fingerprint}
        AND (
          (${input.conversationId}::uuid IS NULL AND conversation_id IS NULL)
          OR conversation_id = ${input.conversationId}::uuid
        )
      ORDER BY generated_at DESC
      LIMIT 1
    `.catch(() => [] as Row[]);
    const report = rows[0]?.report;
    if (!report || typeof report !== 'object' || Array.isArray(report)) return null;
    return { ...(report as Record<string, unknown>), cached: true, analysisReportId: rows[0].id };
  }

  private async ensureWhatsappAiMediaSummaries(
    messages: Array<{
      id: string;
      messageType: WhatsappMessageType;
      mediaUrl: string | null;
      mediaMimeType: string | null;
      mediaStatus: string | null;
      caption: string | null;
    }>,
    runtime: { apiKey: string; model: string; companyName: string },
  ) {
    const mediaMessages = messages.filter((m) => m.messageType !== WhatsappMessageType.TEXT);
    if (mediaMessages.length === 0) return new Map<string, WhatsappAiMediaContext>();

    type Row = {
      message_id: string;
      media_type: string;
      summary: string | null;
      transcription_status: string;
      transcription_text: string | null;
    };
    const ids = mediaMessages.map((m) => m.id);
    const uuidIds = ids.map((id) => Prisma.sql`${id}::uuid`);
    const existingRows = ids.length
      ? await this.prisma.$queryRaw<Row[]>`
          SELECT message_id, media_type, summary, transcription_status, transcription_text
          FROM whatsapp_ai_media_summaries
          WHERE message_id IN (${Prisma.join(uuidIds)})
        `.catch(() => [] as Row[])
      : [];
    const summaries = new Map<string, WhatsappAiMediaContext>();
    for (const row of existingRows) {
      summaries.set(row.message_id, {
        messageId: row.message_id,
        type: row.media_type,
        mimeType: null,
        status: 'cached',
        summary: row.summary,
        transcriptionStatus: row.transcription_status,
        transcriptionText: row.transcription_text,
      });
    }

    let imageBudget = 8;
    let audioBudget = 4;
    for (const msg of mediaMessages) {
      if (summaries.has(msg.id)) continue;
      let summary: string | null = null;
      let transcriptionStatus = 'not_applicable';
      let transcriptionText: string | null = null;
      const mediaType = msg.messageType.toString().toLowerCase();

      if (msg.messageType === WhatsappMessageType.IMAGE) {
        if (runtime.apiKey && imageBudget > 0 && this.canOpenAiReadImageUrl(msg.mediaUrl)) {
          imageBudget -= 1;
          summary = await this.requestWhatsappImageSummary(runtime, msg.mediaUrl!, msg.caption).catch(() => null);
        }
        summary ??= msg.caption?.trim()
          ? `Imagen con caption: ${msg.caption.trim()}`
          : msg.mediaStatus === 'ready'
            ? 'Imagen disponible; resumen visual pendiente.'
            : 'Imagen pendiente o no disponible para analisis visual.';
      } else if (msg.messageType === WhatsappMessageType.AUDIO) {
        transcriptionStatus = 'pending';
        if (runtime.apiKey && audioBudget > 0 && msg.mediaUrl?.startsWith('data:audio')) {
          audioBudget -= 1;
          transcriptionText = await this.transcribeAudioBase64(
            msg.mediaUrl,
            msg.mediaMimeType ?? 'audio/ogg',
            runtime.apiKey,
          ).catch(() => null);
          transcriptionStatus = transcriptionText ? 'transcribed' : 'pending';
        }
        summary = transcriptionText
          ? `Audio transcrito: ${transcriptionText}`
          : 'Audio pendiente de transcripcion.';
      } else if (msg.messageType === WhatsappMessageType.VIDEO) {
        summary = msg.caption?.trim()
          ? `Video disponible con caption: ${msg.caption.trim()}`
          : 'Video disponible; analisis visual/transcripcion pendiente.';
      } else if (msg.messageType === WhatsappMessageType.DOCUMENT) {
        summary = msg.caption?.trim()
          ? `Documento adjunto con caption: ${msg.caption.trim()}`
          : 'Documento adjunto; contenido pendiente de lectura automatica.';
      } else {
        summary = 'Media no textual registrada; analisis especifico pendiente.';
      }

      const context: WhatsappAiMediaContext = {
        messageId: msg.id,
        type: mediaType,
        mimeType: msg.mediaMimeType,
        status: msg.mediaStatus ?? 'unknown',
        summary,
        transcriptionStatus,
        transcriptionText,
      };
      summaries.set(msg.id, context);
      await this.saveWhatsappAiMediaSummary(context, runtime.model).catch(() => null);
    }

    return summaries;
  }

  private canOpenAiReadImageUrl(value: string | null) {
    if (!value) return false;
    return value.startsWith('data:image') || value.startsWith('https://') || value.startsWith('http://');
  }

  private async requestWhatsappImageSummary(
    runtime: { apiKey: string; model: string; companyName: string },
    imageUrl: string,
    caption?: string | null,
  ) {
    const candidates = [runtime.model, 'gpt-4o', 'gpt-4.1', 'gpt-4o-mini'].filter(
      (value, index, list) => value && list.indexOf(value) === index,
    );
    const prompt = [
      'Analiza esta imagen de una conversacion de WhatsApp CRM.',
      'Describe solo evidencia visible. No inventes datos.',
      'Detecta si parece comprobante de pago, transferencia, factura, cedula/documento, producto danado, instalacion, reclamo visual, captura de pantalla, conversacion reenviada o posible manipulacion/fraude evidente.',
      'Si contiene datos sensibles, no transcribas numeros completos; solo indica el tipo de documento o evidencia.',
      caption?.trim() ? `Caption: ${caption.trim()}` : '',
    ].filter(Boolean).join(' ');

    for (const model of candidates) {
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 9000);
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          signal: controller.signal,
          headers: {
            Authorization: `Bearer ${runtime.apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model,
            temperature: 0.05,
            max_tokens: 350,
            messages: [
              { role: 'system', content: 'Eres auditor visual de CRM. Responde breve en espanol y sin inventar.' },
              { role: 'user', content: [
                { type: 'text', text: prompt },
                { type: 'image_url', image_url: { url: imageUrl, detail: 'low' } },
              ] },
            ],
          }),
        }).finally(() => clearTimeout(timeout));
        if (!response.ok) continue;
        const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> };
        const content = data.choices?.[0]?.message?.content?.trim();
        if (content) return content.slice(0, 1200);
      } catch {
        continue;
      }
    }
    return null;
  }

  private async saveWhatsappAiMediaSummary(context: WhatsappAiMediaContext, model: string) {
    const evidence = {
      summary: context.summary,
      mediaType: context.type,
      mimeType: context.mimeType,
      status: context.status,
    };
    await this.prisma.$executeRaw`
      INSERT INTO whatsapp_ai_media_summaries
        (message_id, media_type, summary, evidence, transcription_status, transcription_text, model)
      VALUES
        (${context.messageId}::uuid, ${context.type}, ${context.summary}, CAST(${JSON.stringify(evidence)} AS jsonb), ${context.transcriptionStatus}, ${context.transcriptionText}, ${model})
      ON CONFLICT (message_id) DO UPDATE SET
        media_type = EXCLUDED.media_type,
        summary = EXCLUDED.summary,
        evidence = EXCLUDED.evidence,
        transcription_status = EXCLUDED.transcription_status,
        transcription_text = EXCLUDED.transcription_text,
        model = EXCLUDED.model,
        updated_at = CURRENT_TIMESTAMP
    `;
  }

  private buildWhatsappAiConversationContext(
    messages: Array<any>,
    mediaSummaries: Map<string, WhatsappAiMediaContext>,
  ): WhatsappAiConversationContext[] {
    const grouped = new Map<string, Array<any>>();
    for (const message of messages) {
      const list = grouped.get(message.conversationId) ?? [];
      list.push(message);
      grouped.set(message.conversationId, list);
    }

    return Array.from(grouped.entries()).map(([conversationId, rawItems]) => {
      const items = [...rawItems].sort(
        (a, b) => a.sentAt.getTime() - b.sentAt.getTime(),
      );
      const first = items[0];
      const conv = first.conversation;
      const responseTimes: number[] = [];
      let pendingIncomingAt: Date | null = null;
      let pendingIncomingMessages = 0;
      for (const item of items) {
        if (item.direction === WhatsappMessageDirection.INCOMING) {
          pendingIncomingAt ??= item.sentAt;
          pendingIncomingMessages += 1;
        } else if (pendingIncomingAt) {
          responseTimes.push(Math.max(0, item.sentAt.getTime() - pendingIncomingAt.getTime()) / 60000);
          pendingIncomingAt = null;
          pendingIncomingMessages = 0;
        }
      }
      const unansweredIncomingMessages = pendingIncomingMessages;
      const contact = readableSenderName(conv.remoteName, conv.remotePhone) ?? conv.remotePhone ?? conv.remoteJid;
      const last = items[items.length - 1];
      const lastMessageBy = last
        ? last.direction === WhatsappMessageDirection.OUTGOING
          ? 'vendedor'
          : 'cliente'
        : 'desconocido';
      const responsibilityDetected = this.detectWhatsappResponsibility({
        lastMessageBy,
        unansweredIncomingMessages,
        totalMessages: items.length,
        incomingMessages: items.filter((m) => m.direction === WhatsappMessageDirection.INCOMING).length,
        outgoingMessages: items.filter((m) => m.direction === WhatsappMessageDirection.OUTGOING).length,
        lastMessageRequiresClientResponse: this.whatsappMessageRequiresClientResponse(
          last?.body ?? last?.caption ?? '',
        ),
      });
      return {
        conversationId,
        contact,
        phone: conv.remotePhone,
        instanceName: conv.instance?.instanceName ?? '',
        userName: conv.instance?.user?.nombreCompleto ?? conv.instance?.instanceName ?? '',
        firstMessageAt: items[0]?.sentAt?.toISOString() ?? null,
        lastMessageAt: items[items.length - 1]?.sentAt?.toISOString() ?? null,
        totalMessages: items.length,
        incomingMessages: items.filter((m) => m.direction === WhatsappMessageDirection.INCOMING).length,
        outgoingMessages: items.filter((m) => m.direction === WhatsappMessageDirection.OUTGOING).length,
        averageResponseMinutes: responseTimes.length
          ? Math.round(responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length)
          : null,
        maxResponseMinutes: responseTimes.length ? Math.round(Math.max(...responseTimes)) : null,
        unansweredIncomingMessages,
        lastMessageBy,
        responsibilityDetected,
        messages: items.slice(-80).map((m) => ({
          id: m.id,
          timestamp: m.sentAt.toISOString(),
          time: m.sentAt.toISOString(),
          direction: m.direction === WhatsappMessageDirection.OUTGOING ? 'outbound' : 'inbound',
          senderRole: m.direction === WhatsappMessageDirection.OUTGOING ? 'vendedor' : 'cliente',
          senderName: m.direction === WhatsappMessageDirection.OUTGOING
            ? (m.senderName ?? conv.instance?.user?.nombreCompleto ?? conv.instance?.instanceName ?? 'Vendedor')
            : (m.senderName ?? contact),
          senderPhone: m.direction === WhatsappMessageDirection.OUTGOING
            ? (conv.instance?.phoneNumber ?? null)
            : (conv.remotePhone ?? null),
          instanceName: conv.instance?.instanceName ?? '',
          fromMe: m.direction === WhatsappMessageDirection.OUTGOING,
          body: (m.body ?? m.caption ?? '').replace(/\s+/g, ' ').trim().slice(0, 1200),
          type: m.messageType,
          messageType: m.messageType,
          text: (m.body ?? m.caption ?? '').replace(/\s+/g, ' ').trim().slice(0, 1200),
          media: mediaSummaries.get(m.id) ?? null,
        })),
      };
    });
  }

  private detectWhatsappResponsibility(input: {
    lastMessageBy: 'cliente' | 'vendedor' | 'desconocido';
    unansweredIncomingMessages: number;
    totalMessages: number;
    incomingMessages: number;
    outgoingMessages: number;
    lastMessageRequiresClientResponse?: boolean;
  }): WhatsappResponsibilityOption {
    if (input.totalMessages === 0) return 'No hay evidencia suficiente';
    if (input.unansweredIncomingMessages > 0 || input.lastMessageBy === 'cliente') {
      return 'Vendedor no respondio';
    }
    if (input.incomingMessages === 0 && input.outgoingMessages === 0) {
      return 'No hay evidencia suficiente';
    }
    if (input.lastMessageBy === 'vendedor') {
      return input.lastMessageRequiresClientResponse
        ? 'Cliente no respondio'
        : 'Conversacion normal';
    }
    return 'Conversacion normal';
  }

  private whatsappMessageRequiresClientResponse(value: unknown) {
    const text = asString(value)?.toLowerCase() ?? '';
    if (!text) return false;
    if (text.includes('?') || text.includes('¿')) return true;
    return [
      'confirm',
      'avisame',
      'avísame',
      'quedo atento',
      'pendiente',
      'me indica',
      'me confirmas',
      'responde',
      'respuesta',
      'interesa',
      'coordinamos',
      'cuando',
      'cuándo',
      'hora',
      'fecha',
      'direccion',
      'dirección',
    ].some((needle) => text.includes(needle));
  }

  private normalizeWhatsappResponsibility(value: unknown): WhatsappResponsibilityOption {
    const raw = asString(value)?.toLowerCase() ?? '';
    if (!raw) return 'No hay evidencia suficiente';
    if (raw.includes('cliente') && raw.includes('no respond')) {
      return 'Cliente no respondio';
    }
    if (raw.includes('vendedor') && raw.includes('no respond')) {
      return 'Vendedor no respondio';
    }
    if (raw.includes('requiere') && raw.includes('seguimiento')) {
      return 'Requiere seguimiento del vendedor';
    }
    if (raw.includes('normal')) return 'Conversacion normal';
    if (raw.includes('insuficiente') || raw.includes('evidencia')) {
      return 'No hay evidencia suficiente';
    }
    return 'No hay evidencia suficiente';
  }

  private buildWhatsappResponsibilityEvidence(conv: WhatsappAiConversationContext) {
    const last = conv.messages[conv.messages.length - 1];
    const lastWriter = conv.lastMessageBy === 'cliente'
      ? `cliente ${conv.contact}${conv.phone ? ` (${conv.phone})` : ''}`
      : conv.lastMessageBy === 'vendedor'
        ? `vendedor ${conv.userName || 'Usuario no identificado'} / instancia ${conv.instanceName || 'Instancia no identificada'}`
        : 'desconocido';
    const lastText = last?.text || last?.media?.summary || 'No hay evidencia suficiente.';
    return `Ultimo mensaje de ${lastWriter}. Evidencia: ${lastText.slice(0, 500)}`;
  }

  private buildDeterministicWhatsappResponsibilities(
    conversations: WhatsappAiConversationContext[],
  ) {
    return conversations.map((conv) => ({
      conversationId: conv.conversationId,
      cliente: `${conv.contact}${conv.phone ? ` (${conv.phone})` : ''}`,
      atendidoPor: `${conv.userName || 'Usuario no identificado'} / ${conv.instanceName || 'Instancia no identificada'}`,
      estado: conv.responsibilityDetected,
      evidencia: conv.messages.length
        ? this.buildWhatsappResponsibilityEvidence(conv)
        : 'No hay evidencia suficiente.',
      ultimoMensajeDe: conv.lastMessageBy,
      accion: conv.responsibilityDetected === 'Vendedor no respondio'
        ? 'Dar seguimiento al cliente desde la instancia correspondiente.'
        : conv.responsibilityDetected === 'Cliente no respondio'
          ? 'Esperar respuesta o programar seguimiento comercial.'
          : conv.responsibilityDetected === 'Requiere seguimiento del vendedor'
            ? 'Asignar seguimiento claro al vendedor responsable.'
            : conv.responsibilityDetected === 'No hay evidencia suficiente'
              ? 'Revisar mas mensajes o ampliar el rango antes de concluir.'
              : 'Mantener monitoreo normal.',
    }));
  }

  private buildWhatsappAiStats(conversations: WhatsappAiConversationContext[], range: { label: string; startIso: string; endIso: string }, scope: WhatsappAiScope) {
    const totalMessages = conversations.reduce((sum, conv) => sum + conv.totalMessages, 0);
    return {
      scope,
      rangeLabel: range.label,
      startAt: range.startIso,
      endAt: range.endIso,
      contacts: conversations.length,
      totalMessages,
      incomingMessages: conversations.reduce((sum, conv) => sum + conv.incomingMessages, 0),
      outgoingMessages: conversations.reduce((sum, conv) => sum + conv.outgoingMessages, 0),
      mediaMessages: conversations.reduce((sum, conv) => sum + conv.messages.filter((m) => m.media != null).length, 0),
    };
  }

  private buildDeterministicWhatsappAiReport(conversations: WhatsappAiConversationContext[], stats: Record<string, unknown>): WhatsappAiReport {
    const problematic = conversations
      .filter((conv) => conv.unansweredIncomingMessages > 0 || (conv.maxResponseMinutes ?? 0) > 180 || this.hasRiskWords(conv))
      .map((conv) => ({
        conversationId: conv.conversationId,
        contacto: conv.contact,
        telefono: conv.phone,
        motivo: conv.unansweredIncomingMessages > 0
          ? 'Mensajes del cliente sin respuesta dentro del rango.'
          : this.hasRiskWords(conv)
            ? 'Se detectaron palabras asociadas a reclamo, molestia o posible fraude.'
            : 'Tiempo de respuesta alto.',
        evidencia: this.pickConversationEvidence(conv),
        prioridad: this.hasCriticalWords(conv) ? 'alta' : 'media',
        accionRecomendada: 'Revisar la conversacion, responder con seguimiento claro y documentar el cierre.',
        clasificacion: this.hasCriticalWords(conv) ? 'Conversacion critica' : 'Requiere atencion',
      }));
    const critical = problematic.filter((item) => item.prioridad === 'alta').length;
    const fraud = problematic.filter((item) => item.motivo.toLowerCase().includes('fraude')).length;
    const responsabilidadDetectada = this.buildDeterministicWhatsappResponsibilities(conversations);
    return {
      estadoGeneral: critical > 0 ? 'Critico' : problematic.length > 0 ? 'Atencion requerida' : 'Normal',
      resumenEjecutivo: conversations.length === 0
        ? 'No hay mensajes en el rango seleccionado. No hay evidencia suficiente para evaluar conversaciones.'
        : problematic.length > 0
          ? `Se analizaron ${conversations.length} conversaciones y se encontraron ${problematic.length} con posibles alertas. Revisar prioridades antes de cerrar el dia.`
          : `Se analizaron ${conversations.length} conversaciones sin evidencia suficiente de conflictos, fraude o falta de seguimiento grave.`,
      totalConversacionesAnalizadas: conversations.length,
      totalMensajesAnalizados: Number(stats.totalMessages ?? 0),
      casosNormales: Math.max(0, conversations.length - problematic.length),
      casosConAlerta: problematic.length,
      casosCriticos: critical,
      posiblesFraudesDetectados: fraud,
      clientesSinRespuesta: conversations.filter((conv) => conv.unansweredIncomingMessages > 0).length,
      recomendacionesConcretas: problematic.length
        ? ['Responder primero los clientes sin respuesta.', 'Confirmar promesas pendientes con fecha y responsable.', 'Escalar reclamos o sospechas de pago antes de entregar productos/servicios.']
        : ['Mantener seguimiento regular y registrar proximos pasos cuando haya interes comercial.'],
      conversacionesProblematicas: problematic,
      responsabilidadDetectada,
    };
  }

  private hasRiskWords(conv: WhatsappAiConversationContext) {
    const text = conv.messages.map((m) => `${m.text} ${m.media?.summary ?? ''}`).join(' ').toLowerCase();
    return ['reclamo', 'molesto', 'denuncia', 'devolucion', 'devolución', 'fraude', 'estafa', 'pago', 'transferencia', 'no me resolvieron', 'redes'].some((word) => text.includes(word));
  }

  private hasCriticalWords(conv: WhatsappAiConversationContext) {
    const text = conv.messages.map((m) => `${m.text} ${m.media?.summary ?? ''}`).join(' ').toLowerCase();
    return ['denuncia', 'fraude', 'estafa', 'demanda', 'redes', 'policia', 'policía'].some((word) => text.includes(word));
  }

  private pickConversationEvidence(conv: WhatsappAiConversationContext) {
    const evidence = conv.messages.find((m) => m.text.trim().length > 0 || m.media?.summary);
    if (!evidence) return 'No hay evidencia suficiente.';
    return (evidence.text || evidence.media?.summary || 'No hay evidencia suficiente.').slice(0, 500);
  }

  private async requestWhatsappAiAnalysisFromOpenAi(
    runtime: { apiKey: string; model: string; companyName: string },
    payload: {
      range: { label: string; startIso: string; endIso: string };
      scope: WhatsappAiScope;
      stats: Record<string, unknown>;
      conversations: WhatsappAiConversationContext[];
    },
  ): Promise<WhatsappAiReport> {
    const candidates = [runtime.model, 'gpt-5', 'gpt-4.1', 'gpt-4o', 'gpt-4o-mini'].filter(
      (value, index, list) => value && list.indexOf(value) === index,
    );
    const compactConversations = payload.conversations.slice(0, 80).map((conv) => ({
      ...conv,
      messages: conv.messages.slice(-70),
    }));
    const systemPrompt =
      `Eres auditor ejecutivo del CRM WhatsApp de ${runtime.companyName}. ` +
      'Analiza conversaciones SOLO con la evidencia provista. No inventes. Diferencia hecho confirmado, sospecha, recomendacion y dato pendiente. ' +
      'Regla obligatoria de identidad: fromMe=true, direction=outbound y senderRole=vendedor significan mensaje enviado por la empresa/vendedor. fromMe=false, direction=inbound y senderRole=cliente significan mensaje enviado por el cliente/contacto externo. Nunca asumas lo contrario. ' +
      'Cada mensaje del contexto trae direction, senderRole, senderName, senderPhone, instanceName, fromMe, timestamp, body y messageType. Usa esos campos como fuente de verdad y no uses frases ambiguas como mensaje enviado sin indicar quien lo envio. ' +
      'Para cada evidencia importante indica quien escribio: cliente o vendedor, y el nombre/telefono/instancia cuando exista. Si no hay evidencia suficiente, dilo exactamente. ' +
      'Detecta posible fraude, conflictos, mala atencion, falta de seguimiento, vendedor sin dedicacion, clientes molestos, reclamos, mensajes sin responder, promesas incumplidas, errores de comunicacion, oportunidades de venta y conversaciones normales. ' +
      'Trata cedulas/documentos como datos sensibles y no copies numeros completos.';
    const schema = {
      estadoGeneral: 'Normal|Atencion requerida|Critico',
      resumenEjecutivo: 'texto ejecutivo breve',
      totalConversacionesAnalizadas: 0,
      totalMensajesAnalizados: 0,
      casosNormales: 0,
      casosConAlerta: 0,
      casosCriticos: 0,
      posiblesFraudesDetectados: 0,
      clientesSinRespuesta: 0,
      recomendacionesConcretas: ['acciones concretas'],
      conversacionesProblematicas: [{
        conversationId: 'id', contacto: 'nombre', telefono: 'telefono', motivo: 'motivo', evidencia: 'texto/resumen', prioridad: 'baja|media|alta|critica', accionRecomendada: 'accion', clasificacion: 'Normal|Requiere atencion|Riesgo de conflicto|Posible fraude|Cliente molesto|Falta de seguimiento|Venta potencial|Reclamo abierto|Conversacion critica',
      }],
      responsabilidadDetectada: [{
        conversationId: 'id', cliente: 'nombre/telefono', atendidoPor: 'usuario/instancia', estado: 'Cliente no respondio|Vendedor no respondio|Conversacion normal|Requiere seguimiento del vendedor|No hay evidencia suficiente', evidencia: 'quien escribio y que paso', ultimoMensajeDe: 'cliente|vendedor|desconocido', accion: 'accion recomendada',
      }],
    };
    const userPrompt = {
      rango: payload.range,
      alcance: payload.scope,
      estadisticas: payload.stats,
      conversaciones: compactConversations,
      reglas: [
        'El reporte debe usar exactamente este rango.',
        'fromMe=true significa empresa/vendedor; fromMe=false significa cliente/contacto. Nunca invertir roles.',
        'direction=outbound significa enviado por vendedor/empresa; direction=inbound significa recibido del cliente.',
        'senderRole es la fuente de verdad para saber quien escribio cada mensaje importante.',
        'En responsabilidadDetectada usa solo una de estas opciones: Cliente no respondio, Vendedor no respondio, Conversacion normal, Requiere seguimiento del vendedor, No hay evidencia suficiente.',
        'Nunca marques al cliente como responsable si el ultimo mensaje fue inbound/fromMe=false/senderRole=cliente.',
        'Nunca marques al vendedor como responsable si el ultimo mensaje fue outbound/fromMe=true/senderRole=vendedor y no hay mensajes posteriores del cliente.',
        'Si no hay evidencia suficiente, escribir: No hay evidencia suficiente.',
        'No guardar ni repetir imagenes completas; usa solo resumen visual.',
        'Indicar audio pendiente de transcripcion cuando aplique.',
      ],
      formatoObligatorio: schema,
    };

    for (const model of candidates) {
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 18000);
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          signal: controller.signal,
          headers: {
            Authorization: `Bearer ${runtime.apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model,
            temperature: 0.08,
            max_tokens: 4500,
            messages: [
              { role: 'system', content: systemPrompt },
              { role: 'user', content: `Devuelve SOLO JSON valido.\n${JSON.stringify(userPrompt).slice(0, 60000)}` },
            ],
          }),
        }).finally(() => clearTimeout(timeout));
        if (!response.ok) continue;
        const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> };
        const content = data.choices?.[0]?.message?.content?.trim();
        if (!content) continue;
        const first = content.indexOf('{');
        const last = content.lastIndexOf('}');
        const json = first >= 0 && last > first ? content.slice(first, last + 1) : content;
        return JSON.parse(json) as WhatsappAiReport;
      } catch {
        continue;
      }
    }
    throw new BadRequestException('No se pudo generar el analisis de IA.');
  }

  private normalizeWhatsappAiResponse(input: {
    source: string;
    cached: boolean;
    range: { label: string; startIso: string; endIso: string; key: string };
    stats: Record<string, unknown>;
    report: WhatsappAiReport;
    conversations: WhatsappAiConversationContext[];
    mediaSummaries: Map<string, WhatsappAiMediaContext>;
  }) {
    const alerts = input.report.conversacionesProblematicas.map((item) => ({
      type: item.clasificacion?.toLowerCase().includes('fraude') ? 'fraud' : item.clasificacion?.toLowerCase().includes('molesto') ? 'angry_customer' : item.clasificacion?.toLowerCase().includes('seguimiento') ? 'no_response' : 'crm_risk',
      severity: item.prioridad === 'critica' || item.prioridad === 'alta' ? 'high' : item.prioridad === 'media' ? 'medium' : 'low',
      contact: item.contacto,
      description: `${item.motivo}. Evidencia: ${item.evidencia}`,
    }));
    const conversationAnalysis = input.conversations.map((conv) => {
      const problem = input.report.conversacionesProblematicas.find((item) => item.conversationId === conv.conversationId || item.contacto === conv.contact);
      return {
        contact: conv.contact,
        messageCount: conv.totalMessages,
        status: problem ? this.mapWhatsappAiClassificationToStatus(problem.clasificacion) : 'normal',
        issues: problem ? [problem.motivo, problem.accionRecomendada] : [],
        summary: problem?.evidencia ?? 'Conversacion normal sin problema evidente.',
      };
    });
    const imageSummaries = Array.from(input.mediaSummaries.values())
      .filter((item) => item.type === 'image')
      .map((item) => ({ messageId: item.messageId, summary: item.summary }));
    const audioTranscriptionStatus = Array.from(input.mediaSummaries.values())
      .filter((item) => item.type === 'audio')
      .map((item) => ({ messageId: item.messageId, status: item.transcriptionStatus }));
    const deterministicResponsibilities = this.buildDeterministicWhatsappResponsibilities(input.conversations);
    const rawResponsibilities = Array.isArray(input.report.responsabilidadDetectada)
      ? input.report.responsabilidadDetectada
      : [];
    const responsabilidadDetectada = deterministicResponsibilities.map((deterministic) => {
      const aiItem = rawResponsibilities.find((item) =>
        item?.conversationId === deterministic.conversationId,
      ) as Record<string, unknown> | undefined;
      return {
        ...deterministic,
        ...(aiItem ?? {}),
        conversationId: deterministic.conversationId,
        cliente: deterministic.cliente,
        atendidoPor: deterministic.atendidoPor,
        estado: this.normalizeWhatsappResponsibility(
          aiItem?.estado ?? deterministic.estado,
        ),
        ultimoMensajeDe: deterministic.ultimoMensajeDe,
        evidencia: asString(aiItem?.evidencia) ?? deterministic.evidencia,
        accion: asString(aiItem?.accion) ?? deterministic.accion,
      };
    });
    const analyzedConversations = input.conversations.map((conv) => ({
      conversationId: conv.conversationId,
      cliente: { nombre: conv.contact, telefono: conv.phone },
      atendidoPor: { usuario: conv.userName, instancia: conv.instanceName },
      lastMessageBy: conv.lastMessageBy,
      responsibilityDetected: conv.responsibilityDetected,
      unansweredIncomingMessages: conv.unansweredIncomingMessages,
      messages: conv.messages.map((m) => ({
        id: m.id,
        timestamp: m.timestamp,
        direction: m.direction,
        senderRole: m.senderRole,
        senderName: m.senderName,
        senderPhone: m.senderPhone,
        instanceName: m.instanceName,
        fromMe: m.fromMe,
        body: m.body,
        messageType: m.messageType,
        media: m.media
          ? {
              type: m.media.type,
              status: m.media.status,
              summary: m.media.summary,
              transcriptionStatus: m.media.transcriptionStatus,
            }
          : null,
      })),
    }));
    const reportWithResponsibility = {
      ...input.report,
      responsabilidadDetectada,
    };
    return {
      source: input.source,
      cached: input.cached,
      dateRange: input.range,
      stats: input.stats,
      summary: input.report.resumenEjecutivo,
      alerts,
      conversationAnalysis,
      report: reportWithResponsibility,
      responsabilidadDetectada,
      imageSummaries,
      audioTranscriptionStatus,
      analyzedConversations,
      generatedAt: new Date().toISOString(),
    };
  }

  private mapWhatsappAiClassificationToStatus(value: string) {
    const text = (value ?? '').toLowerCase();
    if (text.includes('fraude')) return 'fraud';
    if (text.includes('critica')) return 'critical';
    if (text.includes('molesto') || text.includes('conflicto')) return 'angry';
    if (text.includes('seguimiento') || text.includes('respuesta')) return 'no_response';
    if (text.includes('venta')) return 'interested';
    return 'pending';
  }

  private async saveWhatsappAiReport(input: {
    scope: WhatsappAiScope;
    conversationId?: string | null;
    dateRangeKey: string;
    startAt: Date;
    endAt: Date;
    fingerprint: string;
    report: Record<string, unknown>;
    generatedBy?: string | null;
  }) {
    const id = randomUUID();
    const report = input.report;
    const rawReport = (report.report ?? {}) as Record<string, unknown>;
    const riskLevel = String(rawReport.estadoGeneral ?? 'Normal');
    await this.prisma.$executeRaw`
      INSERT INTO whatsapp_ai_analysis_reports
        (id, conversation_id, scope, date_range_key, start_at, end_at, message_fingerprint, risk_level, summary, alerts, image_summaries, audio_transcription_status, report, generated_by)
      VALUES
        (${id}::uuid, ${input.conversationId}::uuid, ${input.scope}, ${input.dateRangeKey}, ${input.startAt}, ${input.endAt}, ${input.fingerprint}, ${riskLevel}, ${String(report.summary ?? '')}, CAST(${JSON.stringify(report.alerts ?? [])} AS jsonb), CAST(${JSON.stringify(report.imageSummaries ?? [])} AS jsonb), CAST(${JSON.stringify(report.audioTranscriptionStatus ?? [])} AS jsonb), CAST(${JSON.stringify(report)} AS jsonb), ${input.generatedBy}::uuid)
    `;
    return id;
  }

  private withTimeout<T>(
    promise: Promise<T>,
    timeoutMs: number,
    message: string,
  ): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error(message)), timeoutMs);
      promise.then(
        (value) => {
          clearTimeout(timeout);
          resolve(value);
        },
        (error) => {
          clearTimeout(timeout);
          reject(error);
        },
      );
    });
  }

  private async transcribeAudioBase64(
    dataUrl: string,
    mimeType: string,
    apiKey: string,
  ): Promise<string | null> {
    try {
      const base64 = dataUrl.replace(/^data:[^;]+;base64,/, '');
      const buffer = Buffer.from(base64, 'base64');
      const ext = mimeType.includes('ogg')
        ? 'ogg'
        : mimeType.includes('mp4')
          ? 'mp4'
          : mimeType.includes('mpeg') || mimeType.includes('mp3')
            ? 'mp3'
            : 'ogg';
      const form = new FormData();
      form.append(
        'file',
        new Blob([buffer], { type: mimeType }),
        `audio.${ext}`,
      );
      form.append('model', 'whisper-1');
      form.append('language', 'es');
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5000);
      const response = await fetch(
        'https://api.openai.com/v1/audio/transcriptions',
        {
          method: 'POST',
          signal: controller.signal,
          headers: { Authorization: `Bearer ${apiKey}` },
          body: form,
        },
      ).finally(() => clearTimeout(timeout));
      if (!response.ok) return null;
      const data = (await response.json()) as { text?: string };
      return (data.text ?? '').trim() || null;
    } catch {
      return null;
    }
  }

  private async getOpenAiRuntimeConfig() {
    const envKey = (
      this.config.get<string>('OPENAI_API_KEY') ??
      process.env.OPENAI_API_KEY ??
      ''
    ).trim();
    const envModel = (
      this.config.get<string>('OPENAI_MODEL') ??
      process.env.OPENAI_MODEL ??
      ''
    ).trim();
    const appConfig = await this.prisma.appConfig
      .findUnique({
        where: { id: 'global' },
        select: { openAiApiKey: true, openAiModel: true, companyName: true },
      })
      .catch(() => null);

    return {
      apiKey:
        envKey.length > 0 ? envKey : (appConfig?.openAiApiKey ?? '').trim(),
      model:
        envModel.length > 0
          ? envModel
          : (appConfig?.openAiModel ?? '').trim() || 'gpt-4o-mini',
      companyName: (appConfig?.companyName ?? 'FULLTECH').trim() || 'FULLTECH',
    };
  }

  private buildDeterministicDailySummary(
    stats: {
      date: string;
      userName: string;
      totalMessages: number;
      incomingMessages: number;
      outgoingMessages: number;
      contacts: number;
      mediaMessages: number;
    },
    transcript: Array<{ direction: string; text: string; contact: string }>,
  ) {
    const interestWords = [
      'precio',
      'cotizacion',
      'cotización',
      'quiero',
      'interesa',
      'disponible',
      'comprar',
      'instalar',
    ];
    const followWords = [
      'mañana',
      'luego',
      'despues',
      'después',
      'pendiente',
      'seguimiento',
      'confirmar',
    ];
    const interested = new Set<string>();
    const followups = new Set<string>();

    for (const item of transcript) {
      const text = item.text.toLowerCase();
      if (interestWords.some((word) => text.includes(word)))
        interested.add(item.contact);
      if (followWords.some((word) => text.includes(word)))
        followups.add(item.contact);
    }

    return [
      `Resumen del ${stats.date} para ${stats.userName}.`,
      `Actividad: ${stats.totalMessages} mensajes en ${stats.contacts} contactos. Recibidos: ${stats.incomingMessages}. Enviados desde la instancia: ${stats.outgoingMessages}. Multimedia: ${stats.mediaMessages}.`,
      `Interes comercial detectado: ${interested.size} contacto(s) con señales de compra, cotizacion o disponibilidad.`,
      `Seguimientos detectados: ${followups.size} contacto(s) con menciones de pendiente, confirmar o retomar.`,
      'Recomendacion: revisar los contactos con interes y confirmar que cada conversacion tenga proximo paso claro, monto/categoria y responsable.',
    ].join('\n\n');
  }

  private async requestDailySummaryFromOpenAi(
    runtime: { apiKey: string; model: string; companyName: string },
    payload: {
      stats: unknown;
      transcript: unknown;
      images?: Array<{ contact: string; url: string }>;
      audioTranscriptions?: Array<{ contact: string; text: string }>;
      conversationIds?: Array<{
        contact: string;
        messageCount: number;
        hasIncoming: boolean;
        hasOutgoing: boolean;
        hasMedia: boolean;
      }>;
    },
  ): Promise<{
    summary?: string;
    alerts?: Array<{ type: string; severity: string; contact: string; description: string }>;
    conversationAnalysis?: Array<{
      contact: string;
      messageCount: number;
      status: string;
      issues: string[];
      summary: string;
    }>;
  }> {
    const candidates = [
      runtime.model,
      'gpt-5',
      'gpt-4.1',
      'gpt-4o',
      'gpt-4o-mini',
    ].filter((value, index, list) => value && list.indexOf(value) === index);

    const systemPrompt =
      `Eres un analista CRM y auditor de cumplimiento de ${runtime.companyName}. ` +
      'Analiza la actividad diaria de WhatsApp de un empleado para: ' +
      '1) Evaluar desempeno de ventas y seguimiento. ' +
      '2) Detectar conductas inapropiadas o falta de profesionalismo del usuario (empleado). ' +
      '3) Detectar clientes enojados, frustrados o que no recibieron respuesta. ' +
      '4) Detectar senales de fraude, acuerdos fuera del sistema, pagos informales, descuentos no autorizados. ' +
      '5) Revisar ortografia y redaccion del empleado. ' +
      '6) Generar alertas accionables con nivel de riesgo. ' +
      'Basa tu analisis SOLO en los mensajes proporcionados. No inventes informacion. Escribe en espanol profesional.';

    const textPayload = {
      stats: payload.stats,
      transcript: payload.transcript,
      audioTranscriptions: payload.audioTranscriptions ?? [],
      conversations: payload.conversationIds ?? [],
    };

    const outputSchema =
      'Devuelve SOLO JSON con esta estructura exacta:\n' +
      '{"summary":"resumen ejecutivo del dia",' +
      '"alerts":[{"type":"fraud|misconduct|no_response|angry_customer|spelling|unanswered","severity":"high|medium|low","contact":"nombre del contacto o usuario","description":"descripcion especifica"}],' +
      '"conversationAnalysis":[{"contact":"nombre","messageCount":0,"status":"interested|not_interested|angry|no_response|closed|pending","issues":["lista de problemas detectados"],"summary":"resumen de 1-2 lineas de esta conversacion"}]}';

    // Build user message content — include images if available
    const userContent: Array<{ type: string; text?: string; image_url?: { url: string; detail: string } }> = [];

    userContent.push({
      type: 'text',
      text: `Datos de actividad:\n${JSON.stringify(textPayload, null, 0).slice(0, 28000)}\n\n${outputSchema}`,
    });

    // Add image frames if available (vision)
    for (const img of payload.images ?? []) {
      userContent.push({
        type: 'text',
        text: `[Imagen enviada por/a: ${img.contact}]`,
      });
      userContent.push({
        type: 'image_url',
        image_url: { url: img.url, detail: 'low' },
      });
    }

    for (const model of candidates) {
      try {
        const isVisionModel =
          model.includes('gpt-4') || model.includes('gpt-5');
        const messageContent =
          isVisionModel && (payload.images?.length ?? 0) > 0
            ? userContent
            : userContent.filter((c) => c.type === 'text').map((c) => c.text).join('\n');

        const controller = new AbortController();
        const timeout = setTimeout(
          () => controller.abort(),
          DAILY_SUMMARY_AI_TIMEOUT_MS,
        );
        const response = await fetch(
          'https://api.openai.com/v1/chat/completions',
          {
            method: 'POST',
            signal: controller.signal,
            headers: {
              Authorization: `Bearer ${runtime.apiKey}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              model,
              temperature: 0.15,
              max_tokens: 3000,
              messages: [
                { role: 'system', content: systemPrompt },
                {
                  role: 'user',
                  content: messageContent,
                },
              ],
            }),
          },
        ).finally(() => clearTimeout(timeout));
        if (!response.ok) continue;
        const data = (await response.json()) as {
          choices?: Array<{ message?: { content?: string } }>;
        };
        const content = data.choices?.[0]?.message?.content?.trim();
        if (!content) continue;
        const first = content.indexOf('{');
        const last = content.lastIndexOf('}');
        const json =
          first >= 0 && last > first ? content.slice(first, last + 1) : content;
        return JSON.parse(json) as {
          summary?: string;
          alerts?: Array<{ type: string; severity: string; contact: string; description: string }>;
          conversationAnalysis?: Array<{ contact: string; messageCount: number; status: string; issues: string[]; summary: string }>;
        };
      } catch {
        continue;
      }
    }
    throw new BadRequestException('No se pudo generar el resumen de IA.');
  }
}
