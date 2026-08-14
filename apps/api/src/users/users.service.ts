import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CompanyMemberRole, CompanyMemberStatus, Prisma } from '@prisma/client';
import { CreateUserDto } from './dto/create-user.dto';
import { SignWorkContractDto } from './dto/sign-work-contract.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { AiEditWorkContractDto } from './dto/ai-edit-work-contract.dto';
import * as bcrypt from 'bcryptjs';
import { SelfUpdateUserDto } from './dto/self-update-user.dto';
import { ConfigService } from '@nestjs/config';
import { requireTenant, type TenantUser } from '../auth/tenant-context';
import { LicenseService } from '../license/license.service';

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly licenses: LicenseService,
  ) {}

  private normalizeEmail(value: string) {
    return value.trim().toLowerCase();
  }

  private normalizeOptionalString(value: unknown) {
    if (typeof value !== 'string') return undefined;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : undefined;
  }

  private hasValue<T>(value: T | null | undefined): value is T {
    return value !== undefined && value !== null;
  }

  private async getOpenAiRuntimeConfig() {
    const envKey = (this.config.get<string>('OPENAI_API_KEY') ?? process.env.OPENAI_API_KEY ?? '').trim();
    const envModel = (this.config.get<string>('OPENAI_MODEL') ?? process.env.OPENAI_MODEL ?? '').trim();

    let appConfig: { openAiApiKey: string | null; openAiModel: string | null; companyName: string | null } | null = null;
    try {
      appConfig = await this.prisma.appConfig.findUnique({
        where: { id: 'global' },
        select: { openAiApiKey: true, openAiModel: true, companyName: true }
      });
    } catch {
      // ignore missing table/rows, fallback to env vars only
    }

    const apiKey = envKey.length > 0 ? envKey : (appConfig?.openAiApiKey ?? '').trim();
    const model = envModel.length > 0
      ? envModel
      : ((appConfig?.openAiModel ?? '').trim() || 'gpt-4o-mini');
    const companyName = (appConfig?.companyName ?? '').trim();
    return { apiKey, model, companyName };
  }

  private getOpenAiModelCandidates(preferredModel: string) {
    const autoCandidatesEnv = (process.env.OPENAI_MODEL_CANDIDATES ?? '').trim();
    const autoCandidates = autoCandidatesEnv.length > 0
      ? autoCandidatesEnv
          .split(',')
          .map((item) => item.trim())
          .filter((item) => item.length > 0)
      : ['gpt-5', 'gpt-4.1', 'gpt-4o', 'gpt-4o-mini'];

    return [preferredModel, ...autoCandidates].filter(
      (value, index, list) => value.length > 0 && list.indexOf(value) === index,
    );
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

  private normalizeStringMap(value: unknown) {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      return {} as Record<string, string>;
    }

    const entries = Object.entries(value as Record<string, unknown>)
      .map(([key, raw]) => [key.trim(), this.normalizeOptionalString(raw)] as const)
      .filter(([key, raw]) => key.length > 0 && raw);

    return Object.fromEntries(entries) as Record<string, string>;
  }

  private normalizeNullableStringMap(value: unknown) {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      return {} as Record<string, string | null>;
    }

    const output: Record<string, string | null> = {};
    for (const [rawKey, rawValue] of Object.entries(value as Record<string, unknown>)) {
      const key = rawKey.trim();
      if (!key) continue;
      if (rawValue === null) {
        output[key] = null;
        continue;
      }
      const cleaned = this.normalizeOptionalString(rawValue);
      if (cleaned) {
        output[key] = cleaned;
      }
    }
    return output;
  }

  private normalizeBooleanMap(value: unknown) {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      return {} as Record<string, boolean>;
    }

    const output: Record<string, boolean> = {};
    for (const [rawKey, rawValue] of Object.entries(value as Record<string, unknown>)) {
      const key = rawKey.trim();
      if (!key) continue;
      if (typeof rawValue === 'boolean') {
        output[key] = rawValue;
      }
    }
    return output;
  }

  private async assertTargetUserInTenant(requestUser: TenantUser, targetUserId: string) {
    const target = await this.prisma.user.findFirst({
      where: this.targetUserTenantWhere(requestUser, targetUserId),
      select: { id: true },
    });
    if (!target) throw new NotFoundException('User not found');
    return target;
  }

  private targetUserTenantWhere(requestUser: TenantUser, targetUserId: string): Prisma.UserWhereInput {
    const companyId = requireTenant(requestUser);
    return {
      id: targetUserId,
      OR: [
        { companyId },
        {
          companyMemberships: {
            some: {
              companyId,
              status: CompanyMemberStatus.ACTIVE,
            },
          },
        },
      ],
    };
  }

  private parseAiFieldUpdates(value: unknown) {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      return {} as Record<string, unknown>;
    }
    return value as Record<string, unknown>;
  }

  private async requestOpenAiContractEdit(dto: AiEditWorkContractDto) {
    const { apiKey, model, companyName } = await this.getOpenAiRuntimeConfig();
    if (!apiKey) {
      throw new BadRequestException('Configura la API key de OpenAI en Ajustes > Configuración de API.');
    }

    const modelCandidates = this.getOpenAiModelCandidates(model);
    const prompt = JSON.stringify({
      companyName: companyName || 'FULLTECH',
      instruction: dto.instruction,
      currentFields: dto.currentFields ?? {},
      currentClauses: dto.currentClauses,
    });

    for (const candidate of modelCandidates) {
      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: candidate,
          temperature: 0.2,
          messages: [
            {
              role: 'system',
              content:
                'Eres un asistente legal administrativo que ajusta contratos laborales dominicanos. Responde solo JSON válido. No inventes identidades, montos o datos no presentes. Mantén lenguaje formal. Usa fieldUpdates para cambios de campos contractuales y clauseOverrides para reemplazar el texto completo de cláusulas existentes por su key. Si se pide volver al texto base de una cláusula, usa null en esa key. Si se pide eliminar cláusulas especiales o una fecha contractual, usa null en fieldUpdates. No agregues claves fuera de summary, fieldUpdates y clauseOverrides.',
            },
            {
              role: 'user',
              content:
                `${prompt}\n\nDevuelve exactamente este JSON: {"summary":"...","fieldUpdates":{"workContractJobTitle":string|null,"workContractSalary":string|null,"workContractPaymentFrequency":string|null,"workContractPaymentMethod":string|null,"workContractWorkSchedule":string|null,"workContractWorkLocation":string|null,"workContractCustomClauses":string|null,"workContractStartDate":"YYYY-MM-DD"|null},"clauseOverrides":{"clave":string|null}}. Omite en fieldUpdates lo que no cambie. En clauseOverrides usa solo keys existentes en currentClauses.`,
            },
          ],
        }),
      });

      if (!response.ok) {
        continue;
      }

      const payload = (await response.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
      };
      const content = payload.choices?.[0]?.message?.content?.trim();
      if (!content) {
        continue;
      }

      try {
        const parsed = JSON.parse(this.extractJsonObject(content)) as {
          summary?: unknown;
          fieldUpdates?: unknown;
          clauseOverrides?: unknown;
        };

        return {
          selectedModel: candidate,
          summary: this.normalizeOptionalString(parsed.summary) ?? 'Contrato actualizado con IA.',
          fieldUpdates: this.parseAiFieldUpdates(parsed.fieldUpdates),
          clauseOverrides: this.normalizeNullableStringMap(parsed.clauseOverrides),
        };
      } catch {
        continue;
      }
    }

    throw new BadRequestException('No se pudo generar una respuesta válida desde OpenAI para este contrato.');
  }

  private isBirthdayToday(birthDate: Date) {
    const now = new Date();
    return now.getMonth() === birthDate.getMonth() && now.getDate() === birthDate.getDate();
  }

  async generateBirthdayGreeting(userId: string) {
    const user = await this.prisma.user.findFirst({
      where: { id: userId },
      select: { id: true, nombreCompleto: true, fechaNacimiento: true }
    });
    if (!user) throw new NotFoundException('User not found');

    if (!user.fechaNacimiento) {
      return {
        userId: user.id,
        isBirthdayToday: false,
        birthdayKnown: false,
        message: 'No hay fecha de nacimiento registrada para este usuario.'
      };
    }

    const isToday = this.isBirthdayToday(user.fechaNacimiento);
    const birthdayFmt = user.fechaNacimiento.toISOString().slice(0, 10);
    if (!isToday) {
      return {
        userId: user.id,
        isBirthdayToday: false,
        birthdayKnown: true,
        birthday: birthdayFmt,
        message: 'Hoy no es su cumpleaños.'
      };
    }

    const { apiKey, model, companyName } = await this.getOpenAiRuntimeConfig();
    const employeeName = (user.nombreCompleto ?? '').trim() || 'nuestro colaborador';

    if (!apiKey) {
      const from = companyName.length > 0 ? companyName : 'el equipo';
      return {
        userId: user.id,
        isBirthdayToday: true,
        birthdayKnown: true,
        birthday: birthdayFmt,
        source: 'template',
        message: `Feliz cumpleaños, ${employeeName}. ¡Te deseamos un día excelente! — ${from}`
      };
    }

    const prompt = `Genera un mensaje corto (1-2 frases), profesional y cálido en español para felicitar el cumpleaños de un empleado.
Empleado: ${employeeName}
Empresa: ${companyName || 'FULLTECH'}
Requisitos: sin emojis, sin chistes, no menciones IA, no uses información no proporcionada.`;

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: 'Eres un asistente que redacta mensajes corporativos breves.' },
          { role: 'user', content: prompt },
        ],
        temperature: 0.7,
      }),
    });

    if (!response.ok) {
      const from = companyName.length > 0 ? companyName : 'el equipo';
      return {
        userId: user.id,
        isBirthdayToday: true,
        birthdayKnown: true,
        birthday: birthdayFmt,
        source: 'template',
        message: `Feliz cumpleaños, ${employeeName}. ¡Te deseamos un día excelente! — ${from}`,
      };
    }

    const data = (await response.json()) as any;
    const content = (data?.choices?.[0]?.message?.content ?? '').toString().trim();

    return {
      userId: user.id,
      isBirthdayToday: true,
      birthdayKnown: true,
      birthday: birthdayFmt,
      source: 'openai',
      message: content.length > 0 ? content : `Feliz cumpleaños, ${employeeName}.`,
    };
  }

  private isMissingUserTable(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === 'P2021';
    }

    if (typeof error === 'object' && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === 'string' ? value.code : '';
      const message = typeof value.message === 'string' ? value.message : '';
      return code === 'P2021' || message.includes('does not exist in the current database');
    }

    return false;
  }

  private isInconsistentQueryResult(error: unknown) {
    if (typeof error !== 'object' || error === null) return false;
    const value = error as { message?: unknown; name?: unknown };
    const message = typeof value.message === 'string' ? value.message : '';
    const name = typeof value.name === 'string' ? value.name : '';
    return (
      message.includes('Inconsistent query result') ||
      message.includes('got null instead') ||
      name.includes('PrismaClientUnknownRequestError')
    );
  }

  private mapSafeUserRow(row: any) {
    return {
      id: row.id,
      email: row.email,
      nombreCompleto: row.nombreCompleto ?? '',
      telefono: row.telefono ?? '',
      numeroFlota: row.numeroFlota ?? null,
      telefonoFamiliar: row.telefonoFamiliar ?? null,
      cedula: row.cedula ?? null,
      fotoCedulaUrl: row.fotoCedulaUrl ?? null,
      fotoLicenciaUrl: row.fotoLicenciaUrl ?? null,
      fotoPersonalUrl: row.fotoPersonalUrl ?? null,
      workContractSignatureUrl: row.workContractSignatureUrl ?? null,
      workContractSignedAt: row.workContractSignedAt ?? null,
      workContractVersion: row.workContractVersion ?? null,
      workContractJobTitle: row.workContractJobTitle ?? null,
      workContractSalary: row.workContractSalary ?? null,
      workContractPaymentFrequency: row.workContractPaymentFrequency ?? null,
      workContractPaymentMethod: row.workContractPaymentMethod ?? null,
      workContractWorkSchedule: row.workContractWorkSchedule ?? null,
      workContractWorkLocation: row.workContractWorkLocation ?? null,
      workContractClauseOverrides: row.workContractClauseOverrides ?? null,
      workContractCustomClauses: row.workContractCustomClauses ?? null,
      workContractStartDate: row.workContractStartDate ?? null,
      edad: row.edad ?? 0,
      tieneHijos: row.tieneHijos ?? false,
      estaCasado: row.estaCasado ?? false,
      casaPropia: row.casaPropia ?? false,
      vehiculo: row.vehiculo ?? false,
      licenciaConducir: row.licenciaConducir ?? false,
      fechaIngreso: row.fechaIngreso ?? null,
      fechaNacimiento: row.fechaNacimiento ?? null,
      cuentaNominaPreferencial: row.cuentaNominaPreferencial ?? null,
      habilidades: row.habilidades ?? null,
      userPermissions: row.userPermissions ?? {},
      role: row.role ?? 'ASISTENTE',
      blocked: row.blocked ?? false,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    };
  }

  private async findAllSafe(companyId: string) {
    const rows = await this.prisma.$queryRaw<any[]>(Prisma.sql`
      SELECT
        id,
        email,
        COALESCE("nombreCompleto", '') AS "nombreCompleto",
        COALESCE(telefono, '') AS telefono,
        "numeroFlota",
        "telefonoFamiliar",
        cedula,
        "fotoCedulaUrl",
        "fotoLicenciaUrl",
        "fotoPersonalUrl",
        "workContractSignatureUrl",
        "workContractSignedAt",
        "workContractVersion",
        "workContractJobTitle",
        "workContractSalary",
        "workContractPaymentFrequency",
        "workContractPaymentMethod",
        "workContractWorkSchedule",
        "workContractWorkLocation",
        "workContractClauseOverrides",
        "workContractCustomClauses",
        "workContractStartDate",
        COALESCE(edad, 0) AS edad,
        COALESCE("tieneHijos", false) AS "tieneHijos",
        COALESCE("estaCasado", false) AS "estaCasado",
        COALESCE("casaPropia", false) AS "casaPropia",
        COALESCE(vehiculo, false) AS vehiculo,
        COALESCE("licenciaConducir", false) AS "licenciaConducir",
        "fechaIngreso",
        "fechaNacimiento",
        "cuentaNominaPreferencial",
        habilidades,
        COALESCE(user_permissions, '{}'::jsonb) AS "userPermissions",
        COALESCE(role::text, 'ASISTENTE') AS role,
        COALESCE(blocked, false) AS blocked,
        "createdAt",
        "updatedAt"
      FROM users
      WHERE company_id = ${companyId}::uuid
      ORDER BY "createdAt" DESC
    `);

    return rows.map((row) => this.mapSafeUserRow(row));
  }

  private async findByIdSafe(id: string) {
    const rows = await this.prisma.$queryRaw<any[]>(Prisma.sql`
      SELECT
        id,
        email,
        COALESCE("nombreCompleto", '') AS "nombreCompleto",
        COALESCE(telefono, '') AS telefono,
        "numeroFlota",
        "telefonoFamiliar",
        cedula,
        "fotoCedulaUrl",
        "fotoLicenciaUrl",
        "fotoPersonalUrl",
        "workContractSignatureUrl",
        "workContractSignedAt",
        "workContractVersion",
        "workContractJobTitle",
        "workContractSalary",
        "workContractPaymentFrequency",
        "workContractPaymentMethod",
        "workContractWorkSchedule",
        "workContractWorkLocation",
        "workContractClauseOverrides",
        "workContractCustomClauses",
        "workContractStartDate",
        COALESCE(edad, 0) AS edad,
        COALESCE("tieneHijos", false) AS "tieneHijos",
        COALESCE("estaCasado", false) AS "estaCasado",
        COALESCE("casaPropia", false) AS "casaPropia",
        COALESCE(vehiculo, false) AS vehiculo,
        COALESCE("licenciaConducir", false) AS "licenciaConducir",
        "fechaIngreso",
        "fechaNacimiento",
        "cuentaNominaPreferencial",
        habilidades,
        COALESCE(user_permissions, '{}'::jsonb) AS "userPermissions",
        COALESCE(role::text, 'ASISTENTE') AS role,
        COALESCE(blocked, false) AS blocked,
        "createdAt",
        "updatedAt"
      FROM users
      WHERE id::text = ${id}
      LIMIT 1
    `);

    const row = rows[0];
    if (!row) throw new NotFoundException('User not found');
    return this.mapSafeUserRow(row);
  }

  private mapMinimalUser(row: {
    id: string;
    email: string;
    role: string;
    createdAt: Date;
    updatedAt: Date;
  }) {
    return {
      id: row.id,
      email: row.email,
      nombreCompleto: '',
      telefono: '',
      numeroFlota: null,
      telefonoFamiliar: null,
      cedula: null,
      fotoCedulaUrl: null,
      fotoLicenciaUrl: null,
      fotoPersonalUrl: null,
      workContractSignatureUrl: null,
      workContractSignedAt: null,
      workContractVersion: null,
      workContractJobTitle: null,
      workContractSalary: null,
      workContractPaymentFrequency: null,
      workContractPaymentMethod: null,
      workContractWorkSchedule: null,
      workContractWorkLocation: null,
      workContractClauseOverrides: null,
      workContractCustomClauses: null,
      workContractStartDate: null,
      edad: null,
      tieneHijos: false,
      estaCasado: false,
      casaPropia: false,
      vehiculo: false,
      licenciaConducir: false,
      fechaIngreso: null,
      fechaNacimiento: null,
      cuentaNominaPreferencial: null,
      habilidades: null,
      userPermissions: {},
      role: row.role,
      blocked: false,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    };
  }

  async findById(id: string) {
    let user: any;

    try {
      user = await this.prisma.user.findFirst({
        where: { id },
        select: {
          id: true,
          email: true,
          nombreCompleto: true,
          telefono: true,
          numeroFlota: true,
          telefonoFamiliar: true,
          cedula: true,
          fotoCedulaUrl: true,
          fotoLicenciaUrl: true,
          fotoPersonalUrl: true,
          workContractSignatureUrl: true,
          workContractSignedAt: true,
          workContractVersion: true,
          workContractJobTitle: true,
          workContractSalary: true,
          workContractPaymentFrequency: true,
          workContractPaymentMethod: true,
          workContractWorkSchedule: true,
          workContractWorkLocation: true,
          workContractClauseOverrides: true,
          workContractCustomClauses: true,
          workContractStartDate: true,
          edad: true,
          tieneHijos: true,
          estaCasado: true,
          casaPropia: true,
          vehiculo: true,
          licenciaConducir: true,
          fechaIngreso: true,
          fechaNacimiento: true,
          cuentaNominaPreferencial: true,
          habilidades: true,
          userPermissions: true,
          role: true,
          blocked: true,
          createdAt: true,
          updatedAt: true
        }
      });
    } catch (error) {
      if (this.isInconsistentQueryResult(error)) {
        return this.findByIdSafe(id);
      }
      if (!this.isMissingUserTable(error)) throw error;

      const rows = await this.prisma.$queryRaw<
        Array<{ id: string; email: string; role: string; createdAt: Date; updatedAt: Date }>
      >(Prisma.sql`
        SELECT id, email, role, "createdAt", "updatedAt"
        FROM users
        WHERE id::text = ${id}
        LIMIT 1
      `);

      user = rows[0] ? this.mapMinimalUser(rows[0]) : null;
    }

    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async findByIdForTenant(requestUser: TenantUser, id: string) {
    await this.assertTargetUserInTenant(requestUser, id);
    return this.findById(id);
  }

  async generateBirthdayGreetingForTenant(requestUser: TenantUser, userId: string) {
    await this.assertTargetUserInTenant(requestUser, userId);
    return this.generateBirthdayGreeting(userId);
  }

  async applyAiWorkContractEditForTenant(
    requestUser: TenantUser,
    id: string,
    dto: AiEditWorkContractDto,
  ) {
    await this.assertTargetUserInTenant(requestUser, id);
    return this.applyAiWorkContractEdit(id, dto);
  }

  async create(requestUser: TenantUser, dto: CreateUserDto) {
    const companyId = requireTenant(requestUser);
    await this.licenses.assertCanCreateUser(companyId);
    const email = this.normalizeEmail(dto.email);
    const cedula = this.normalizeOptionalString(dto.cedula);
    const numeroFlota =
      this.normalizeOptionalString(dto.numeroFlota) ??
      (cedula ? cedula.replace(/\D/g, '') : undefined);

    if (!this.normalizeOptionalString(dto.nombreCompleto)) {
      throw new BadRequestException('El nombre completo es obligatorio');
    }
    if (!this.normalizeOptionalString(dto.telefono)) {
      throw new BadRequestException('El teléfono es obligatorio');
    }
    if (!numeroFlota) {
      throw new BadRequestException('numeroFlota es obligatorio');
    }

    const exists = await this.prisma.user.findUnique({ where: { email } });
    if (exists) throw new BadRequestException('El correo ya está registrado');

    if (cedula) {
      const cedulaTaken = await this.prisma.user.findUnique({ where: { cedula } });
      if (cedulaTaken) throw new BadRequestException('La cédula ya está registrada');
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);
    const created = await this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          email,
          companyId,
          passwordHash,
          nombreCompleto: dto.nombreCompleto.trim(),
          telefono: dto.telefono.trim(),
          numeroFlota,
          telefonoFamiliar: this.normalizeOptionalString(dto.telefonoFamiliar),
          cedula,
          fotoCedulaUrl: this.normalizeOptionalString(dto.fotoCedulaUrl),
          fotoLicenciaUrl: this.normalizeOptionalString(dto.fotoLicenciaUrl),
          fotoPersonalUrl: this.normalizeOptionalString(dto.fotoPersonalUrl),
          workContractJobTitle: this.normalizeOptionalString(dto.workContractJobTitle),
          workContractSalary: this.normalizeOptionalString(dto.workContractSalary),
          workContractPaymentFrequency: this.normalizeOptionalString(dto.workContractPaymentFrequency),
          workContractPaymentMethod: this.normalizeOptionalString(dto.workContractPaymentMethod),
          workContractWorkSchedule: this.normalizeOptionalString(dto.workContractWorkSchedule),
          workContractWorkLocation: this.normalizeOptionalString(dto.workContractWorkLocation),
          workContractClauseOverrides: (() => {
            const cleaned = this.normalizeStringMap(dto.workContractClauseOverrides);
            return Object.keys(cleaned).length > 0 ? cleaned : undefined;
          })(),
          workContractCustomClauses: this.normalizeOptionalString(dto.workContractCustomClauses),
          workContractStartDate: dto.workContractStartDate ? new Date(dto.workContractStartDate) : undefined,
          edad: dto.edad,
          tieneHijos: dto.tieneHijos ?? false,
          estaCasado: dto.estaCasado ?? false,
          casaPropia: dto.casaPropia ?? false,
          vehiculo: dto.vehiculo ?? false,
          licenciaConducir: dto.licenciaConducir ?? false,
          fechaIngreso: dto.fechaIngreso ? new Date(dto.fechaIngreso) : undefined,
          fechaNacimiento: dto.fechaNacimiento ? new Date(dto.fechaNacimiento) : undefined,
          cuentaNominaPreferencial: this.normalizeOptionalString(dto.cuentaNominaPreferencial),
          habilidades: dto.habilidades,
          userPermissions: this.normalizeBooleanMap(dto.userPermissions),
          role: dto.role,
          blocked: dto.blocked ?? false
        },
        select: { id: true },
      });
      await tx.companyMember.create({
        data: {
          userId: user.id,
          companyId,
          role: CompanyMemberRole.VIEWER,
          status: CompanyMemberStatus.ACTIVE,
          invitedBy: requestUser.id,
          joinedAt: new Date(),
        },
      });
      return user;
    });

    return this.prisma.user.findUniqueOrThrow({
      where: { id: created.id },
      select: {
        id: true,
        email: true,
        nombreCompleto: true,
        telefono: true,
        numeroFlota: true,
        telefonoFamiliar: true,
        cedula: true,
        fotoCedulaUrl: true,
        fotoLicenciaUrl: true,
        fotoPersonalUrl: true,
        workContractSignatureUrl: true,
        workContractSignedAt: true,
        workContractVersion: true,
        workContractJobTitle: true,
        workContractSalary: true,
        workContractPaymentFrequency: true,
        workContractPaymentMethod: true,
        workContractWorkSchedule: true,
        workContractWorkLocation: true,
        workContractClauseOverrides: true,
        workContractCustomClauses: true,
        workContractStartDate: true,
        edad: true,
        tieneHijos: true,
        estaCasado: true,
        casaPropia: true,
        vehiculo: true,
        licenciaConducir: true,
        fechaIngreso: true,
        fechaNacimiento: true,
        cuentaNominaPreferencial: true,
        habilidades: true,
        userPermissions: true,
        role: true,
        blocked: true,
        createdAt: true,
        updatedAt: true
      }
    });
  }

  findAll(requestUser: TenantUser) {
    const companyId = requireTenant(requestUser);
    return this.prisma.user.findMany({
      where: { companyId },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        email: true,
        nombreCompleto: true,
        telefono: true,
        numeroFlota: true,
        telefonoFamiliar: true,
        cedula: true,
        fotoCedulaUrl: true,
        fotoLicenciaUrl: true,
        fotoPersonalUrl: true,
        workContractSignatureUrl: true,
        workContractSignedAt: true,
        workContractVersion: true,
        workContractJobTitle: true,
        workContractSalary: true,
        workContractPaymentFrequency: true,
        workContractPaymentMethod: true,
        workContractWorkSchedule: true,
        workContractWorkLocation: true,
        workContractClauseOverrides: true,
        workContractCustomClauses: true,
        workContractStartDate: true,
        edad: true,
        tieneHijos: true,
        estaCasado: true,
        casaPropia: true,
        vehiculo: true,
        licenciaConducir: true,
        fechaIngreso: true,
        fechaNacimiento: true,
        cuentaNominaPreferencial: true,
        habilidades: true,
        userPermissions: true,
        role: true,
        blocked: true,
        createdAt: true,
        updatedAt: true
      }
    }).catch(async (error) => {
      if (this.isInconsistentQueryResult(error)) {
        // eslint-disable-next-line no-console
        console.error('[users.findAll] Prisma inconsistent query result; falling back to raw SQL', {
          message: error instanceof Error ? error.message : String(error)
        });
        return this.findAllSafe(companyId);
      }

      // eslint-disable-next-line no-console
      console.error('[users.findAll] Prisma error', {
        message: error instanceof Error ? error.message : String(error),
        name: (error as any)?.name,
      });

      if (!this.isMissingUserTable(error)) throw error;
      const rows = await this.prisma.$queryRaw<
        Array<{ id: string; email: string; role: string; createdAt: Date; updatedAt: Date }>
      >(Prisma.sql`
        SELECT id, email, role, "createdAt", "updatedAt"
        FROM users
        WHERE company_id = ${companyId}::uuid
        ORDER BY "createdAt" DESC
      `);
      return rows.map((row) => this.mapMinimalUser(row));
    });
  }

  async signWorkContract(userId: string, dto: SignWorkContractDto) {
    const signatureUrl = this.normalizeOptionalString(dto.signatureUrl);
    const version = this.normalizeOptionalString(dto.version);

    if (!signatureUrl) throw new BadRequestException('Firma inválida');
    if (!version) throw new BadRequestException('Versión inválida');

    const existing = await this.prisma.user.findFirst({
      where: { id: userId },
      select: {
        id: true,
        workContractSignatureUrl: true,
        workContractSignedAt: true,
        workContractVersion: true,
      },
    });
    if (!existing) throw new NotFoundException('User not found');

    const alreadySignedSameVersion =
      existing.workContractSignedAt != null &&
      (existing.workContractSignatureUrl ?? '').trim().length > 0 &&
      (existing.workContractVersion ?? '').trim() === version;

    if (alreadySignedSameVersion) {
      throw new BadRequestException('Este contrato ya fue firmado');
    }

    await this.prisma.user.update({
      where: { id: userId },
      data: {
        workContractSignatureUrl: signatureUrl,
        workContractSignedAt: new Date(),
        workContractVersion: version,
      },
      select: { id: true }
    });

    return this.findById(userId);
  }

  async update(requestUser: TenantUser, id: string, dto: UpdateUserDto) {
    await this.assertTargetUserInTenant(requestUser, id);
    const existing = await this.prisma.user.findFirst({ where: this.targetUserTenantWhere(requestUser, id) });
    if (!existing) throw new NotFoundException('User not found');

    const existingNumeroFlota = ((existing as any).numeroFlota ?? '').toString().trim();

    const nextEmail = this.hasValue(dto.email) ? this.normalizeEmail(dto.email) : undefined;
    const nextCedula = this.hasValue(dto.cedula) ? this.normalizeOptionalString(dto.cedula) : undefined;

    if (nextEmail && nextEmail !== existing.email) {
      const emailTaken = await this.prisma.user.findUnique({ where: { email: nextEmail } });
      if (emailTaken) throw new BadRequestException('Email already in use');
    }

    if (nextCedula && nextCedula !== existing.cedula) {
      const cedulaTaken = await this.prisma.user.findUnique({ where: { cedula: nextCedula } });
      if (cedulaTaken) throw new BadRequestException('La cédula ya está registrada');
    }

    const passwordHash = this.hasValue(dto.password) ? await bcrypt.hash(dto.password, 10) : undefined;

    const data: Prisma.UserUpdateInput = {};
    if (nextEmail !== undefined) data.email = nextEmail;
    if (passwordHash !== undefined) data.passwordHash = passwordHash;
    if (this.hasValue(dto.nombreCompleto)) data.nombreCompleto = dto.nombreCompleto.trim();
    if (this.hasValue(dto.telefono)) data.telefono = dto.telefono.trim();
    if (this.hasValue(dto.numeroFlota)) data.numeroFlota = dto.numeroFlota.trim();
    if (this.hasValue(dto.telefonoFamiliar)) data.telefonoFamiliar = this.normalizeOptionalString(dto.telefonoFamiliar) ?? null;
    if (dto.cedula !== undefined) data.cedula = nextCedula ?? null;
    if (this.hasValue(dto.fotoCedulaUrl)) data.fotoCedulaUrl = this.normalizeOptionalString(dto.fotoCedulaUrl) ?? null;
    if (this.hasValue(dto.fotoLicenciaUrl)) data.fotoLicenciaUrl = this.normalizeOptionalString(dto.fotoLicenciaUrl) ?? null;
    if (this.hasValue(dto.fotoPersonalUrl)) data.fotoPersonalUrl = this.normalizeOptionalString(dto.fotoPersonalUrl) ?? null;
    if (dto.workContractJobTitle !== undefined) data.workContractJobTitle = this.normalizeOptionalString(dto.workContractJobTitle) ?? null;
    if (dto.workContractSalary !== undefined) data.workContractSalary = this.normalizeOptionalString(dto.workContractSalary) ?? null;
    if (dto.workContractPaymentFrequency !== undefined) data.workContractPaymentFrequency = this.normalizeOptionalString(dto.workContractPaymentFrequency) ?? null;
    if (dto.workContractPaymentMethod !== undefined) data.workContractPaymentMethod = this.normalizeOptionalString(dto.workContractPaymentMethod) ?? null;
    if (dto.workContractWorkSchedule !== undefined) data.workContractWorkSchedule = this.normalizeOptionalString(dto.workContractWorkSchedule) ?? null;
    if (dto.workContractWorkLocation !== undefined) data.workContractWorkLocation = this.normalizeOptionalString(dto.workContractWorkLocation) ?? null;
    if (dto.workContractClauseOverrides !== undefined) {
      const cleaned = this.normalizeStringMap(dto.workContractClauseOverrides);
      data.workContractClauseOverrides = Object.keys(cleaned).length > 0 ? cleaned as Prisma.InputJsonValue : Prisma.DbNull;
    }
    if (dto.workContractCustomClauses !== undefined) data.workContractCustomClauses = this.normalizeOptionalString(dto.workContractCustomClauses) ?? null;
    if (dto.workContractStartDate !== undefined) data.workContractStartDate = dto.workContractStartDate ? new Date(dto.workContractStartDate) : null;
    if (this.hasValue(dto.edad)) data.edad = dto.edad;
    if (this.hasValue(dto.tieneHijos)) data.tieneHijos = dto.tieneHijos;
    if (this.hasValue(dto.estaCasado)) data.estaCasado = dto.estaCasado;
    if (this.hasValue(dto.casaPropia)) data.casaPropia = dto.casaPropia;
    if (this.hasValue(dto.vehiculo)) data.vehiculo = dto.vehiculo;
    if (this.hasValue(dto.licenciaConducir)) data.licenciaConducir = dto.licenciaConducir;
    if (this.hasValue(dto.fechaIngreso)) data.fechaIngreso = new Date(dto.fechaIngreso);
    if (this.hasValue(dto.fechaNacimiento)) data.fechaNacimiento = new Date(dto.fechaNacimiento);
    if (this.hasValue(dto.cuentaNominaPreferencial)) {
      data.cuentaNominaPreferencial = this.normalizeOptionalString(dto.cuentaNominaPreferencial) ?? null;
    }
    if (this.hasValue(dto.habilidades)) data.habilidades = dto.habilidades as any;
    if (this.hasValue(dto.userPermissions)) {
      data.userPermissions = this.normalizeBooleanMap(dto.userPermissions) as Prisma.InputJsonValue;
    }
    if (this.hasValue(dto.role)) data.role = dto.role;
    if (this.hasValue(dto.blocked)) data.blocked = dto.blocked;

    if (Object.keys(data).length === 0) {
      return this.findById(id);
    }

    // Enforce numeroFlota when editing users that don't have it yet.
    if (existingNumeroFlota.length === 0 && (data as any).numeroFlota === undefined) {
      throw new BadRequestException('numeroFlota es obligatorio');
    }

    await this.prisma.user.update({
      where: { id },
      data,
      select: { id: true }
    });

    return this.findById(id);
  }

  async updatePermissions(requestUser: TenantUser, id: string, permissions: Record<string, boolean>) {
    await this.assertTargetUserInTenant(requestUser, id);
    const existing = await this.prisma.user.findFirst({
      where: this.targetUserTenantWhere(requestUser, id),
      select: { id: true, role: true },
    });
    if (!existing) throw new NotFoundException('User not found');
    if (existing.role === 'ADMIN') {
      throw new BadRequestException('El administrador mantiene todos los permisos.');
    }

    await this.prisma.user.update({
      where: { id },
      data: {
        userPermissions: this.normalizeBooleanMap(permissions) as Prisma.InputJsonValue,
      },
      select: { id: true },
    });

    return this.findById(id);
  }

  async applyAiWorkContractEdit(id: string, dto: AiEditWorkContractDto) {
    const user = await this.findById(id);
    const allowedClauseKeys = new Set(
      dto.currentClauses
        .map((clause) => clause.key.trim())
        .filter((key) => key.length > 0),
    );
    if (allowedClauseKeys.size === 0) {
      throw new BadRequestException('No se recibieron cláusulas actuales para editar.');
    }

    const aiResult = await this.requestOpenAiContractEdit(dto);
    const fieldUpdates = aiResult.fieldUpdates;
    const existingOverrides = this.normalizeStringMap(user.workContractClauseOverrides);
    const nextOverrides = { ...existingOverrides };

    for (const [key, value] of Object.entries(aiResult.clauseOverrides)) {
      if (!allowedClauseKeys.has(key)) continue;
      if (value === null) {
        delete nextOverrides[key];
        continue;
      }
      const cleaned = this.normalizeOptionalString(value);
      if (cleaned) {
        nextOverrides[key] = cleaned;
      }
    }

    const data: Prisma.UserUpdateInput = {};
    const assignStringField = (field: keyof Prisma.UserUpdateInput, rawValue: unknown) => {
      if (rawValue === undefined) return;
      (data as Record<string, unknown>)[field as string] = rawValue === null
        ? null
        : this.normalizeOptionalString(rawValue) ?? null;
    };

    assignStringField('workContractJobTitle', fieldUpdates.workContractJobTitle);
    assignStringField('workContractSalary', fieldUpdates.workContractSalary);
    assignStringField('workContractPaymentFrequency', fieldUpdates.workContractPaymentFrequency);
    assignStringField('workContractPaymentMethod', fieldUpdates.workContractPaymentMethod);
    assignStringField('workContractWorkSchedule', fieldUpdates.workContractWorkSchedule);
    assignStringField('workContractWorkLocation', fieldUpdates.workContractWorkLocation);
    assignStringField('workContractCustomClauses', fieldUpdates.workContractCustomClauses);

    if (Object.prototype.hasOwnProperty.call(fieldUpdates, 'workContractStartDate')) {
      const rawDate = fieldUpdates.workContractStartDate;
      if (rawDate === null) {
        data.workContractStartDate = null;
      } else {
        const value = this.normalizeOptionalString(rawDate);
        data.workContractStartDate = value ? new Date(value) : null;
      }
    }

    data.workContractClauseOverrides = Object.keys(nextOverrides).length > 0
      ? nextOverrides as Prisma.InputJsonValue
      : Prisma.DbNull;

    await this.prisma.user.update({
      where: { id },
      data,
      select: { id: true },
    });

    return {
      source: 'openai',
      selectedModel: aiResult.selectedModel,
      summary: aiResult.summary,
      user: await this.findById(id),
    };
  }

  async updateSelf(id: string, dto: SelfUpdateUserDto) {
    const existing = await this.prisma.user.findFirst({ where: { id } });
    if (!existing) throw new NotFoundException('User not found');

    const nextEmail = this.hasValue(dto.email) ? this.normalizeEmail(dto.email) : undefined;

    if (nextEmail && nextEmail !== existing.email) {
      const emailTaken = await this.prisma.user.findUnique({ where: { email: nextEmail } });
      if (emailTaken) throw new BadRequestException('Email already in use');
    }

    const passwordHash = this.hasValue(dto.password) ? await bcrypt.hash(dto.password, 10) : undefined;

    const data: Prisma.UserUpdateInput = {};
    if (nextEmail !== undefined) data.email = nextEmail;
    if (this.hasValue(dto.nombreCompleto)) data.nombreCompleto = dto.nombreCompleto.trim();
    if (this.hasValue(dto.telefono)) data.telefono = dto.telefono.trim();
    if (this.hasValue(dto.fotoPersonalUrl)) data.fotoPersonalUrl = this.normalizeOptionalString(dto.fotoPersonalUrl) ?? null;
    if (passwordHash !== undefined) data.passwordHash = passwordHash;

    if (Object.keys(data).length === 0) {
      return this.findById(id);
    }

    await this.prisma.user.update({
      where: { id },
      data,
      select: { id: true }
    });

    return this.findById(id);
  }

  async setBlocked(requestUser: TenantUser, id: string, blocked?: boolean) {
    await this.assertTargetUserInTenant(requestUser, id);
    const existing = await this.prisma.user.findFirst({ where: this.targetUserTenantWhere(requestUser, id) });
    if (!existing) throw new NotFoundException('User not found');
    const next = blocked ?? !existing.blocked;

    return this.prisma.user.update({
      where: { id },
      data: { blocked: next },
      select: {
        id: true,
        email: true,
        role: true,
        blocked: true,
        updatedAt: true
      }
    });
  }

  async remove(requestUser: TenantUser, id: string) {
    await this.assertTargetUserInTenant(requestUser, id);
    const existing = await this.prisma.user.findFirst({ where: this.targetUserTenantWhere(requestUser, id) });
    if (!existing) throw new NotFoundException('User not found');
    const companyId = requireTenant(requestUser);
    await this.prisma.$transaction(async (tx) => {
      await tx.companyMember.deleteMany({ where: { userId: id, companyId } });

      const remainingMembership = await tx.companyMember.findFirst({
        where: {
          userId: id,
          status: CompanyMemberStatus.ACTIVE,
        },
        select: { companyId: true },
        orderBy: { createdAt: 'asc' },
      });

      await tx.user.update({
        where: { id },
        data: remainingMembership
          ? {
              companyId:
                existing.companyId === companyId
                  ? remainingMembership.companyId
                  : existing.companyId,
            }
          : { blocked: true, companyId: null },
        select: { id: true },
      });
    });
    return { ok: true };
  }
}
