import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import {
  ECF_DGII_MAX_DOCUMENT_BYTES,
  validateDocument,
  type EcfDgiiDocumentKind,
} from "./ecf-dgii-document.policy";
import { EcfDgiiDocumentStorage } from "./ecf-dgii-document.storage";

export type UploadEcfDgiiDocumentInput = {
  kind: EcfDgiiDocumentKind;
  fileName?: string | null;
  declaredMime?: string | null;
  buffer: Buffer;
  size?: number;
};

export type DownloadedEcfDgiiDocument = {
  fileName: string;
  mimeType: string;
  buffer: Buffer;
  sha256: string | null;
};

/**
 * Documentos del expediente DGII.
 *
 * Reutiliza la tabla de evidencias existente (`ecf_evidences`) en lugar de crear
 * un almacén paralelo: una evidencia ya tiene empresa, procedencia, hash, estado
 * de revisión y autor. Lo que faltaba era el flujo real de carga y descarga.
 *
 * Reglas:
 * - Todo se acota a la empresa del contexto autenticado (`requireTenant`).
 * - El tipo real se valida por contenido antes de escribir nada.
 * - Duplicado (misma empresa + misma clase + mismo SHA-256) devuelve el registro
 *   existente en vez de crear otro: un doble clic no ensucia el expediente.
 * - Nunca se devuelve `storageRef` al cliente.
 */
@Injectable()
export class EcfDgiiDocumentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: EcfDgiiDocumentStorage,
  ) {}

  async upload(
    user: TenantUser,
    input: UploadEcfDgiiDocumentInput,
  ): Promise<{
    id: string;
    sha256: string;
    size: number;
    mimeType: string;
    fileName: string;
    duplicate: boolean;
  }> {
    const companyId = requireTenant(user);

    if (!input.buffer || input.buffer.length === 0) {
      throw new BadRequestException("ECF_DGII_DOCUMENT_EMPTY");
    }
    if ((input.size ?? input.buffer.length) > ECF_DGII_MAX_DOCUMENT_BYTES) {
      throw new BadRequestException("ECF_DGII_DOCUMENT_TOO_LARGE");
    }

    const validation = validateDocument({
      buffer: input.buffer,
      size: input.size,
      declaredMime: input.declaredMime,
      fileName: input.fileName,
    });
    if (!validation.ok) {
      throw new BadRequestException(validation.code);
    }

    const existing = await this.prisma.ecfEvidence.findFirst({
      where: { companyId, kind: input.kind, sha256: validation.sha256 },
      select: { id: true, fileName: true, mimeType: true },
    });
    if (existing) {
      return {
        id: existing.id,
        sha256: validation.sha256,
        size: validation.size,
        mimeType: existing.mimeType ?? validation.mimeType,
        fileName: existing.fileName ?? validation.safeFileName,
        duplicate: true,
      };
    }

    const stored = await this.storage.save({
      companyId,
      buffer: input.buffer,
      extension: validation.extension,
    });

    const row = await this.prisma.ecfEvidence.create({
      data: {
        companyId,
        // Una carga del cliente es una declaración manual: NUNCA es un registro
        // oficial. La promoción a `DGII_OFFICIAL_RECORD` es un acto aparte y
        // auditado, con permiso propio.
        source: "MANUAL_DECLARATION",
        kind: input.kind,
        storageRef: stored.storageRef,
        fileName: validation.safeFileName,
        mimeType: validation.mimeType,
        sha256: validation.sha256,
        uploadedByUserId: user.id ?? null,
      },
      select: { id: true },
    });

    return {
      id: row.id,
      sha256: validation.sha256,
      size: validation.size,
      mimeType: validation.mimeType,
      fileName: validation.safeFileName,
      duplicate: false,
    };
  }

  async download(
    user: TenantUser,
    evidenceId: string,
  ): Promise<DownloadedEcfDgiiDocument> {
    const companyId = requireTenant(user);
    return this.readDocument(companyId, evidenceId);
  }

  /**
   * Descarga con EMPRESA EXPLÍCITA (panel de plataforma).
   *
   * La empresa se pasa como parámetro porque el personal de Fulltech revisa
   * expedientes de otras empresas. Sigue siendo una lectura acotada: la evidencia
   * debe pertenecer a ESA empresa, y `storageRef` nunca sale del servidor.
   */
  async downloadForCompany(
    companyId: string,
    evidenceId: string,
  ): Promise<DownloadedEcfDgiiDocument> {
    return this.readDocument(companyId, evidenceId);
  }

  /** Lectura única del documento, siempre acotada a una empresa. */
  private async readDocument(
    companyId: string,
    evidenceId: string,
  ): Promise<DownloadedEcfDgiiDocument> {
    // Búsqueda acotada por empresa: un identificador de otra empresa se comporta
    // igual que uno inexistente (no se filtra su existencia).
    const evidence = await this.prisma.ecfEvidence.findFirst({
      where: { id: evidenceId, companyId },
      select: {
        storageRef: true,
        fileName: true,
        mimeType: true,
        sha256: true,
      },
    });
    if (!evidence) {
      throw new NotFoundException("ECF_DGII_DOCUMENT_NOT_FOUND");
    }

    let buffer: Buffer;
    try {
      buffer = await this.storage.read(evidence.storageRef);
    } catch {
      // El registro existe pero el archivo no: se informa como no encontrado sin
      // exponer rutas internas ni el error del sistema de archivos.
      throw new NotFoundException("ECF_DGII_DOCUMENT_FILE_MISSING");
    }

    return {
      fileName: evidence.fileName ?? "documento",
      mimeType: evidence.mimeType ?? "application/octet-stream",
      buffer,
      sha256: evidence.sha256,
    };
  }
}
