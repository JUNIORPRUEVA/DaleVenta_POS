import { Type } from 'class-transformer';
import { IsArray, IsIn, IsOptional, IsString, IsUUID, MaxLength, ValidateNested } from 'class-validator';
import { AiChatContextDto } from './ai-chat-context.dto';

export class AiChatHistoryMessageDto {
  @IsIn(['user', 'assistant'])
  role!: 'user' | 'assistant';

  @IsString()
  content!: string;
}

export class ChatAiAssistantDto {
  @ValidateNested()
  @Type(() => AiChatContextDto)
  context!: AiChatContextDto;

  @IsString()
  message!: string;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => AiChatHistoryMessageDto)
  history?: AiChatHistoryMessageDto[];

  /**
   * Conversación en APPYRA IA. Se omite en el primer mensaje; la respuesta devuelve el
   * identificador que el cliente debe reenviar para conservar la continuidad. El valor es
   * opaco para FullPOS: no se interpreta ni se guarda fuera de la sesión del panel.
   */
  @IsOptional()
  @IsUUID()
  conversationId?: string;

  /** Evita duplicar el turno cuando el cliente reintenta el mismo envío. */
  @IsOptional()
  @IsString()
  @MaxLength(80)
  clientMessageId?: string;

  /**
   * Archivo ya procesado por el motor multimedia cuyo texto debe usar la respuesta.
   * Se obtiene en `POST /ai/attachments`; aquí solo viaja el identificador.
   */
  @IsOptional()
  @IsUUID()
  mediaJobId?: string;
}
