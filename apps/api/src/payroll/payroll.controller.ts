import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { PayrollPeriodStatus, Role } from '@prisma/client';
import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { CreatePayrollPeriodDto } from './dto/create-payroll-period.dto';
import { AddPayrollEntryDto, PayrollEntriesQueryDto } from './dto/payroll-entry.dto';
import { MyPayrollHistoryQueryDto } from './dto/my-payroll-history-query.dto';
import { MarkPayrollPaidDto, PayrollPaymentStatusQueryDto } from './dto/payroll-payment-status.dto';
import { PayrollTotalsQueryDto } from './dto/payroll-query.dto';
import { OverlapPeriodQueryDto } from './dto/overlap-period-query.dto';
import { ReviewServiceCommissionDto } from './dto/review-service-commission.dto';
import { SchedulePayrollWhatsappDto, SendPayrollWhatsappDto } from './dto/send-payroll-whatsapp.dto';
import { UpsertPayrollConfigDto } from './dto/upsert-payroll-config.dto';
import { UpsertPayrollEmployeeDto } from './dto/upsert-payroll-employee.dto';
import { PayrollService } from './payroll.service';

type JwtUser = {
  id: string;
  role: Role;
  companyId?: string | null;
};

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('payroll')
export class PayrollController {
  constructor(private readonly payroll: PayrollService) {}

  @Get('periods')
  @Roles(Role.ADMIN)
  async listPeriods(@Req() req: Request) {
    const ownerId = await this.ownerIdFrom(req);
    await this.payroll.ensureCurrentOpenPeriod(ownerId);
    const periods = await this.payroll.listPeriods(ownerId);
    return periods.map((item) => this.mapPeriod(item));
  }

  @Get('periods/open-overlap')
  @Roles(Role.ADMIN)
  async hasOverlappingOpenPeriod(@Req() req: Request, @Query() query: OverlapPeriodQueryDto) {
    const ownerId = await this.ownerIdFrom(req);
    const overlaps = await this.payroll.hasOverlappingOpenPeriod(ownerId, new Date(query.start), new Date(query.end));
    return { overlaps };
  }

  @Get('periods/:id')
  @Roles(Role.ADMIN)
  async getPeriodById(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    const period = await this.payroll.getPeriodById(ownerId, id);
    return period ? this.mapPeriod(period) : null;
  }

  @Post('periods')
  @Roles(Role.ADMIN)
  async createPeriod(@Req() req: Request, @Body() dto: CreatePayrollPeriodDto) {
    const ownerId = await this.ownerIdFrom(req);
    const period = await this.payroll.createPeriod(ownerId, new Date(dto.start), new Date(dto.end), dto.title);
    return this.mapPeriod(period);
  }

  @Post('periods/ensure-current-open')
  @Roles(Role.ADMIN)
  async ensureCurrentOpenPeriod(@Req() req: Request) {
    const ownerId = await this.ownerIdFrom(req);
    const period = await this.payroll.ensureCurrentOpenPeriod(ownerId);
    return this.mapPeriod(period);
  }

  @Patch('periods/:id/close')
  @Roles(Role.ADMIN)
  async closePeriod(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    await this.payroll.closePeriod(ownerId, id);
    return { ok: true };
  }

  @Post('periods/:id/next-open')
  @Roles(Role.ADMIN)
  async createNextOpenPeriod(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    const period = await this.payroll.createNextOpenPeriod(ownerId, id);
    return this.mapPeriod(period);
  }

  @Get('periods/:id/total-all')
  @Roles(Role.ADMIN)
  async computePeriodTotalAllEmployees(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    const total = await this.payroll.computePeriodTotalAllEmployees(ownerId, id);
    return { total };
  }

  @Get('employees')
  @Roles(Role.ADMIN)
  async listEmployees(@Req() req: Request, @Query('activeOnly') activeOnly?: string) {
    const ownerId = await this.ownerIdFrom(req);
    const useActiveOnly = activeOnly == null ? true : activeOnly.toLowerCase() !== 'false';
    const employees = await this.payroll.listEmployees(ownerId, useActiveOnly);
    return employees.map((item) => this.mapEmployee(item));
  }

  @Get('employees/:id')
  @Roles(Role.ADMIN)
  async getEmployeeById(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    const employee = await this.payroll.getEmployeeById(ownerId, id);
    return employee ? this.mapEmployee(employee) : null;
  }

