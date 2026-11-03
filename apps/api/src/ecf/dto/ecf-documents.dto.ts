import { Type } from "class-transformer";
import {
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from "class-validator";
import { EcfElectronicDocumentStatus } from "@prisma/client";
import {
  ALANUBE_SIMULATION_SCENARIOS,
  type AlanubeSimulationScenario,
} from "../alanube/alanube-scenario.transport";
import { ECF_ALLOWED_DOCUMENT_TYPES } from "../ecf.constants";

/**
 * Escenario del ALANUBE SIMULADO para el despacho de validación.
 *
 * No existe una variante "real": el proveedor real sigue en NO-GO y su ruta no
 * está cableada. Los escenarios disponibles son los que el simulador sabe
 * reproducir (`ALANUBE_SIMULATION_SCENARIOS`).
 */
export class SimulateEcfDispatchDto {
  @IsOptional()
  @IsIn([...ALANUBE_SIMULATION_SCENARIOS])
  scenario?: AlanubeSimulationScenario;
}

// Functional buckets the client UI groups by. They are a VIEW of the persisted
// status, never a replacement: the fiscal state machine remains the source of truth.
export const ECF_STATUS_GROUPS = [
  "PENDING",
  "REQUIRES_REVIEW",
  "ACCEPTED",
  "REJECTED",
  "CANCELLED",
] as const;
export type EcfStatusGroup = (typeof ECF_STATUS_GROUPS)[number];

export const ECF_GROUP_STATUSES: Record<EcfStatusGroup, EcfElectronicDocumentStatus[]> = {
  PENDING: [
    EcfElectronicDocumentStatus.LOCAL_DRAFT,
    EcfElectronicDocumentStatus.LOCAL_VALIDATION_PENDING,
    EcfElectronicDocumentStatus.LOCAL_VALIDATED,
    EcfElectronicDocumentStatus.READY_TO_SEND,
    EcfElectronicDocumentStatus.SEND_PENDING,
    EcfElectronicDocumentStatus.SEND_IN_PROGRESS,
    EcfElectronicDocumentStatus.DGII_STATUS_PENDING,
    EcfElectronicDocumentStatus.PROVIDER_ACCEPTED,
  ],
  // A provider rejection or an unknown result is NEVER resolved automatically:
  // it stays visible for a human, which is why it has its own bucket.
  REQUIRES_REVIEW: [
    EcfElectronicDocumentStatus.UNKNOWN_RESULT,
    EcfElectronicDocumentStatus.HUMAN_REVIEW_REQUIRED,
    EcfElectronicDocumentStatus.PROVIDER_REJECTED,
  ],
  ACCEPTED: [EcfElectronicDocumentStatus.DGII_ACCEPTED],
  REJECTED: [EcfElectronicDocumentStatus.DGII_REJECTED],
  CANCELLED: [EcfElectronicDocumentStatus.CANCELLED],
};

export class ListEcfDocumentsQueryDto {
  @IsOptional()
  @IsIn([...ECF_ALLOWED_DOCUMENT_TYPES])
  documentType?: "E31" | "E32" | "E34";

  @IsOptional()
  @IsIn(Object.values(EcfElectronicDocumentStatus))
  status?: EcfElectronicDocumentStatus;

  @IsOptional()
  @IsIn([...ECF_STATUS_GROUPS])
  group?: EcfStatusGroup;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  search?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  take?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  skip?: number;
}

export class RegisterEcfSequenceDto {
  @IsIn(["E31", "E34"])
  documentType!: "E31" | "E34";

  @Type(() => Number)
  @IsInt()
  @Min(1)
  startNumber!: number;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  endNumber!: number;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  validUntil?: string | null;
}

export class RenewEcfSequenceDto extends RegisterEcfSequenceDto {}

// Preparación de CONSUMO (E32). Flujo independiente del genérico: no consume el
// rango de numeración de la empresa, no toca el cupo único de sandbox y no
// emite. El e-NCF lo entrega su propio flujo, nunca este.
export class PrepareEcfConsumoDto {
  @IsString()
  @IsUUID()
  saleId!: string;

  @IsIn(["E32"])
  documentType!: "E32";

  @Type(() => Number)
  @IsInt()
  @IsIn([1, 2])
  paymentType!: 1 | 2;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @IsIn([1, 2, 3, 4, 5, 6])
  incomeType?: 1 | 2 | 3 | 4 | 5 | 6;

  @IsOptional()
  @IsString()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  sequenceDueDate?: string;

  @IsOptional()
  @IsString()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  paymentDeadline?: string;
}

// Preparar NO es emitir: crea un borrador local validado desde una venta real.
// `paymentType` es obligatorio y explícito porque el repositorio no contiene un
// mapeo oficial verificado entre `Sale.paymentMethod` y el código del contrato.
/**
 * Confirmación SUPERVISADA de la clasificación fiscal de una partida (F1).
 *
 * Solo se usa para partidas que no tienen producto y por tanto no tienen
 * clasificación congelada. Exige motivo porque la decisión debe poder auditarse:
 * quien la revise después tiene que entender por qué se declaró bien o servicio.
 */
export class ConfirmEcfLineClassificationDto {
  @IsString()
  @IsUUID()
  saleId!: string;

  @IsString()
  @IsUUID()
  saleItemId!: string;

  @IsIn(["PRODUCT", "SERVICE"])
  classification!: "PRODUCT" | "SERVICE";

  @IsString()
  @MinLength(3)
  @MaxLength(300)
  reason!: string;
}

export class PrepareEcfDocumentDto {
  @IsString()
  @IsUUID()
  saleId!: string;

  @IsIn(["E31"])
  documentType!: "E31";

  @Type(() => Number)
  @IsInt()
  // El contrato del proveedor declara `paymentType` con enum [1, 2] para E31.
  @IsIn([1, 2])
  paymentType!: 1 | 2;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @IsIn([1, 2, 3, 4, 5, 6])
  incomeType?: 1 | 2 | 3 | 4 | 5 | 6;

  @IsOptional()
  @IsString()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  sequenceDueDate?: string;

  @IsOptional()
  @IsString()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  paymentDeadline?: string;
}

/// Línea a acreditar en una nota parcial. Solo indica QUÉ se acredita; la
/// clasificación fiscal y el precio los toma el servidor del original.
export class EcfCreditNoteLineDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  lineNumber!: number;

  @IsString()
  @MaxLength(20)
  quantity!: string;
}

export class PrepareEcfCreditNoteDto {
  @IsUUID()
  originalDocumentId!: string;

  /// Ancla la idempotencia y la numeración de ESTA nota.
  @IsUUID()
  clientRequestId!: string;

  @IsIn(["TOTAL", "PARTIAL"])
  refundKind!: "TOTAL" | "PARTIAL";

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => EcfCreditNoteLineDto)
  lines?: EcfCreditNoteLineDto[];

  /// enum [1,2,3,4] del contrato. Selección explícita: el esquema publicado no
  /// documenta la semántica de cada código.
  @Type(() => Number)
  @IsInt()
  @IsIn([1, 2, 3, 4])
  modificationCode!: 1 | 2 | 3 | 4;

  @IsString()
  @MaxLength(90)
  modificationReason!: string;

  @Type(() => Number)
  @IsInt()
  @IsIn([1, 2])
  paymentType!: 1 | 2;

  /// enum [0,1] del contrato, exigido por `idDoc` en E34.
  @Type(() => Number)
  @IsInt()
  @IsIn([0, 1])
  creditNoteIndicator!: 0 | 1;

  @IsOptional()
  @IsString()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  sequenceDueDate?: string;
}
