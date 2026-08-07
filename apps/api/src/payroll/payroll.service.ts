import { BadRequestException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import {
  CompanyMemberRole,
  CompanyMemberStatus,
  PayrollEntryType,
  PayrollPaymentStatus,
  PayrollPeriodStatus,
  PayrollServiceCommissionStatus,
  Prisma,
  Role,
  ServiceOrderType,
} from '@prisma/client';
import { EvolutionWhatsAppService } from '../notifications/evolution-whatsapp.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { MyPayrollHistoryQueryDto } from './dto/my-payroll-history-query.dto';
import { AddPayrollEntryDto } from './dto/payroll-entry.dto';
import { SchedulePayrollWhatsappDto, SendPayrollWhatsappDto } from './dto/send-payroll-whatsapp.dto';
import { UpsertPayrollConfigDto } from './dto/upsert-payroll-config.dto';
import { UpsertPayrollEmployeeDto } from './dto/upsert-payroll-employee.dto';

@Injectable()
export class PayrollService {
  private readonly logger = new Logger(PayrollService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly evolutionWhatsApp: EvolutionWhatsAppService,
    private readonly notifications: NotificationsService,
  ) {}

  async resolveCompanyOwnerId(fallbackUserId: string, companyId?: string | null) {
    const tenantId = companyId?.trim();
    if (!tenantId) return fallbackUserId;
    const owner = await this.prisma.companyMember.findFirst({
      where: {
        companyId: tenantId,
        status: CompanyMemberStatus.ACTIVE,
        role: CompanyMemberRole.OWNER,
      },
      orderBy: { createdAt: 'asc' },
      select: { userId: true },
    });
    return owner?.userId ?? fallbackUserId;
  }

  private async companyIdForOwner(ownerId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: ownerId },
      select: { companyId: true },
    });
    if (!user?.companyId) {
      throw new BadRequestException('El usuario no tiene empresa activa para nómina.');
    }
    return user.companyId;
  }

  async listPeriods(ownerId: string) {
    return this.prisma.payrollPeriod.findMany({
      where: { ownerId },
      orderBy: { startDate: 'desc' },
    });
  }

  async getPeriodById(ownerId: string, periodId: string) {
    return this.prisma.payrollPeriod.findFirst({ where: { ownerId, id: periodId } });
  }

  async hasOverlappingOpenPeriod(ownerId: string, start: Date, end: Date) {
    const count = await this.prisma.payrollPeriod.count({
      where: {
        ownerId,
        status: PayrollPeriodStatus.OPEN,
        startDate: { lte: end },
        endDate: { gte: start },
      },
    });
    return count > 0;
  }

  async createPeriod(ownerId: string, start: Date, end: Date, title: string) {
    const companyId = await this.companyIdForOwner(ownerId);
    if (end < start) {
      throw new BadRequestException('La fecha final no puede ser menor que la inicial');
    }

    const overlap = await this.hasOverlappingOpenPeriod(ownerId, start, end);
    if (overlap) {
      throw new BadRequestException('Ya existe una quincena abierta que se solapa con esas fechas');
    }

    return this.prisma.payrollPeriod.create({
      data: {
        companyId,
        ownerId,
        title: title.trim(),
        startDate: start,
        endDate: end,
        status: PayrollPeriodStatus.OPEN,
      },
    });
  }

  async ensureCurrentOpenPeriod(ownerId: string) {
    const companyId = await this.companyIdForOwner(ownerId);
    const now = new Date();
    const expectedStart = this.periodStartFor(now);
    const expectedEnd = this.periodEndFor(now);

    const openPeriods = await this.prisma.payrollPeriod.findMany({
      where: { ownerId, status: PayrollPeriodStatus.OPEN },
      orderBy: { startDate: 'desc' },
    });

    for (const period of openPeriods) {
      if (this.isSameDay(period.startDate, expectedStart) && this.isSameDay(period.endDate, expectedEnd)) {
        return period;
      }
    }

    if (openPeriods.length) {
      await this.prisma.payrollPeriod.updateMany({
        where: { ownerId, status: PayrollPeriodStatus.OPEN },
        data: { status: PayrollPeriodStatus.CLOSED },
      });
    }

    return this.prisma.payrollPeriod.create({
      data: {
        companyId,
        ownerId,
        title: this.periodTitle(now),
        startDate: expectedStart,
        endDate: expectedEnd,
        status: PayrollPeriodStatus.OPEN,
      },
    });
  }

  async closePeriod(ownerId: string, periodId: string) {
    const result = await this.prisma.payrollPeriod.updateMany({
      where: { ownerId, id: periodId },
      data: { status: PayrollPeriodStatus.CLOSED },
    });

    if (result.count === 0) {
      throw new NotFoundException('Quincena no encontrada');
    }
  }

  async createNextOpenPeriod(ownerId: string, closedPeriodId: string) {
    const companyId = await this.companyIdForOwner(ownerId);
    const closed = await this.getPeriodById(ownerId, closedPeriodId);
    if (!closed) {
      throw new NotFoundException('Quincena no encontrada');
    }

    const nextBase = new Date(closed.endDate.getTime() + 24 * 60 * 60 * 1000);
    const start = this.periodStartFor(nextBase);
    const end = this.periodEndFor(nextBase);
    const title = this.periodTitle(nextBase);

    const existing = await this.prisma.payrollPeriod.findFirst({
      where: {
        ownerId,
        status: PayrollPeriodStatus.OPEN,
        startDate: start,
        endDate: end,
      },
    });

    if (existing) {
      return existing;
    }

    return this.prisma.payrollPeriod.create({
      data: {
        companyId,
        ownerId,
        title,
        startDate: start,
        endDate: end,
        status: PayrollPeriodStatus.OPEN,
      },
    });
  }

  async listEmployees(ownerId: string, activeOnly = true) {
    return this.prisma.payrollEmployee.findMany({
      where: {
        ownerId,
        ...(activeOnly ? { activo: true } : {}),
      },
      orderBy: { nombre: 'asc' },
    });
  }

  async getEmployeeById(ownerId: string, employeeId: string) {
    return this.prisma.payrollEmployee.findFirst({
      where: { ownerId, id: employeeId },
    });
  }

  async upsertEmployee(ownerId: string, dto: UpsertPayrollEmployeeDto) {
    const companyId = await this.companyIdForOwner(ownerId);
    const nombre = dto.nombre.trim();
    if (!nombre) {
      throw new BadRequestException('El nombre del empleado es obligatorio');
    }

    const linkedUser = dto.id
      ? await this.prisma.user.findUnique({
          where: { id: dto.id },
          select: { id: true },
        })
      : null;

    const existing = dto.id
      ? await this.prisma.payrollEmployee.findFirst({
          where: { ownerId, id: dto.id },
          select: {
            id: true,
            seguroLeyMonto: true,
            seguroLeyMontoLocked: true,
          },
        })
      : null;

    const requestedSeguroLeyMonto = Math.max(0, dto.seguroLeyMonto ?? 0);
    const currentSeguroLeyMonto = this.toNumber(existing?.seguroLeyMonto);
    const canEditSeguroLeyMonto =
      !existing?.seguroLeyMontoLocked || dto.allowSeguroLeyMontoEdit === true;
    const seguroLeyMonto = existing && !canEditSeguroLeyMonto
      ? currentSeguroLeyMonto
      : requestedSeguroLeyMonto;

    if (
      existing?.seguroLeyMontoLocked &&
      dto.allowSeguroLeyMontoEdit !== true &&
      requestedSeguroLeyMonto !== currentSeguroLeyMonto
    ) {
      throw new BadRequestException('El seguro de ley ya esta fijado. Usa la opcion de editar para modificarlo.');
    }

    const payload = {
      companyId,
      ownerId,
      userId: linkedUser?.id,
      nombre,
      telefono: dto.telefono?.trim() ? dto.telefono.trim() : null,
      puesto: dto.puesto?.trim() ? dto.puesto.trim() : null,
      salarioBaseQuincenal: new Prisma.Decimal(dto.salarioBaseQuincenal ?? 0),
      cuotaMinima: new Prisma.Decimal(dto.cuotaMinima ?? 0),
      seguroLeyMonto: new Prisma.Decimal(seguroLeyMonto),
      seguroLeyMontoLocked: true,
      activo: dto.activo ?? true,
    };

    if (dto.id) {
      if (existing) {
        return this.prisma.payrollEmployee.update({
          where: { id: dto.id },
          data: payload,
        });
      }

      if (!linkedUser) {
        throw new BadRequestException('El usuario seleccionado no existe');
      }

      return this.prisma.payrollEmployee.create({
        data: {
          id: dto.id,
          ...payload,
        },
      });
    }

    return this.prisma.payrollEmployee.create({ data: payload });
  }

  async deleteEmployee(ownerId: string, employeeId: string) {
    const employee = await this.prisma.payrollEmployee.findFirst({
      where: { ownerId, id: employeeId },
      select: { id: true, activo: true },
    });

    if (!employee) {
      throw new NotFoundException('Empleado de nómina no encontrado');
    }

    if (!employee.activo) {
      return;
    }

    await this.prisma.payrollEmployee.update({
      where: { id: employeeId },
      data: { activo: false },
    });
  }

  async getEmployeeConfig(ownerId: string, periodId: string, employeeId: string) {
    return this.prisma.payrollEmployeeConfig.findFirst({
      where: { ownerId, periodId, employeeId },
    });
  }

  async upsertEmployeeConfig(ownerId: string, dto: UpsertPayrollConfigDto) {
    const companyId = await this.companyIdForOwner(ownerId);
    return this.prisma.payrollEmployeeConfig.upsert({
      where: {
        ownerId_periodId_employeeId: {
          ownerId,
          periodId: dto.periodId,
          employeeId: dto.employeeId,
        },
      },
      create: {
        companyId,
        ownerId,
        periodId: dto.periodId,
        employeeId: dto.employeeId,
        baseSalary: new Prisma.Decimal(dto.baseSalary),
        includeCommissions: dto.includeCommissions,
        notes: dto.notes?.trim() ? dto.notes.trim() : null,
      },
      update: {
        baseSalary: new Prisma.Decimal(dto.baseSalary),
        includeCommissions: dto.includeCommissions,
        notes: dto.notes?.trim() ? dto.notes.trim() : null,
      },
    });
  }

  async listEntries(ownerId: string, periodId: string, employeeId: string) {
    return this.prisma.payrollEntry.findMany({
      where: { ownerId, periodId, employeeId },
      orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
    });
  }

  async addEntry(ownerId: string, dto: AddPayrollEntryDto) {
    const companyId = await this.companyIdForOwner(ownerId);
    await this.assertPayrollEditable(ownerId, dto.periodId, dto.employeeId);
    const [employee, config] = await Promise.all([
      this.getEmployeeById(ownerId, dto.employeeId),
      this.getEmployeeConfig(ownerId, dto.periodId, dto.employeeId),
    ]);
    if (!employee) {
      throw new NotFoundException('Empleado de nomina no encontrado');
    }

    const quantity = dto.cantidad == null ? null : Math.max(0, dto.cantidad);
    const resolvedAmount = this.resolvePayrollEntryAmount({
      type: dto.type,
      requestedAmount: dto.amount,
      quantity: quantity ?? 1,
      employee,
      config,
    });

    const entry = await this.prisma.payrollEntry.create({
      data: {
        companyId,
        ownerId,
        periodId: dto.periodId,
        employeeId: dto.employeeId,
        date: new Date(dto.date),
        type: dto.type,
        concept: dto.concept.trim(),
        amount: new Prisma.Decimal(resolvedAmount),
        cantidad: quantity == null ? null : new Prisma.Decimal(quantity),
      },
    });

    if (dto.notifyUser === true) {
      void this.notifyPayrollEntryIfNeeded(ownerId, entry.id).catch((error) => {
        this.logger.error(
          `Payroll entry notification dispatch failed entry=${entry.id} employee=${entry.employeeId}`,
          error instanceof Error ? error.stack : undefined,
        );
      });
    }
    return entry;
  }

  async sendPayrollWhatsapp(ownerId: string, dto: SendPayrollWhatsappDto) {
    const [employee, period] = await Promise.all([
      this.prisma.payrollEmployee.findFirst({
        where: { ownerId, id: dto.employeeId },
        include: {
          user: {
            select: { id: true, telefono: true, nombreCompleto: true },
          },
        },
      }),
      this.prisma.payrollPeriod.findFirst({
        where: { ownerId, id: dto.periodId },
        select: { id: true, title: true, startDate: true, endDate: true },
      }),
    ]);

    if (!employee) {
      throw new NotFoundException('Empleado de nómina no encontrado');
    }
    if (!period) {
      throw new NotFoundException('Quincena no encontrada');
    }

    const notificationConfig = await this.getPayrollNotificationConfig();
    const targets = this.buildPayrollEmployeeNotificationTargets(employee);
    if (targets.length === 0) {
      throw new BadRequestException('No hay un teléfono válido para enviar la nómina por WhatsApp');
    }

    const bytes = this.parsePdfBase64(dto.pdfBase64);
    const fileName = (dto.fileName ?? '').trim() || this.buildPayrollPdfFileName(employee.nombre, period.title);
    const customMessage = (dto.messageText ?? '').trim();
    const message = customMessage || this.buildPayrollPdfMessage(
      employee.nombre,
      period.title,
      notificationConfig.companyName,
    );
    let delivery: { label: string; rawPhone: string; normalizedPhone: string };
    try {
      delivery = await this.sendPayrollWhatsappWithFallback({
        targets,
        employeeId: employee.id,
        periodId: period.id,
        message,
        bytes,
        fileName,
        caption: `Nomina correspondiente a ${period.title}.`,
      });
    } catch (error) {
      const reason = this.describePayrollWhatsappError(error);
      this.logger.warn(
        `Payroll PDF WhatsApp failed employee=${employee.id} period=${period.id}: ${reason}`,
      );
      throw new BadRequestException(`No se pudo enviar la nomina por WhatsApp: ${reason}`);
    }

    this.logger.log(
      `Payroll PDF WhatsApp sent employee=${employee.id} period=${period.id} to=${delivery.normalizedPhone || delivery.rawPhone} target=${delivery.label}`,
    );

    return {
      ok: true,
      normalizedPhone: delivery.normalizedPhone,
      target: delivery.label,
      sentAt: new Date().toISOString(),
    };
  }

  async schedulePayrollWhatsapp(ownerId: string, dto: SchedulePayrollWhatsappDto) {
    const scheduledFor = new Date(dto.scheduledFor);
    if (Number.isNaN(scheduledFor.getTime())) {
      throw new BadRequestException('La fecha programada no es valida');
    }
    if (scheduledFor.getTime() <= Date.now() + 30_000) {
      throw new BadRequestException('La fecha y hora programada debe ser futura');
    }

    const [employee, period] = await Promise.all([
      this.prisma.payrollEmployee.findFirst({
        where: { ownerId, id: dto.employeeId },
        include: {
          user: {
            select: { id: true, telefono: true, nombreCompleto: true },
          },
        },
      }),
      this.prisma.payrollPeriod.findFirst({
        where: { ownerId, id: dto.periodId },
        select: { id: true, title: true, startDate: true, endDate: true },
      }),
    ]);

    if (!employee) {
      throw new NotFoundException('Empleado de nomina no encontrado');
    }
    if (!period) {
      throw new NotFoundException('Quincena no encontrada');
    }

    const notificationConfig = await this.getPayrollNotificationConfig();
    const targets = this.buildPayrollEmployeeNotificationTargets(employee);
    if (targets.length === 0) {
      throw new BadRequestException('No hay un telefono valido para enviar la nomina por WhatsApp');
    }

    const bytes = this.parsePdfBase64(dto.pdfBase64);
    const fileName = (dto.fileName ?? '').trim() || this.buildPayrollPdfFileName(employee.nombre, period.title);
    const customMessage = (dto.messageText ?? '').trim();
    const message = customMessage || this.buildPayrollPdfMessage(
      employee.nombre,
      period.title,
      notificationConfig.companyName,
    );
    const target = targets[0];

    const job = await this.notifications.enqueueWhatsAppDocument({
      toNumber: target.rawPhone,
      messageText: message,
      fileName,
      bytes,
      mimeType: 'application/pdf',
      dedupeKey: `payroll-pdf:${ownerId}:${period.id}:${employee.id}:${scheduledFor.toISOString()}`,
      payload: {
        kind: 'payroll_pdf',
        ownerId,
        employeeId: employee.id,
        periodId: period.id,
        scheduledFor: scheduledFor.toISOString(),
        target: target.label,
      },
      recipientUserId: employee.userId ?? null,
      scheduledFor,
      allowOutsideBusinessHours: true,
    });

    return {
      ok: true,
      queuedId: job.id,
      scheduledFor: scheduledFor.toISOString(),
      normalizedPhone: target.normalizedPhone,
      target: target.label,
    };
  }

  async listPendingServiceCommissionRequests(ownerId: string) {
    return this.prisma.payrollServiceCommissionRequest.findMany({
      where: {
        ownerId,
        status: PayrollServiceCommissionStatus.PENDING,
      },
      include: {
        employee: {
          select: { id: true, nombre: true, userId: true },
        },
        technicianUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
        serviceOrder: {
          include: {
            client: {
              select: { id: true, nombre: true },
            },
          },
        },
      },
      orderBy: [{ finalizedAt: 'desc' }, { createdAt: 'desc' }],
    });
  }

  async queueServiceCommissionRequest(params: {
    ownerId: string;
    serviceOrderId: string;
    quotationId?: string | null;
    recipientUserId: string;
    technicianUserId?: string | null;
    createdByUserId?: string | null;
    serviceType: ServiceOrderType;
    finalizedAt: Date;
    profitAfterExpense: number;
    commissionRate: number;
    commissionAmount: number;
    concept: string;
  }) {
    const companyId = await this.companyIdForOwner(params.ownerId);
    const recipientUserId = params.recipientUserId.trim();
    if (!recipientUserId) {
      return null;
    }

    const technicianUserId =
      params.technicianUserId?.trim() || recipientUserId;

    const roundedAmount = this.round2(params.commissionAmount);
    if (roundedAmount <= 0) {
      return null;
    }

    return this.prisma.$transaction(async (tx) => {
      const employee = await this.ensurePayrollEmployeeLinkedToUser(
        tx,
        params.ownerId,
        recipientUserId,
      );

      const existing = await tx.payrollServiceCommissionRequest.findUnique({
        where: { serviceOrderId: params.serviceOrderId },
        select: { id: true, status: true },
      });

      if (existing?.status === PayrollServiceCommissionStatus.APPROVED) {
        return tx.payrollServiceCommissionRequest.findUnique({
          where: { id: existing.id },
          include: {
            employee: {
              select: { id: true, nombre: true, userId: true },
            },
            technicianUser: {
              select: { id: true, nombreCompleto: true, role: true },
            },
            serviceOrder: {
              include: {
                client: {
                  select: { id: true, nombre: true },
                },
              },
            },
          },
        });
      }

      const payload = {
        companyId,
        ownerId: params.ownerId,
        quotationId: params.quotationId ?? null,
        employeeId: employee.id,
        technicianUserId,
        createdByUserId: params.createdByUserId ?? null,
        reviewedByUserId: null,
        periodId: null,
        payrollEntryId: null,
        serviceType: params.serviceType,
        finalizedAt: params.finalizedAt,
        profitAfterExpense: new Prisma.Decimal(this.round2(params.profitAfterExpense)),
        commissionRate: new Prisma.Decimal(params.commissionRate),
        commissionAmount: new Prisma.Decimal(roundedAmount),
        concept: params.concept.trim(),
        status: PayrollServiceCommissionStatus.PENDING,
        reviewNote: null,
        approvedAt: null,
        rejectedAt: null,
      };

      if (existing) {
        return tx.payrollServiceCommissionRequest.update({
          where: { id: existing.id },
          data: payload,
          include: {
            employee: {
              select: { id: true, nombre: true, userId: true },
            },
            technicianUser: {
              select: { id: true, nombreCompleto: true, role: true },
            },
            serviceOrder: {
              include: {
                client: {
                  select: { id: true, nombre: true },
                },
              },
            },
          },
        });
      }

      return tx.payrollServiceCommissionRequest.create({
        data: {
          ...payload,
          serviceOrderId: params.serviceOrderId,
        },
        include: {
          employee: {
            select: { id: true, nombre: true, userId: true },
          },
          technicianUser: {
            select: { id: true, nombreCompleto: true, role: true },
          },
          serviceOrder: {
            include: {
              client: {
                select: { id: true, nombre: true },
              },
            },
          },
        },
      });
    });
  }

  async approveServiceCommissionRequest(
    ownerId: string,
    requestId: string,
    reviewedByUserId: string,
  ) {
    const period = await this.ensureCurrentOpenPeriod(ownerId);
    const companyId = await this.companyIdForOwner(ownerId);

    return this.prisma.$transaction(async (tx) => {
      const request = await tx.payrollServiceCommissionRequest.findFirst({
        where: { ownerId, id: requestId },
        include: {
          employee: {
            select: { id: true, nombre: true, userId: true },
          },
          technicianUser: {
            select: { id: true, nombreCompleto: true, role: true },
          },
          serviceOrder: {
            include: {
              client: {
                select: { id: true, nombre: true },
              },
            },
          },
        },
      });

      if (!request) {
        throw new NotFoundException('Comisión de servicio pendiente no encontrada');
      }

      if (request.status === PayrollServiceCommissionStatus.APPROVED) {
        return request;
      }

      if (request.status !== PayrollServiceCommissionStatus.PENDING) {
        throw new BadRequestException('Solo se pueden aprobar comisiones de servicio pendientes');
      }

      const entry = await tx.payrollEntry.create({
        data: {
          companyId,
          ownerId,
          periodId: period.id,
          employeeId: request.employeeId,
          date: request.finalizedAt,
          type: PayrollEntryType.COMISION_SERVICIO,
          concept: request.concept,
          amount: request.commissionAmount,
        },
      });

      return tx.payrollServiceCommissionRequest.update({
        where: { id: request.id },
        data: {
          status: PayrollServiceCommissionStatus.APPROVED,
          reviewedByUserId,
          approvedAt: new Date(),
          rejectedAt: null,
          reviewNote: null,
          periodId: period.id,
          payrollEntryId: entry.id,
        },
        include: {
          employee: {
            select: { id: true, nombre: true, userId: true },
          },
          technicianUser: {
            select: { id: true, nombreCompleto: true, role: true },
          },
          serviceOrder: {
            include: {
              client: {
                select: { id: true, nombre: true },
              },
            },
          },
        },
      });
    });
  }

  async rejectServiceCommissionRequest(
    ownerId: string,
    requestId: string,
    reviewedByUserId: string,
    note?: string,
  ) {
    const existing = await this.prisma.payrollServiceCommissionRequest.findFirst({
      where: { ownerId, id: requestId },
      select: { id: true, status: true },
    });

    if (!existing) {
      throw new NotFoundException('Comisión de servicio pendiente no encontrada');
    }

    if (existing.status !== PayrollServiceCommissionStatus.PENDING) {
      throw new BadRequestException('Solo se pueden rechazar comisiones de servicio pendientes');
    }

    return this.prisma.payrollServiceCommissionRequest.update({
      where: { id: existing.id },
      data: {
        status: PayrollServiceCommissionStatus.REJECTED,
        reviewedByUserId,
        rejectedAt: new Date(),
        approvedAt: null,
        reviewNote: note?.trim() || null,
        payrollEntryId: null,
        periodId: null,
      },
      include: {
        employee: {
          select: { id: true, nombre: true, userId: true },
        },
        technicianUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
        serviceOrder: {
          include: {
            client: {
              select: { id: true, nombre: true },
            },
          },
        },
      },
    });
  }

  async deleteEntry(ownerId: string, entryId: string) {
    const entry = await this.prisma.payrollEntry.findFirst({
      where: { ownerId, id: entryId },
      select: { id: true, periodId: true, employeeId: true },
    });
    if (!entry) {
      throw new NotFoundException('Movimiento no encontrado');
    }
    await this.assertPayrollEditable(ownerId, entry.periodId, entry.employeeId);
    const result = await this.prisma.payrollEntry.deleteMany({ where: { ownerId, id: entryId } });
    if (result.count === 0) {
      throw new NotFoundException('Movimiento no encontrado');
    }
  }

  async listPaymentStatuses(ownerId: string, periodId: string, employeeId?: string) {
    return this.prisma.payrollEmployeePeriodStatus.findMany({
      where: {
        ownerId,
        periodId,
        ...(employeeId ? { employeeId } : {}),
      },
      orderBy: [{ paidAt: 'desc' }, { updatedAt: 'desc' }],
    });
  }

  async getPaymentStatus(ownerId: string, periodId: string, employeeId: string) {
    const status = await this.prisma.payrollEmployeePeriodStatus.findUnique({
      where: {
        ownerId_periodId_employeeId: {
          ownerId,
          periodId,
          employeeId,
        },
      },
    });
    return status ?? {
      id: '',
      ownerId,
      periodId,
      employeeId,
      status: PayrollPaymentStatus.DRAFT,
      paidAt: null,
      paidById: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    };
  }

  async markPayrollPaid(ownerId: string, periodId: string, employeeId: string, paidById: string) {
    const companyId = await this.companyIdForOwner(ownerId);
    const [period, employee] = await Promise.all([
      this.getPeriodById(ownerId, periodId),
      this.getEmployeeById(ownerId, employeeId),
    ]);
    if (!period) throw new NotFoundException('Quincena no encontrada');
    if (!employee) throw new NotFoundException('Empleado de nomina no encontrado');

    const now = new Date();
    return this.prisma.payrollEmployeePeriodStatus.upsert({
      where: {
        ownerId_periodId_employeeId: {
          ownerId,
          periodId,
          employeeId,
        },
      },
      create: {
        companyId,
        ownerId,
        periodId,
        employeeId,
        status: PayrollPaymentStatus.PAID,
        paidAt: now,
        paidById,
      },
      update: {
        status: PayrollPaymentStatus.PAID,
        paidAt: now,
        paidById,
      },
    });
  }

  async computeTotals(ownerId: string, periodId: string, employeeId: string) {
    const [employee, config, entries] = await Promise.all([
      this.getEmployeeById(ownerId, employeeId),
      this.getEmployeeConfig(ownerId, periodId, employeeId),
      this.listEntries(ownerId, periodId, employeeId),
    ]);

    const period = await this.getPeriodById(ownerId, periodId);

    const base = this.toNumber(
      config?.baseSalary ??
        (employee as { salarioBaseQuincenal?: Prisma.Decimal | number | string | null } | null)
          ?.salarioBaseQuincenal,
    );
    let manualServiceCommissions = 0;
    let manualSalesCommissions = 0;
    let bonuses = 0;
    let otherAdditions = 0;
    let holidayWorked = 0;
    let absences = 0;
    let late = 0;
    let advances = 0;
    let otherDeductions = 0;

    for (const entry of entries) {
      const amount = this.toNumber(entry.amount);
      switch (entry.type) {
        case PayrollEntryType.COMISION_SERVICIO:
          if (amount >= 0) manualServiceCommissions += amount;
          break;
        case PayrollEntryType.COMISION_VENTAS:
          if (amount >= 0) manualSalesCommissions += amount;
          break;
        case PayrollEntryType.BONIFICACION:
        case PayrollEntryType.PAGO_COMBUSTIBLE:
          if (amount >= 0) bonuses += amount;
          break;
        case PayrollEntryType.FERIADO_TRABAJADO:
          holidayWorked += Math.abs(amount);
          break;
        case PayrollEntryType.AUSENCIA:
          absences += Math.abs(amount);
          break;
        case PayrollEntryType.TARDE:
          late += Math.abs(amount);
          break;
        case PayrollEntryType.ADELANTO:
          advances += Math.abs(amount);
          break;
        case PayrollEntryType.DESCUENTO:
          otherDeductions += Math.abs(amount);
          break;
        case PayrollEntryType.OTRO:
          if (amount >= 0) {
            otherAdditions += amount;
          } else {
            otherDeductions += Math.abs(amount);
          }
          break;
      }
    }

    const hasLinkedSalesUser = Boolean(await this.resolveSalesUserIdForEmployee(ownerId, employee));
    const automaticSales = await this.computeAutomaticSalesCommissionForEmployee({
      ownerId,
      employee,
      includeCommissions: config?.includeCommissions ?? true,
      periodStart: period?.startDate,
      periodEnd: period?.endDate,
    });

    const commissions = manualSalesCommissions + automaticSales.commissionAmount;

    const seguroLey = Math.max(
      0,
      this.toNumber(
        (employee as { seguroLeyMonto?: Prisma.Decimal | number | string | null } | null)
          ?.seguroLeyMonto,
      ),
    );
    const additions = commissions + manualServiceCommissions + bonuses + holidayWorked + otherAdditions;
    const deductions = absences + late + advances + otherDeductions + seguroLey;
    const total = base + additions - deductions;

    return {
      baseSalary: base,
      commissions,
      serviceCommissions: manualServiceCommissions,
      bonuses,
      holidayWorked,
      otherAdditions,
      absences,
      late,
      advances,
      otherDeductions,
      seguroLey,
      salesCommissionAuto: automaticSales.commissionAmount,
      salesAmountThisPeriod: automaticSales.salesAmount,
      salesGoal: automaticSales.goal,
      salesGoalReached: automaticSales.goalReached,
      salesCommissionSource: manualSalesCommissions > 0
        ? automaticSales.commissionAmount > 0
          ? 'mixed'
          : 'manual'
        : automaticSales.usedAutomatic
          ? 'automatic'
          : hasLinkedSalesUser
            ? 'automatic_disabled'
            : 'manual',
      additions,
      deductions,
      total,
      employeeExists: Boolean(employee),
    };
  }

  async computePeriodTotalAllEmployees(ownerId: string, periodId: string) {
    const employees = await this.listEmployees(ownerId, true);
    let total = 0;
    for (const employee of employees) {
      const t = await this.computeTotals(ownerId, periodId, employee.id);
      total += t.total;
    }
    return total;
  }

  async listPayrollHistoryByEmployee(
    ownerId: string,
    employeeId: string,
    query?: MyPayrollHistoryQueryDto,
  ) {
    const periods = await this.listPeriods(ownerId);
    const employee = await this.getEmployeeById(ownerId, employeeId);
    const history: Array<Record<string, unknown>> = [];
    const normalizedStatus = (query?.status ?? '').trim().toUpperCase();
    const periodSearch = (query?.period ?? '').trim().toLowerCase();
    const fromDate = query?.from ? new Date(query.from) : null;
    const toDate = query?.to ? new Date(query.to) : null;

    if (fromDate && Number.isNaN(fromDate.getTime())) {
      throw new BadRequestException('El filtro "from" no es una fecha valida');
    }
    if (toDate && Number.isNaN(toDate.getTime())) {
      throw new BadRequestException('El filtro "to" no es una fecha valida');
    }

    for (const period of periods) {
      if (query?.periodId && period.id !== query.periodId) {
        continue;
      }
      if (periodSearch && !period.title.toLowerCase().includes(periodSearch)) {
        continue;
      }

      const [entries, config] = await Promise.all([
        this.listEntries(ownerId, period.id, employeeId),
        this.getEmployeeConfig(ownerId, period.id, employeeId),
      ]);

      const paymentStatus = await this.prisma.payrollEmployeePeriodStatus.findUnique({
        where: {
          ownerId_periodId_employeeId: {
            ownerId,
            periodId: period.id,
            employeeId,
          },
        },
      });

      const paymentStatusValue = paymentStatus?.status ?? PayrollPaymentStatus.DRAFT;
      const paymentDate = paymentStatus?.paidAt ?? null;

      if (normalizedStatus && paymentStatusValue !== normalizedStatus) {
        continue;
      }

      const compareDate = paymentDate ?? period.endDate;
      if (fromDate && compareDate < fromDate) {
        continue;
      }
      if (toDate) {
        const toEnd = new Date(toDate);
        toEnd.setHours(23, 59, 59, 999);
        if (compareDate > toEnd) {
          continue;
        }
      }

      const automaticSales = await this.computeAutomaticSalesCommissionForEmployee({
        ownerId,
        employee,
        includeCommissions: config?.includeCommissions ?? true,
        periodStart: period.startDate,
        periodEnd: period.endDate,
      });

      const hasData =
        Boolean(config) ||
        entries.length > 0 ||
        automaticSales.salesAmount > 0 ||
        automaticSales.commissionAmount > 0 ||
        paymentStatus != null;
      if (!hasData) continue;

      const baseSalary = this.toNumber(
        config?.baseSalary ??
            (employee as
                    | { salarioBaseQuincenal?: Prisma.Decimal | number | string | null }
                    | null)
                ?.salarioBaseQuincenal,
      );
      const seguroLey = Math.max(
        0,
        this.toNumber(
          (employee as { seguroLeyMonto?: Prisma.Decimal | number | string | null } | null)
            ?.seguroLeyMonto,
        ),
      );
          let manualServiceCommissions = 0;
      let manualSalesCommissions = 0;
      let overtimeAmount = 0;
      let bonusesAmount = 0;
      let holidayWorkedAmount = 0;
      let deductionsAmount = 0;
      let benefitsAmount = 0;

      for (const entry of entries) {
        const amount = this.toNumber(entry.amount);
        switch (entry.type) {
          case PayrollEntryType.COMISION_SERVICIO:
            if (amount >= 0) manualServiceCommissions += amount;
            break;
          case PayrollEntryType.COMISION_VENTAS:
            if (amount >= 0) manualSalesCommissions += amount;
            break;
          case PayrollEntryType.BONIFICACION:
          case PayrollEntryType.PAGO_COMBUSTIBLE:
            bonusesAmount += amount;
            break;
          case PayrollEntryType.FERIADO_TRABAJADO:
            holidayWorkedAmount += Math.abs(amount);
            break;
          case PayrollEntryType.AUSENCIA:
          case PayrollEntryType.TARDE:
          case PayrollEntryType.ADELANTO:
          case PayrollEntryType.DESCUENTO:
            deductionsAmount += Math.abs(amount);
            break;
          case PayrollEntryType.OTRO:
            if (amount >= 0) {
              benefitsAmount += amount;
            } else {
              deductionsAmount += Math.abs(amount);
            }
            break;
        }
      }

      const commissionFromSales =
        manualSalesCommissions + automaticSales.commissionAmount;

      benefitsAmount += manualServiceCommissions;

      const additions = commissionFromSales + overtimeAmount + bonusesAmount + holidayWorkedAmount + benefitsAmount;
      const grossTotal = baseSalary + additions;
      const totalDeductions = deductionsAmount + seguroLey;
      const netTotal = grossTotal - totalDeductions;
      const totalCommissions = commissionFromSales + manualServiceCommissions;
      const createdAt = paymentStatus?.createdAt ?? period.createdAt;
      const updatedAt = paymentStatus?.updatedAt ?? period.updatedAt;
      const paymentId = paymentStatus?.id ?? `draft_${period.id}_${employeeId}`;

      history.push({
        entry_id: entries.length > 0 ? entries[0].id : `period_${period.id}`,
        source_employee_id: employeeId,
        payment_id: paymentId,
        employee_name: employee?.nombre ?? '',
        period_id: period.id,
        period_title: period.title,
        period_start: period.startDate.toISOString(),
        period_end: period.endDate.toISOString(),
        period_status: period.status,
        payment_status: paymentStatusValue,
        payment_date: paymentDate?.toISOString() ?? null,
        salary_base: baseSalary,
        commissions: totalCommissions,
        bonuses: bonusesAmount,
        discounts: totalDeductions,
        overtime: overtimeAmount,
        total_gross: grossTotal,
        total_discounted: totalDeductions,
        total_net_paid: netTotal,
        payment_method: null,
        reference: null,
        notes: null,
        created_at: createdAt.toISOString(),
        updated_at: updatedAt.toISOString(),
        base_salary: baseSalary,
        commission_from_sales: commissionFromSales,
        overtime_amount: overtimeAmount,
        bonuses_amount: bonusesAmount,
        holiday_worked_amount: holidayWorkedAmount,
        deductions_amount: totalDeductions,
        benefits_amount: benefitsAmount,
        gross_total: grossTotal,
        net_total: netTotal,
        seguro_ley_monto: seguroLey,
        sales_commission_auto: automaticSales.commissionAmount,
        sales_amount_this_period: automaticSales.salesAmount,
        sales_goal: automaticSales.goal,
        sales_goal_reached: automaticSales.goalReached,
      });
    }

    history.sort((a, b) => {
      const right = new Date((b['period_end'] ?? '').toString()).getTime();
      const left = new Date((a['period_end'] ?? '').toString()).getTime();
      return right - left;
    });

    return history;
  }

  async listMyPayrollHistory(
    ownerId: string,
    userId: string,
    query?: MyPayrollHistoryQueryDto,
  ) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, nombreCompleto: true, telefono: true },
    });

    if (!user) {
      return [] as Array<Record<string, unknown>>;
    }

    const direct = await this.prisma.payrollEmployee.findMany({
      where: {
        ownerId,
        OR: [{ id: user.id }, { userId: user.id }],
      },
      select: { id: true },
    });

    const fallback = await this.prisma.payrollEmployee.findMany({
      where: {
        ownerId,
        nombre: user.nombreCompleto,
        ...(user.telefono.trim().length > 0 ? { telefono: user.telefono } : {}),
      },
      select: { id: true },
    });

    const employeeIds = new Set<string>([user.id]);
    for (const item of direct) employeeIds.add(item.id);
    for (const item of fallback) employeeIds.add(item.id);

    const allHistory: Array<Record<string, unknown>> = [];
    for (const employeeId of employeeIds) {
      const rows = await this.listPayrollHistoryByEmployee(ownerId, employeeId, query);
      allHistory.push(...rows);
    }

    const unique = new Map<string, Record<string, unknown>>();
    for (const row of allHistory) {
      const key = [
        (row['source_employee_id'] ?? '').toString(),
        (row['period_id'] ?? '').toString(),
        (row['payment_id'] ?? '').toString(),
      ].join(':');
      if (!key) continue;
      if (!unique.has(key)) unique.set(key, row);
    }

    const result = [...unique.values()];
    result.sort((a, b) => {
      const right = new Date((b['period_end'] ?? '').toString()).getTime();
      const left = new Date((a['period_end'] ?? '').toString()).getTime();
      return right - left;
    });

    return result;
  }

  async getCuotaMinimaForUser(ownerId: string, userId: string) {
    const byId = await this.prisma.payrollEmployee.findFirst({
      where: {
        ownerId,
        activo: true,
        OR: [{ id: userId }, { userId }],
      },
      select: { cuotaMinima: true },
    });

    if (byId) {
      return this.toNumber(byId.cuotaMinima);
    }

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { nombreCompleto: true, telefono: true },
    });

    if (!user) {
      return 0;
    }

    const legacyMatches = await this.prisma.payrollEmployee.findMany({
      where: {
        ownerId,
        activo: true,
        nombre: user.nombreCompleto,
        ...(user.telefono.trim().length > 0 ? { telefono: user.telefono } : {}),
      },
      select: { cuotaMinima: true },
      take: 2,
    });

    if (legacyMatches.length == 1) {
      return this.toNumber(legacyMatches[0].cuotaMinima);
    }

    return 0;
  }

  private async assertPayrollEditable(ownerId: string, periodId: string, employeeId: string) {
    const status = await this.prisma.payrollEmployeePeriodStatus.findUnique({
      where: {
        ownerId_periodId_employeeId: {
          ownerId,
          periodId,
          employeeId,
        },
      },
      select: { status: true },
    });

    if (status?.status === PayrollPaymentStatus.PAID) {
      throw new BadRequestException('Esta nomina fue pagada y no se puede editar.');
    }
  }

  private resolvePayrollEntryAmount(params: {
    type: PayrollEntryType;
    requestedAmount?: number;
    quantity: number;
    employee: {
      salarioBaseQuincenal?: Prisma.Decimal | number | string | null;
    } | null;
    config?: { baseSalary?: Prisma.Decimal | number | string | null } | null;
  }) {
    const quantity = params.quantity > 0 ? params.quantity : 1;
    const dailySalary = this.computeDominicanDailySalary(
      params.config?.baseSalary ?? params.employee?.salarioBaseQuincenal,
    );
    const manualAmount = params.requestedAmount;

    if (params.type === PayrollEntryType.AUSENCIA) {
      return -this.round2(dailySalary * quantity);
    }

    if (params.type === PayrollEntryType.FERIADO_TRABAJADO) {
      return this.round2(dailySalary * quantity);
    }

    if (manualAmount == null || !Number.isFinite(manualAmount)) {
      throw new BadRequestException('El monto es obligatorio para este tipo de movimiento');
    }

    return this.round2(manualAmount);
  }

  private computeDominicanDailySalary(baseSalary: Prisma.Decimal | number | string | null | undefined) {
    const biweeklySalary = Math.max(0, this.toNumber(baseSalary));
    if (biweeklySalary <= 0) return 0;
    const monthlySalary = biweeklySalary * 2;
    return monthlySalary / 23.83;
  }

  private async computeAutomaticSalesCommissionForEmployee(params: {
    ownerId: string;
    employee: {
      id: string;
      nombre: string;
      telefono: string | null;
      cuotaMinima: Prisma.Decimal | number | string | null;
    } | null;
    includeCommissions: boolean;
    periodStart?: Date;
    periodEnd?: Date;
  }) {
    const { ownerId, employee, includeCommissions, periodStart, periodEnd } = params;

    const goal = Math.max(0, this.toNumber(employee?.cuotaMinima));

    if (!includeCommissions || !periodStart || !periodEnd || !employee) {
      return {
        usedAutomatic: false,
        salesAmount: 0,
        commissionAmount: 0,
        goal,
        goalReached: false,
      };
    }

    const salesUserId = await this.resolveSalesUserIdForEmployee(ownerId, employee);
    if (!salesUserId) {
      return {
        usedAutomatic: false,
        salesAmount: 0,
        commissionAmount: 0,
        goal,
        goalReached: false,
      };
    }

    const start = new Date(periodStart.getFullYear(), periodStart.getMonth(), periodStart.getDate(), 0, 0, 0, 0);
    const endExclusive = new Date(periodEnd.getFullYear(), periodEnd.getMonth(), periodEnd.getDate() + 1, 0, 0, 0, 0);

    const aggregate = await this.prisma.sale.aggregate({
      where: {
        userId: salesUserId,
        isDeleted: false,
        saleDate: {
          gte: start,
          lt: endExclusive,
        },
      },
      _sum: {
        totalProfit: true,
        commissionAmount: true,
      },
    });

    const salesAmount = this.toNumber(aggregate._sum.totalProfit);
    const totalSalesCommission = this.toNumber(aggregate._sum.commissionAmount);
    const goalReached = goal <= 0 ? salesAmount > 0 : salesAmount >= goal;

    return {
      usedAutomatic: true,
      salesAmount,
      commissionAmount: goalReached ? totalSalesCommission : 0,
      goal,
      goalReached,
    };
  }

  private async resolveSalesUserIdForEmployee(
    ownerId: string,
    employee: { id: string; userId?: string | null; nombre: string; telefono: string | null } | null,
  ) {
    if (!employee) return null;

    if ((employee.userId ?? '').trim().length > 0) {
      return employee.userId ?? null;
    }

    const userById = await this.prisma.user.findUnique({
      where: { id: employee.id },
      select: { id: true },
    });
    if (userById) return userById.id;

    const trimmedName = employee.nombre.trim();
    if (!trimmedName) return null;

    const phone = (employee.telefono ?? '').trim();
    const users = await this.prisma.user.findMany({
      where: {
        nombreCompleto: trimmedName,
        ...(phone.length > 0 ? { telefono: phone } : {}),
      },
      select: { id: true },
      take: 2,
    });

    if (users.length === 1) return users[0].id;

    const payrollUsers = await this.prisma.payrollEmployee.findMany({
      where: {
        ownerId,
        nombre: trimmedName,
        ...(phone.length > 0 ? { telefono: phone } : {}),
      },
      select: { id: true },
      take: 2,
    });

    if (payrollUsers.length === 1) {
      const userByPayrollId = await this.prisma.user.findUnique({
        where: { id: payrollUsers[0].id },
        select: { id: true },
      });
      return userByPayrollId?.id ?? null;
    }

    return null;
  }

  private async ensurePayrollEmployeeLinkedToUser(
    tx: Prisma.TransactionClient,
    ownerId: string,
    userId: string,
  ) {
    const companyId = await this.companyIdForOwner(ownerId);
    const existing = await tx.payrollEmployee.findFirst({
      where: {
        ownerId,
        OR: [{ userId }, { id: userId }],
      },
      orderBy: { createdAt: 'asc' },
    });

    if (existing) {
      if (existing.userId === userId) {
        return existing;
      }

      return tx.payrollEmployee.update({
        where: { id: existing.id },
        data: { userId },
      });
    }

    const user = await tx.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        nombreCompleto: true,
        telefono: true,
      },
    });

    if (!user) {
      throw new BadRequestException('No se encontró el usuario del técnico para crear el empleado de nómina');
    }

    const roleLabel = user.nombreCompleto.trim() ? 'Colaborador' : 'Usuario';

    return tx.payrollEmployee.create({
      data: {
        companyId,
        id: user.id,
        ownerId,
        userId: user.id,
        nombre: user.nombreCompleto.trim() || roleLabel,
        telefono: user.telefono.trim() || null,
        puesto: 'Colaborador',
        salarioBaseQuincenal: new Prisma.Decimal(0),
        cuotaMinima: new Prisma.Decimal(0),
        seguroLeyMonto: new Prisma.Decimal(0),
        activo: true,
      },
    });
  }

  private async notifyPayrollEntryIfNeeded(ownerId: string, entryId: string) {
    const entry = await this.prisma.payrollEntry.findFirst({
      where: { ownerId, id: entryId },
      include: {
        employee: {
          include: {
            user: {
              select: { id: true, telefono: true, nombreCompleto: true },
            },
          },
        },
        period: {
          select: { id: true, title: true },
        },
      },
    });

    if (!entry) {
      return;
    }

    if (!this.shouldNotifyEntryType(entry.type)) {
      return;
    }

    const notificationConfig = await this.getPayrollNotificationConfig();
    const targets = this.buildPayrollNotificationTargets(entry.employee, notificationConfig.companyPhone);
    if (targets.length === 0) {
      this.logger.warn(
        `Payroll entry notification skipped employee=${entry.employeeId} entry=${entry.id} reason=no_target_phone`,
      );
      return;
    }

    const message = this.buildPayrollEntryMessage({
      employeeName: entry.employee.nombre,
      periodTitle: entry.period?.title ?? '',
      type: entry.type,
      concept: entry.concept,
      amount: this.toNumber(entry.amount),
      quantity: this.toNumber(entry.cantidad),
      companyName: notificationConfig.companyName,
    });

    try {
      const delivery = await this.sendTextPayrollNotificationWithFallback({
        targets,
        employeeId: entry.employeeId,
        entryId: entry.id,
        message,
      });
      this.logger.log(
        `Payroll entry WhatsApp sent entry=${entry.id} employee=${entry.employeeId} type=${entry.type} to=${delivery.normalizedPhone || delivery.rawPhone} target=${delivery.label}`,
      );
    } catch (error) {
      this.logger.error(
        `Payroll entry notification failed entry=${entry.id} employee=${entry.employeeId} type=${entry.type}`,
        error instanceof Error ? error.stack : undefined,
      );
    }
  }

  private shouldNotifyEntryType(type: PayrollEntryType) {
    return (
      type === PayrollEntryType.ADELANTO ||
      type === PayrollEntryType.BONIFICACION ||
      type === PayrollEntryType.AUSENCIA ||
      type === PayrollEntryType.FERIADO_TRABAJADO
    );
  }

  private buildPayrollNotificationTargets(employee: {
    telefono?: string | null;
    user?: { telefono?: string | null } | null;
  }, companyPhone?: string | null) {
    const candidates = [
      {
        label: 'employee_personal',
        phone: (employee.telefono ?? '').trim(),
      },
      {
        label: 'linked_user',
        phone: (employee.user?.telefono ?? '').trim(),
      },
      {
        label: 'company_config',
        phone: (companyPhone ?? '').trim(),
      },
    ];

    const seen = new Set<string>();
    const targets: Array<{ label: string; rawPhone: string; normalizedPhone: string }> = [];
    for (const candidate of candidates) {
      if (!candidate.phone) continue;
      const normalizedPhone = this.evolutionWhatsApp.normalizeWhatsAppNumber(candidate.phone);
      if (!normalizedPhone || seen.has(normalizedPhone)) continue;
      seen.add(normalizedPhone);
      targets.push({
        label: candidate.label,
        rawPhone: candidate.phone,
        normalizedPhone,
      });
    }

    return targets;
  }

  private buildPayrollEmployeeNotificationTargets(employee: {
    telefono?: string | null;
    user?: { telefono?: string | null } | null;
  }) {
    return this.buildPayrollNotificationTargets(employee, null);
  }

  private buildPayrollEntryMessage(params: {
    employeeName: string;
    periodTitle: string;
    type: PayrollEntryType;
    concept: string;
    amount: number;
    quantity: number;
    companyName?: string;
  }) {
    const employeeName = params.employeeName.trim() || 'colaborador';
    const concept = params.concept.trim();
    const periodTitle = params.periodTitle.trim();
    const quantity = params.quantity > 0 ? params.quantity : 0;
    const amountLabel = this.formatMoney(Math.abs(params.amount));
    const companyName = (params.companyName ?? '').trim();
    const signature = companyName.length > 0 ? `${companyName}
Administración de nómina` : 'Administración de nómina';
    const joinLines = (...lines: Array<string | null>) =>
      lines.filter((line): line is string => Boolean(line && line.trim())).join('\n');

    switch (params.type) {
      case PayrollEntryType.ADELANTO:
        return joinLines(
          `Hola ${employeeName},`,
          `Te informamos que se registró un adelanto de nómina por ${amountLabel}.`,
          concept.length > 0 ? `Concepto registrado: ${concept}.` : null,
          periodTitle.length > 0 ? `Quincena aplicada: ${periodTitle}.` : null,
          'Si tienes alguna duda, por favor comunícate con administración.',
          signature,
        );
      case PayrollEntryType.BONIFICACION:
        return joinLines(
          `Hola ${employeeName},`,
          `Te informamos que se registró una bonificación de nómina por ${amountLabel}.`,
          concept.length > 0 ? `Concepto registrado: ${concept}.` : null,
          periodTitle.length > 0 ? `Quincena aplicada: ${periodTitle}.` : null,
          'Si tienes alguna duda, por favor comunícate con administración.',
          signature,
        );
      case PayrollEntryType.AUSENCIA:
        return joinLines(
          `Hola ${employeeName},`,
          `Te informamos que se registró una ausencia en tu nómina${quantity > 0 ? ` (${this.formatQuantity(quantity)}).` : '.'}`,
          `Monto aplicado: ${amountLabel}.`,
          concept.length > 0 ? `Concepto registrado: ${concept}.` : null,
          periodTitle.length > 0 ? `Quincena aplicada: ${periodTitle}.` : null,
          'Si tienes alguna duda, por favor comunícate con administración.',
          signature,
        );
      case PayrollEntryType.FERIADO_TRABAJADO:
        return joinLines(
          `Hola ${employeeName},`,
          `Te informamos que se registro un feriado trabajado en tu nomina${quantity > 0 ? ` (${this.formatQuantity(quantity)}).` : '.'}`,
          `Monto adicional aplicado: ${amountLabel}.`,
          concept.length > 0 ? `Concepto registrado: ${concept}.` : null,
          periodTitle.length > 0 ? `Quincena aplicada: ${periodTitle}.` : null,
          'Si tienes alguna duda, por favor comunicate con administracion.',
          signature,
        );
      default:
        return '';
    }
  }

  private buildPayrollPdfMessage(employeeName: string, periodTitle: string, companyName?: string) {
    const safeName = employeeName.trim() || 'colaborador';
    const safePeriod = periodTitle.trim();
    const safeCompany = (companyName ?? '').trim();
    return [
      `Hola ${safeName},`,
      safePeriod.length === 0
        ? 'Adjuntamos tu comprobante formal de nómina en PDF.'
        : `Adjuntamos tu comprobante formal de nómina correspondiente a ${safePeriod}.`,
      'Si tienes alguna duda, por favor comunícate con administración.',
      safeCompany.length > 0 ? safeCompany : null,
    ].filter((line): line is string => Boolean(line && line.trim())).join('\n');
  }

  private async getPayrollNotificationConfig() {
    const config = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: { companyName: true, phone: true },
    });

    return {
      companyName: (config?.companyName ?? '').trim(),
      companyPhone: (config?.phone ?? '').trim(),
    };
  }

  private async sendTextPayrollNotificationWithFallback(params: {
    targets: Array<{ label: string; rawPhone: string; normalizedPhone: string }>;
    employeeId: string;
    entryId: string;
    message: string;
  }) {
    let lastError: unknown = null;

    for (const target of params.targets) {
      try {
        await this.evolutionWhatsApp.sendTextMessage({
          toNumber: target.rawPhone,
          message: params.message,
        });
        return target;
      } catch (error) {
        lastError = error;
        this.logger.warn(
          `Payroll entry WhatsApp target failed entry=${params.entryId} employee=${params.employeeId} target=${target.label} to=${target.normalizedPhone}`,
        );
      }
    }

    throw lastError instanceof Error
      ? lastError
      : new Error('No se pudo enviar la notificación de nómina por WhatsApp');
  }

  private async sendPayrollWhatsappWithFallback(params: {
    targets: Array<{ label: string; rawPhone: string; normalizedPhone: string }>;
    employeeId: string;
    periodId: string;
    message: string;
    bytes: Uint8Array;
    fileName: string;
    caption: string;
  }) {
    let lastError: unknown = null;

    for (const target of params.targets) {
      try {
        await this.evolutionWhatsApp.sendTextMessage({
          toNumber: target.rawPhone,
          message: params.message,
        });
        await this.evolutionWhatsApp.sendPdfDocument({
          toNumber: target.rawPhone,
          bytes: params.bytes,
          fileName: params.fileName,
          caption: params.caption,
        });
        return target;
      } catch (error) {
        lastError = error;
        this.logger.warn(
          `Payroll PDF WhatsApp target failed employee=${params.employeeId} period=${params.periodId} target=${target.label} to=${target.normalizedPhone}`,
        );
      }
    }

    throw lastError instanceof Error
      ? lastError
      : new Error('No se pudo enviar la nómina por WhatsApp');
  }

  private describePayrollWhatsappError(error: unknown) {
    if (error instanceof BadRequestException) {
      const response = error.getResponse();
      if (typeof response === 'string' && response.trim()) return response.trim();
      if (response && typeof response === 'object') {
        const message = (response as { message?: unknown }).message;
        if (typeof message === 'string' && message.trim()) return message.trim();
        if (Array.isArray(message)) {
          const first = message.find((item) => typeof item === 'string' && item.trim());
          if (typeof first === 'string') return first.trim();
        }
      }
      return error.message || 'Solicitud invalida para WhatsApp';
    }

    if (error instanceof Error && error.message.trim()) {
      return error.message.trim();
    }

    return 'Evolution API no devolvio una causa legible';
  }

  private buildPayrollPdfFileName(employeeName: string, periodTitle: string) {
    const employeeSlug = this.slugify(employeeName) || 'empleado';
    const periodSlug = this.slugify(periodTitle) || 'quincena';
    return `nomina_${employeeSlug}_${periodSlug}.pdf`;
  }

  private parsePdfBase64(raw: string) {
    const value = (raw ?? '').trim();
    if (!value) {
      throw new BadRequestException('El PDF es obligatorio para enviarlo por WhatsApp');
    }

    const normalized = value.startsWith('data:') ? value.split(',').pop() ?? '' : value;

    try {
      return Uint8Array.from(Buffer.from(normalized, 'base64'));
    } catch {
      throw new BadRequestException('El PDF enviado no tiene un Base64 válido');
    }
  }

  private formatMoney(value: number) {
    return new Intl.NumberFormat('es-DO', {
      style: 'currency',
      currency: 'DOP',
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(Number.isFinite(value) ? value : 0);
  }

  private formatQuantity(value: number) {
    if (Number.isInteger(value)) {
      return `${value} dia${value == 1 ? '' : 's'}`;
    }
    return `${value.toFixed(2)} dias`;
  }

  private slugify(value: string) {
    return value
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '');
  }

  private round2(value: number) {
    return Math.round(value * 100) / 100;
  }

  private toNumber(value: Prisma.Decimal | number | string | null | undefined) {
    if (value == null) return 0;
    if (typeof value === 'number') return value;
    if (typeof value === 'string') {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return Number(value.toString());
  }

  private dateWithClampedDay(year: number, month: number, day: number) {
    const lastDay = new Date(year, month, 0).getDate();
    const safeDay = day > lastDay ? lastDay : day;
    return new Date(year, month - 1, safeDay);
  }

  private periodStartFor(date: Date) {
    const day = date.getDate();
    const year = date.getFullYear();
    const month = date.getMonth() + 1;

    if (day >= 15 && day <= 29) return new Date(year, month - 1, 15);
    if (day >= 30) return this.dateWithClampedDay(year, month, 30);

    const prev = new Date(year, month - 2, 1);
    return this.dateWithClampedDay(prev.getFullYear(), prev.getMonth() + 1, 30);
  }

  private periodEndFor(date: Date) {
    const day = date.getDate();
    const year = date.getFullYear();
    const month = date.getMonth() + 1;

    if (day >= 15 && day <= 29) return this.dateWithClampedDay(year, month, 29);
    if (day >= 30) return new Date(year, month, 14);
    return new Date(year, month - 1, 14);
  }

  private periodTitle(date: Date) {
    const start = this.periodStartFor(date);
    const end = this.periodEndFor(date);
    return this.periodTitleFromRange(start, end);
  }

  private periodTitleFromRange(start: Date, end: Date) {
    const sDay = start.getDate().toString().padStart(2, '0');
    const eDay = end.getDate().toString().padStart(2, '0');
    const month = (end.getMonth() + 1).toString().padStart(2, '0');
    const year = end.getFullYear().toString();
    const quincenaNumber = end.getDate() <= 14 ? 1 : 2;
    return `Quincena ${quincenaNumber} · ${sDay}-${eDay}/${month}/${year}`;
  }

  private isSameDay(left: Date, right: Date) {
    return (
      left.getFullYear() === right.getFullYear() &&
      left.getMonth() === right.getMonth() &&
      left.getDate() === right.getDate()
    );
  }
}