  @Post('employees/upsert')
  @Roles(Role.ADMIN)
  async upsertEmployee(@Req() req: Request, @Body() dto: UpsertPayrollEmployeeDto) {
    const ownerId = await this.ownerIdFrom(req);
    const employee = await this.payroll.upsertEmployee(ownerId, dto);
    return this.mapEmployee(employee);
  }

  @Delete('employees/:id')
  @Roles(Role.ADMIN)
  async deleteEmployee(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    await this.payroll.deleteEmployee(ownerId, id);
    return { ok: true };
  }

  @Get('config')
  @Roles(Role.ADMIN)
  async getEmployeeConfig(@Req() req: Request, @Query('periodId') periodId: string, @Query('employeeId') employeeId: string) {
    const ownerId = await this.ownerIdFrom(req);
    const config = await this.payroll.getEmployeeConfig(ownerId, periodId, employeeId);
    return config ? this.mapConfig(config) : null;
  }

  @Post('config/upsert')
  @Roles(Role.ADMIN)
  async upsertEmployeeConfig(@Req() req: Request, @Body() dto: UpsertPayrollConfigDto) {
    const ownerId = await this.ownerIdFrom(req);
    const config = await this.payroll.upsertEmployeeConfig(ownerId, dto);
    return this.mapConfig(config);
  }

  @Get('entries')
  @Roles(Role.ADMIN)
  async listEntries(@Req() req: Request, @Query() query: PayrollEntriesQueryDto) {
    const ownerId = await this.ownerIdFrom(req);
    const entries = await this.payroll.listEntries(ownerId, query.periodId, query.employeeId);
    return entries.map((item) => this.mapEntry(item));
  }

  @Post('entries')
  @Roles(Role.ADMIN)
  async addEntry(@Req() req: Request, @Body() dto: AddPayrollEntryDto) {
    const ownerId = await this.ownerIdFrom(req);
    const entry = await this.payroll.addEntry(ownerId, dto);
    return this.mapEntry(entry);
  }

  @Get('service-commissions/pending')
  @Roles(Role.ADMIN)
  async listPendingServiceCommissions(@Req() req: Request) {
    const ownerId = await this.ownerIdFrom(req);
    const items = await this.payroll.listPendingServiceCommissionRequests(ownerId);
    return items.map((item) => this.mapServiceCommissionRequest(item));
  }

  @Post('service-commissions/:id/approve')
  @Roles(Role.ADMIN)
  async approveServiceCommission(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    const user = req.user as JwtUser;
    const item = await this.payroll.approveServiceCommissionRequest(ownerId, id, user.id);
    return this.mapServiceCommissionRequest(item);
  }

  @Post('service-commissions/:id/reject')
  @Roles(Role.ADMIN)
  async rejectServiceCommission(
    @Req() req: Request,
    @Param('id') id: string,
    @Body() dto: ReviewServiceCommissionDto,
  ) {
    const ownerId = await this.ownerIdFrom(req);
    const user = req.user as JwtUser;
    const item = await this.payroll.rejectServiceCommissionRequest(ownerId, id, user.id, dto.note);
    return this.mapServiceCommissionRequest(item);
  }

  @Delete('entries/:id')
  @Roles(Role.ADMIN)
  async deleteEntry(@Req() req: Request, @Param('id') id: string) {
    const ownerId = await this.ownerIdFrom(req);
    await this.payroll.deleteEntry(ownerId, id);
    return { ok: true };
  }

  @Get('payment-status')
  @Roles(Role.ADMIN)
  async listPaymentStatuses(@Req() req: Request, @Query() query: PayrollPaymentStatusQueryDto) {
    const ownerId = await this.ownerIdFrom(req);
    const rows = await this.payroll.listPaymentStatuses(ownerId, query.periodId, query.employeeId);
    return rows.map((item) => this.mapPaymentStatus(item));
  }

  @Post('payment-status/mark-paid')
  @Roles(Role.ADMIN)
  async markPayrollPaid(@Req() req: Request, @Body() dto: MarkPayrollPaidDto) {
    const ownerId = await this.ownerIdFrom(req);
    const user = req.user as JwtUser;
    const item = await this.payroll.markPayrollPaid(ownerId, dto.periodId, dto.employeeId, user.id);
    return this.mapPaymentStatus(item);
  }

