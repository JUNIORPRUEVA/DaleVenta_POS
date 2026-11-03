import { Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join, resolve, sep } from "node:path";

export type StoredEcfDgiiDocument = {
  /** Ruta relativa interna. Nunca se devuelve al cliente. */
  storageRef: string;
  size: number;
};

/**
 * Almacenamiento privado del expediente DGII.
 *
 * Abstracción deliberada: hoy escribe en disco con una ruta no pública; en
 * producción puede sustituirse por el almacenamiento privado del proyecto (S3/R2
 * con bucket privado) sin tocar los servicios que la consumen.
 *
 * Garantías:
 * - La ruta la construye el servidor (`<companyId>/<año>/<uuid>.<ext>`); el
 *   nombre original del archivo **nunca** participa.
 * - `read` resuelve la ruta y verifica que siga dentro de la raíz: bloquea
 *   `../` y rutas absolutas inyectadas.
 * - Los archivos se crean con permisos de propietario (0o600) cuando el sistema
 *   de archivos lo soporta.
 */
@Injectable()
export class EcfDgiiDocumentStorage {
  /** Raíz privada. Configurable por entorno para UAT y producción. */
  private root(): string {
    const configured = process.env.ECF_DGII_STORAGE_DIR?.trim();
    return resolve(configured && configured.length > 0
      ? configured
      : join(process.cwd(), "storage", "ecf-dgii"));
  }

  async save(input: {
    companyId: string;
    buffer: Buffer;
    extension: string;
  }): Promise<StoredEcfDgiiDocument> {
    const year = String(new Date().getUTCFullYear());
    const fileName = `${randomUUID()}.${input.extension}`;
    const absoluteDir = join(this.root(), input.companyId, year);
    await mkdir(absoluteDir, { recursive: true });
    const absolutePath = join(absoluteDir, fileName);
    await writeFile(absolutePath, input.buffer, { mode: 0o600 });
    return {
      storageRef: `${input.companyId}/${year}/${fileName}`,
      size: input.buffer.length,
    };
  }

  async read(storageRef: string): Promise<Buffer> {
    const root = this.root();
    const absolutePath = resolve(root, storageRef);
    // Defensa contra path traversal: la ruta resuelta debe quedar DENTRO de la
    // raíz. Se compara con el separador para no aceptar prefijos hermanos.
    if (!absolutePath.startsWith(root + sep)) {
      throw new Error("ECF_DGII_STORAGE_PATH_INVALID");
    }
    return readFile(absolutePath);
  }
}