  @Post('send-whatsapp')
  @Roles(Role.ADMIN)
  async sendPayrollWhatsapp(@Req() req: Request, @Body() dto: SendPayrollWhatsappDto) {
    const ownerId = await this.ownerIdFrom(req);
    return this.payroll.sendPayrollWhatsapp(ownerId, dto);
  }

  @Post('send-whatsapp/schedule')
  @Roles(Role.ADMIN)
  async schedulePayrollWhatsapp(@Req() req: Request, @Body() dto: SchedulePayrollWhatsappDto) {
    const ownerId = await this.ownerIdFrom(req);
    return this.payroll.schedulePayrollWhatsapp(ownerId, dto);
  }

  @Get('totals')
  @Roles(Role.ADMIN)
  async computeTotals(@Req() req: Request, @Query() query: PayrollTotalsQueryDto) {
    const ownerId = await this.ownerIdFrom(req);
    return this.payroll.computeTotals(ownerId, query.periodId, query.employeeId);
  }

  @Get('my-history')
  async listMyPayrollHistory(@Req() req: Request, @Query() query: MyPayrollHistoryQueryDto) {
    const ownerId = await this.ownerIdFrom(req);
    const user = req.user as JwtUser;
    return this.payroll.listMyPayrollHistory(ownerId, user.id, query);
  }

  @Get('my-goal')
  async getCuotaMinima(@Req() req: Request) {
    const ownerId = await this.ownerIdFrom(req);
    const user = req.user as JwtUser;
    const quota = await this.payroll.getCuotaMinimaForUser(ownerId, user.id);
    return { cuota_minima: quota };
  }

  private async ownerIdFrom(req: Request) {
    const user = req.user as JwtUser;
    return this.payroll.resolveCompanyOwnerId(user.id, user.companyId);
  }

  private mapEmployee(employee: {
    id: string;
    ownerId: string;
    userId?: string | null;
    nombre: string;
    telefono: string | null;
    puesto: string | null;
    salarioBaseQuincenal: unknown;
    cuotaMinima: unknown;
    seguroLeyMonto: unknown;
    seguroLeyMontoLocked?: boolean;
    activo: boolean;
    createdAt: Date;
    updatedAt: Date;
  }) {
    return {
      id: employee.id,
      owner_id: employee.ownerId,
      user_id: employee.userId ?? null,
      nombre: employee.nombre,
      telefono: employee.telefono,
      puesto: employee.puesto,
      salario_base_quincenal: Number(employee.salarioBaseQuincenal ?? 0),
      cuota_minima: Number(employee.cuotaMinima ?? 0),
      seguro_ley_monto: Number(employee.seguroLeyMonto ?? 0),
      seguro_ley_monto_locked: employee.seguroLeyMontoLocked === true ? 1 : 0,
      activo: employee.activo ? 1 : 0,
      created_at: employee.createdAt.toISOString(),
      updated_at: employee.updatedAt.toISOString(),
    };
  }

  private mapPeriod(period: {
    id: string;
    ownerId: string;
    title: string;
    startDate: Date;
    endDate: Date;
    status: PayrollPeriodStatus;
    createdAt: Date;
    updatedAt: Date;
  }) {
    const start = period.startDate;
    const end = period.endDate;
    const sDay = start.getDate().toString().padStart(2, '0');
    const eDay = end.getDate().toString().padStart(2, '0');
    const month = (end.getMonth() + 1).toString().padStart(2, '0');
    const year = end.getFullYear().toString();
    const quincenaNumber = end.getDate() <= 14 ? 1 : 2;

    return {
      id: period.id,
      owner_id: period.ownerId,
      title: `Quincena ${quincenaNumber} · ${sDay}-${eDay}/${month}/${year}`,
      start_date: period.startDate.toISOString(),
      end_date: period.endDate.toISOString(),
      status: period.status,
      created_at: period.createdAt.toISOString(),
      updated_at: period.updatedAt.toISOString(),
    };
  }

  private mapConfig(config: {
    id: string;
    ownerId: string;
    periodId: string;
    employeeId: string;
    baseSalary: unknown;
    includeCommissions: boolean;
    notes: string | null;
    createdAt: Date;
    updatedAt: Date;
  }) {
    return {
      id: config.id,
      owner_id: config.ownerId,
      period_id: config.periodId,
      employee_id: config.employeeId,
      base_salary: Number(config.baseSalary ?? 0),
      include_commissions: config.includeCommissions ? 1 : 0,
      notes: config.notes,
      created_at: config.createdAt.toISOString(),
      updated_at: config.updatedAt.toISOString(),
    };
  }

  private mapEntry(entry: {
    id: string;
    ownerId: string;
    periodId: string;
    employeeId: string;
    pagoCombustibleTecnicoId?: string | null;
    date: Date;
    type: string;
    concept: string;
    amount: unknown;
    cantidad: unknown;
    createdAt: Date;
  }) {
    return {
      id: entry.id,
      owner_id: entry.ownerId,
      period_id: entry.periodId,
      employee_id: entry.employeeId,
      pago_combustible_tecnico_id: entry.pagoCombustibleTecnicoId ?? null,
      date: entry.date.toISOString(),
      type: entry.type,
      concept: entry.concept,
      amount: Number(entry.amount ?? 0),
      cantidad: entry.cantidad == null ? null : Number(entry.cantidad),
      created_at: entry.createdAt.toISOString(),
    };
  }

  private mapPaymentStatus(item: {
    id: string;
    ownerId: string;
    periodId: string;
    employeeId: string;
    status: string;
    paidAt: Date | null;
    paidById: string | null;
    createdAt: Date;
    updatedAt: Date;
  }) {
    return {
      id: item.id,
      owner_id: item.ownerId,
      period_id: item.periodId,
      employee_id: item.employeeId,
      status: item.status,
      paid_at: item.paidAt?.toISOString() ?? null,
      paid_by_id: item.paidById,
      created_at: item.createdAt.toISOString(),
      updated_at: item.updatedAt.toISOString(),
    };
  }

  private mapServiceCommissionRequest(item: {
    id: string;
    ownerId: string;
    serviceOrderId: string;
    quotationId: string | null;
    employeeId: string;
    technicianUserId: string;
    createdByUserId: string | null;
    reviewedByUserId: string | null;
    periodId: string | null;
    payrollEntryId: string | null;
    serviceType: string;
    finalizedAt: Date;
    profitAfterExpense: unknown;
    commissionRate: unknown;
    commissionAmount: unknown;
    concept: string;
    status: string;
    reviewNote: string | null;
    approvedAt: Date | null;
    rejectedAt: Date | null;
    createdAt: Date;
    updatedAt: Date;
    employee?: { id: string; nombre: string; userId: string | null };
    technicianUser?: { id: string; nombreCompleto: string; role: Role };
    serviceOrder?: {
      id: string;
      clientId: string;
      createdById: string;
      assignedToId: string | null;
      client?: { id: string; nombre: string };
    };
  }) {
    return {
      id: item.id,
      owner_id: item.ownerId,
      service_order_id: item.serviceOrderId,
      quotation_id: item.quotationId,
      employee_id: item.employeeId,
      employee_name: item.employee?.nombre ?? '',
      employee_user_id: item.employee?.userId ?? null,
      technician_user_id: item.technicianUserId,
      technician_name: item.technicianUser?.nombreCompleto ?? '',
      created_by_user_id: item.createdByUserId,
      reviewed_by_user_id: item.reviewedByUserId,
      period_id: item.periodId,
      payroll_entry_id: item.payrollEntryId,
      service_type: item.serviceType,
      finalized_at: item.finalizedAt.toISOString(),
      profit_after_expense: Number(item.profitAfterExpense ?? 0),
      commission_rate: Number(item.commissionRate ?? 0),
      commission_amount: Number(item.commissionAmount ?? 0),
      concept: item.concept,
      status: item.status,
      review_note: item.reviewNote,
      approved_at: item.approvedAt?.toISOString(),
      rejected_at: item.rejectedAt?.toISOString(),
      created_at: item.createdAt.toISOString(),
      updated_at: item.updatedAt.toISOString(),
      customer_id: item.serviceOrder?.clientId ?? null,
      customer_name: item.serviceOrder?.client?.nombre ?? null,
      seller_user_id: item.serviceOrder?.createdById ?? null,
      assigned_to_user_id: item.serviceOrder?.assignedToId ?? null,
      recipient_user_id: item.employee?.userId ?? item.employeeId,
      recipient_source:
        (item.employee?.userId ?? item.employeeId) === item.serviceOrder?.assignedToId
          ? 'assigned_technician'
          : (item.employee?.userId ?? item.employeeId) === item.serviceOrder?.createdById
            ? 'order_creator'
            : 'payroll_employee',
    };
  }
}
