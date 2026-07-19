import crypto from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

type ApplicationRow = {
  id: string;
  application_code: string;
  full_name: string;
  identity_number: string;
  phone: string;
  whatsapp: string;
  email: string | null;
  province: string;
  municipality: string;
  sector: string | null;
  specialty: string;
  experience_level: string;
  experience_description: string | null;
  camera_skills: unknown;
  gate_motor_skills: unknown;
  tools_availability: string;
  tools: unknown;
  other_tools: string | null;
  transportation: string;
  availability: string;
  availability_notes: string | null;
  can_travel: boolean;
  can_work_weekends: boolean;
  profile_photo_url: string | null;
  identity_front_photo_url: string | null;
  identity_back_photo_url: string | null;
  work_evidence_photo_urls: unknown;
  reference_name: string | null;
  reference_phone: string | null;
  previous_company: string | null;
  status: string;
  rejection_reason: string | null;
  internal_notes: string | null;
  submitted_at: Date;
  reviewed_at: Date | null;
  reviewed_by_id: string | null;
  created_at: Date;
  updated_at: Date;
};

type TechnicianRow = {
  id: string;
  technician_code: string;
  application_id: string | null;
  full_name: string;
  identity_number: string;
  phone: string;
  whatsapp: string;
  email: string | null;
  province: string;
  municipality: string;
  sector: string | null;
  specialty: string;
  experience_level: string;
  experience_description: string | null;
  camera_skills: unknown;
  gate_motor_skills: unknown;
  tools_availability: string;
  tools: unknown;
  other_tools: string | null;
  transportation: string;
  availability: string;
  availability_notes: string | null;
  can_travel: boolean;
  can_work_weekends: boolean;
  profile_photo_url: string | null;
  identity_document_urls: unknown;
  work_evidence_photo_urls: unknown;
  status: string;
  is_favorite: boolean;
  completed_jobs_count: number;
  rating: Prisma.Decimal | number | string;
  internal_notes: string | null;
  approved_at: Date;
  approved_by_id: string | null;
  last_job_at: Date | null;
  created_at: Date;
  updated_at: Date;
};

@Injectable()
export class TechnicalNetworkService {
  constructor(private readonly prisma: PrismaService) {}

  async summary() {
    const [applications, technicians] = await Promise.all([
      this.listApplications(),
      this.listTechnicians(),
    ]);
    return {
      totalApplications: applications.length,
      pendingApplications: applications.filter((item) => item.status === 'PENDING').length,
      activeTechnicians: technicians.filter((item) => item.status !== 'INACTIVE').length,
      inactiveTechnicians: technicians.filter((item) => item.status === 'INACTIVE').length,
      cameraTechnicians: technicians.filter((item) => item.specialty === 'CAMERAS' || item.specialty === 'BOTH').length,
      gateMotorTechnicians: technicians.filter((item) => item.specialty === 'GATE_MOTORS' || item.specialty === 'BOTH').length,
      availableTechnicians: technicians.filter((item) => item.status === 'AVAILABLE').length,
    };
  }

  async listApplications() {
    const rows = await this.prisma.$queryRaw<ApplicationRow[]>`
      SELECT * FROM technical_network_applications
      ORDER BY submitted_at DESC
    `;
    return rows.map((row) => this.mapApplication(row));
  }

  async listTechnicians() {
    const [rows, jobs, evaluations] = await Promise.all([
      this.prisma.$queryRaw<TechnicianRow[]>`
        SELECT * FROM technical_network_technicians
        ORDER BY is_favorite DESC, full_name ASC
      `,
      this.prisma.$queryRaw<any[]>`
        SELECT * FROM technical_network_jobs ORDER BY job_date DESC
      `,
      this.prisma.$queryRaw<any[]>`
        SELECT * FROM technical_network_evaluations ORDER BY created_at DESC
      `,
    ]);
    return rows.map((row) => ({
      ...this.mapTechnician(row),
      jobs: jobs.filter((job) => job.technician_id === row.id).map((job) => this.mapJob(job)),
      evaluations: evaluations
        .filter((evaluation) => evaluation.technician_id === row.id)
        .map((evaluation) => this.mapEvaluation(evaluation)),
    }));
  }

  async submitApplication(dto: Record<string, unknown>) {
    const data = this.cleanApplicationDto(dto);
    await this.assertNoApplicationDuplicate(data.identityNumber, data.phone);
    const id = crypto.randomUUID();
    const code = await this.nextApplicationCode();
    const now = new Date();
    await this.prisma.$executeRaw`
      INSERT INTO technical_network_applications (
        id, application_code, full_name, identity_number, phone, whatsapp, email,
        province, municipality, sector, specialty, experience_level,
        experience_description, camera_skills, gate_motor_skills,
        tools_availability, tools, other_tools, transportation, availability,
        availability_notes, can_travel, can_work_weekends, profile_photo_url,
        identity_front_photo_url, identity_back_photo_url, work_evidence_photo_urls,
        reference_name, reference_phone, previous_company, status,
        internal_notes, submitted_at, created_at, updated_at
      ) VALUES (
        ${id}, ${code}, ${data.fullName}, ${data.identityNumber}, ${data.phone},
        ${data.whatsapp}, ${data.email}, ${data.province}, ${data.municipality},
        ${data.sector}, ${data.specialty}, ${data.experienceLevel},
        ${data.experienceDescription}, ${JSON.stringify(data.cameraSkills)}::jsonb,
        ${JSON.stringify(data.gateMotorSkills)}::jsonb, ${data.toolsAvailability},
        ${JSON.stringify(data.tools)}::jsonb, ${data.otherTools}, ${data.transportation},
        ${data.availability}, ${data.availabilityNotes}, ${data.canTravel},
        ${data.canWorkWeekends}, ${data.profilePhotoUrl}, ${data.identityFrontPhotoUrl},
        ${data.identityBackPhotoUrl}, ${JSON.stringify(data.workEvidencePhotoUrls)}::jsonb,
        ${data.referenceName}, ${data.referencePhone}, ${data.previousCompany},
        'PENDING', ${data.internalNotes}, ${now}, ${now}, ${now}
      )
    `;
    return { ok: true, id, applicationCode: code };
  }

  async updateApplicationStatus(userId: string, id: string, dto: Record<string, unknown>) {
    const status = this.enumText(dto.status, ['PENDING', 'REVIEWING', 'APPROVED', 'REJECTED'], 'REVIEWING');
    if (status === 'APPROVED') return this.approveApplication(userId, id);
    const reason = this.text(dto.rejectionReason);
    const exists = await this.findApplication(id);
    if (!exists) throw new NotFoundException('Solicitud no encontrada.');
    await this.prisma.$executeRaw`
      UPDATE technical_network_applications
      SET status = ${status}, rejection_reason = ${reason}, reviewed_at = now(),
          reviewed_by_id = ${userId}, updated_at = now()
      WHERE id = ${id}
    `;
    return { ok: true };
  }

  async approveApplication(userId: string, id: string) {
    const application = await this.findApplication(id);
    if (!application) throw new NotFoundException('Solicitud no encontrada.');
    if (application.status === 'APPROVED') {
      throw new ConflictException('Esta solicitud ya fue aprobada.');
    }
    const existing = await this.prisma.$queryRaw<{ id: string }[]>`
      SELECT id FROM technical_network_technicians WHERE application_id = ${id} LIMIT 1
    `;
    if (existing.length) {
      throw new ConflictException('Esta solicitud ya creo un tecnico.');
    }
    const technicianId = crypto.randomUUID();
    const code = await this.nextTechnicianCode();
    const now = new Date();
    await this.prisma.$transaction([
      this.prisma.$executeRaw`
        UPDATE technical_network_applications
        SET status = 'APPROVED', reviewed_at = ${now}, reviewed_by_id = ${userId}, updated_at = ${now}
        WHERE id = ${id}
      `,
      this.prisma.$executeRaw`
        INSERT INTO technical_network_technicians (
          id, technician_code, application_id, full_name, identity_number, phone, whatsapp,
          email, province, municipality, sector, specialty, experience_level,
          experience_description, camera_skills, gate_motor_skills, tools_availability,
          tools, other_tools, transportation, availability, availability_notes,
          can_travel, can_work_weekends, profile_photo_url, identity_document_urls,
          work_evidence_photo_urls, status, is_favorite, completed_jobs_count, rating,
          internal_notes, approved_at, approved_by_id, created_at, updated_at
        ) VALUES (
          ${technicianId}, ${code}, ${application.id}, ${application.full_name},
          ${application.identity_number}, ${application.phone}, ${application.whatsapp},
          ${application.email}, ${application.province}, ${application.municipality},
          ${application.sector}, ${application.specialty}, ${application.experience_level},
          ${application.experience_description}, ${JSON.stringify(this.array(application.camera_skills))}::jsonb,
          ${JSON.stringify(this.array(application.gate_motor_skills))}::jsonb,
          ${application.tools_availability}, ${JSON.stringify(this.array(application.tools))}::jsonb,
          ${application.other_tools}, ${application.transportation}, ${application.availability},
          ${application.availability_notes}, ${application.can_travel}, ${application.can_work_weekends},
          ${application.profile_photo_url},
          ${JSON.stringify([application.identity_front_photo_url, application.identity_back_photo_url].filter(Boolean))}::jsonb,
          ${JSON.stringify(this.array(application.work_evidence_photo_urls))}::jsonb,
          'AVAILABLE', false, 0, 0, ${application.internal_notes}, ${now}, ${userId}, ${now}, ${now}
        )
      `,
    ]);
    return { ok: true, id: technicianId, technicianCode: code };
  }

  async createTechnician(userId: string, dto: Record<string, unknown>) {
    const data = this.cleanApplicationDto(dto);
    const id = crypto.randomUUID();
    const code = await this.nextTechnicianCode();
    const now = new Date();
    await this.prisma.$executeRaw`
      INSERT INTO technical_network_technicians (
        id, technician_code, full_name, identity_number, phone, whatsapp, email,
        province, municipality, sector, specialty, experience_level, experience_description,
        camera_skills, gate_motor_skills, tools_availability, tools, other_tools,
        transportation, availability, availability_notes, can_travel, can_work_weekends,
        profile_photo_url, identity_document_urls, work_evidence_photo_urls, status,
        is_favorite, completed_jobs_count, rating, internal_notes, approved_at,
        approved_by_id, created_at, updated_at
      ) VALUES (
        ${id}, ${code}, ${data.fullName}, ${data.identityNumber}, ${data.phone},
        ${data.whatsapp}, ${data.email}, ${data.province}, ${data.municipality},
        ${data.sector}, ${data.specialty}, ${data.experienceLevel},
        ${data.experienceDescription}, ${JSON.stringify(data.cameraSkills)}::jsonb,
        ${JSON.stringify(data.gateMotorSkills)}::jsonb, ${data.toolsAvailability},
        ${JSON.stringify(data.tools)}::jsonb, ${data.otherTools}, ${data.transportation},
        ${data.availability}, ${data.availabilityNotes}, ${data.canTravel},
        ${data.canWorkWeekends}, ${data.profilePhotoUrl}, ${JSON.stringify([data.identityFrontPhotoUrl, data.identityBackPhotoUrl].filter(Boolean))}::jsonb,
        ${JSON.stringify(data.workEvidencePhotoUrls)}::jsonb, ${this.enumText(dto.status, ['AVAILABLE','BUSY','UNAVAILABLE','INACTIVE'], 'AVAILABLE')},
        false, 0, 0, ${data.internalNotes}, ${now}, ${userId}, ${now}, ${now}
      )
    `;
    return { ok: true, id, technicianCode: code };
  }

  async updateTechnician(id: string, dto: Record<string, unknown>) {
    const exists = await this.prisma.$queryRaw<{ id: string }[]>`
      SELECT id FROM technical_network_technicians WHERE id = ${id} LIMIT 1
    `;
    if (!exists.length) throw new NotFoundException('Tecnico no encontrado.');
    const status = this.enumText(dto.status, ['AVAILABLE', 'BUSY', 'UNAVAILABLE', 'INACTIVE'], '');
    const isFavorite = typeof dto.isFavorite === 'boolean' ? dto.isFavorite : null;
    await this.prisma.$executeRaw`
      UPDATE technical_network_technicians
      SET
        status = COALESCE(NULLIF(${status}, ''), status),
        is_favorite = COALESCE(${isFavorite}, is_favorite),
        updated_at = now()
      WHERE id = ${id}
    `;
    return { ok: true };
  }

  async addJob(userId: string, technicianId: string, dto: Record<string, unknown>) {
    const id = crypto.randomUUID();
    const status = this.enumText(dto.status, ['PENDING', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'], 'PENDING');
    const now = new Date();
    const jobDate = this.date(dto.date) ?? now;
    await this.prisma.$transaction([
      this.prisma.$executeRaw`
        INSERT INTO technical_network_jobs (
          id, technician_id, type, job_date, location, description,
          agreed_payment, status, internal_note, created_by_id, created_at, updated_at
        ) VALUES (
          ${id}, ${technicianId}, ${this.enumText(dto.type, ['CAMERA_INSTALLATION','CAMERA_MAINTENANCE','GATE_MOTOR_INSTALLATION','GATE_MOTOR_MAINTENANCE'], 'CAMERA_INSTALLATION')},
          ${jobDate}, ${this.text(dto.location)}, ${this.text(dto.description)},
          ${this.money(dto.agreedPayment)}, ${status}, ${this.text(dto.internalNote)}, ${userId}, ${now}, ${now}
        )
      `,
      ...(status === 'COMPLETED'
        ? [
            this.prisma.$executeRaw`
              UPDATE technical_network_technicians
              SET completed_jobs_count = completed_jobs_count + 1,
                  last_job_at = ${jobDate},
                  updated_at = now()
              WHERE id = ${technicianId}
            `,
          ]
        : []),
    ]);
    return { ok: true, id };
  }

  async addEvaluation(userId: string, technicianId: string, dto: Record<string, unknown>) {
    const rating = Number(dto.rating ?? 0);
    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
      throw new BadRequestException('La calificacion debe estar entre 1 y 5.');
    }
    const id = crypto.randomUUID();
    await this.prisma.$transaction([
      this.prisma.$executeRaw`
        INSERT INTO technical_network_evaluations (id, technician_id, rating, note, created_by_id)
        VALUES (${id}, ${technicianId}, ${rating}, ${this.text(dto.note)}, ${userId})
      `,
      this.prisma.$executeRaw`
        UPDATE technical_network_technicians t
        SET rating = COALESCE((
          SELECT ROUND(AVG(rating)::numeric, 2)
          FROM technical_network_evaluations e
          WHERE e.technician_id = t.id
        ), 0), updated_at = now()
        WHERE t.id = ${technicianId}
      `,
    ]);
    return { ok: true, id };
  }

  publicFormHtml() {
    return `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Red Tecnica FullTech</title>
<style>
body{margin:0;font-family:Arial,sans-serif;background:#eef5f8;color:#0f172a}.wrap{max-width:940px;margin:auto;padding:22px}
.card{background:#fff;border:1px solid #dbe5ea;border-radius:14px;padding:22px;box-shadow:0 14px 40px #0f172a14}
h1{margin:0 0 6px;font-size:30px}p{color:#475569}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
label{display:block;font-size:13px;font-weight:700;margin-bottom:5px}input,select,textarea{width:100%;box-sizing:border-box;border:1px solid #cbd5e1;border-radius:10px;padding:11px;font-size:15px}
textarea{min-height:88px}.full{grid-column:1/-1}.chips{display:flex;gap:8px;flex-wrap:wrap}.chip{border:1px solid #cbd5e1;border-radius:999px;padding:8px 10px}
button{border:0;border-radius:11px;background:#0f766e;color:#fff;font-weight:800;padding:13px 18px;font-size:16px;cursor:pointer}.ok{display:none;text-align:center;padding:34px}
.err{display:none;background:#fee2e2;color:#991b1b;border:1px solid #fecaca;border-radius:10px;padding:10px;margin:12px 0}@media(max-width:720px){.grid{grid-template-columns:1fr}.wrap{padding:12px}}
</style></head><body><main class="wrap"><section class="card"><h1>Red Tecnica FullTech</h1><p>Formulario para tecnicos independientes de camaras de seguridad y motores de portones.</p>
<div id="err" class="err"></div><form id="f" class="grid">
${this.input('fullName','Nombre completo *')}${this.input('identityNumber','Cedula *')}${this.input('phone','Telefono *')}${this.input('whatsapp','WhatsApp *')}
${this.input('province','Provincia *')}${this.input('municipality','Municipio *')}${this.input('email','Correo')}${this.input('sector','Sector')}
<div><label>Especialidad *</label><select name="specialty"><option value="CAMERAS">Camaras de seguridad</option><option value="GATE_MOTORS">Motores de portones</option><option value="BOTH">Ambas areas</option></select></div>
<div><label>Experiencia *</label><select name="experienceLevel"><option value="NO_EXPERIENCE">Sin experiencia, deseo aprender</option><option value="LESS_THAN_ONE_YEAR">Menos de un ano</option><option value="ONE_TO_THREE_YEARS">De uno a tres anos</option><option value="MORE_THAN_THREE_YEARS">Mas de tres anos</option></select></div>
<div><label>Herramientas *</label><select name="toolsAvailability"><option value="YES">Si</option><option value="SOME">Algunas</option><option value="NO">No</option></select></div>
<div><label>Transporte *</label><select name="transportation"><option>Moto</option><option>Carro</option><option>Camioneta</option><option>No tengo transporte</option></select></div>
<div class="full"><label>Experiencia breve</label><textarea name="experienceDescription"></textarea></div>
<div class="full"><label>Disponibilidad *</label><select name="availability"><option>Disponible de lunes a sabado</option><option>Disponible algunos dias</option><option>Disponible fines de semana</option><option>Disponible cuando sea contactado</option></select></div>
<div class="full"><label><input type="checkbox" name="canTravel"> Puede viajar fuera del municipio</label><label><input type="checkbox" name="canWorkWeekends"> Puede trabajar fines de semana</label></div>
${this.input('referenceName','Referencia')}${this.input('referencePhone','Telefono referencia')}${this.input('previousCompany','Empresa anterior')}
<div class="full"><label><input type="checkbox" name="accepted" required> Acepto que FullTech SRL me contacte. Completar este formulario no representa contratacion laboral ni garantiza trabajos.</label></div>
<div class="full"><button id="b">Enviar solicitud</button></div></form><div id="ok" class="ok"><h2>Solicitud recibida correctamente</h2><p id="code"></p><p>Gracias por tu interes. Revisaremos tus datos y nos comunicaremos contigo cuando sea necesario.</p></div></section></main>
<script>
const f=document.getElementById('f'),b=document.getElementById('b'),err=document.getElementById('err'),ok=document.getElementById('ok');
f.addEventListener('submit',async e=>{e.preventDefault();err.style.display='none';b.disabled=true;b.textContent='Enviando...';
const fd=new FormData(f);const data=Object.fromEntries(fd.entries());data.canTravel=fd.has('canTravel');data.canWorkWeekends=fd.has('canWorkWeekends');
try{const r=await fetch('/technical-network/public/applications',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});const j=await r.json();if(!r.ok)throw new Error(j.message||'No fue posible enviar la solicitud.');
f.style.display='none';ok.style.display='block';document.getElementById('code').textContent='Numero de solicitud: '+j.applicationCode;}catch(ex){err.textContent=ex.message;err.style.display='block';b.disabled=false;b.textContent='Enviar solicitud';}});
</script></body></html>`;
  }

  private input(name: string, label: string) {
    return `<div><label>${label}</label><input name="${name}"></div>`;
  }

  private async findApplication(id: string) {
    const rows = await this.prisma.$queryRaw<ApplicationRow[]>`
      SELECT * FROM technical_network_applications WHERE id = ${id} LIMIT 1
    `;
    return rows[0] ?? null;
  }

  private async assertNoApplicationDuplicate(identity: string, phone: string) {
    const rows = await this.prisma.$queryRaw<{ id: string }[]>`
      SELECT id FROM technical_network_applications
      WHERE identity_number = ${identity} OR phone = ${phone} OR whatsapp = ${phone}
      LIMIT 1
    `;
    if (rows.length) {
      throw new ConflictException('Ya existe una solicitud con esa cedula o telefono.');
    }
  }

  private async nextApplicationCode() {
    const rows = await this.prisma.$queryRaw<{ count: bigint }[]>`
      SELECT COUNT(*)::bigint AS count FROM technical_network_applications
    `;
    const next = Number(rows[0]?.count ?? 0) + 1;
    return `RT-${new Date().getFullYear()}-${String(next).padStart(4, '0')}`;
  }

  private async nextTechnicianCode() {
    const rows = await this.prisma.$queryRaw<{ count: bigint }[]>`
      SELECT COUNT(*)::bigint AS count FROM technical_network_technicians
    `;
    const next = Number(rows[0]?.count ?? 0) + 1;
    return `FT-${String(next).padStart(4, '0')}`;
  }

  private cleanApplicationDto(dto: Record<string, unknown>) {
    const fullName = this.required(dto.fullName, 'Nombre obligatorio.');
    const identityNumber = this.digits(dto.identityNumber);
    const phone = this.digits(dto.phone);
    const whatsapp = this.digits(dto.whatsapp || dto.phone);
    if (identityNumber.length !== 11) throw new BadRequestException('Cedula invalida.');
    if (phone.length < 10) throw new BadRequestException('Telefono invalido.');
    return {
      fullName,
      identityNumber,
      phone,
      whatsapp,
      email: this.text(dto.email),
      province: this.required(dto.province, 'Provincia obligatoria.'),
      municipality: this.required(dto.municipality, 'Municipio obligatorio.'),
      sector: this.text(dto.sector),
      specialty: this.enumText(dto.specialty, ['CAMERAS', 'GATE_MOTORS', 'BOTH'], 'CAMERAS'),
      experienceLevel: this.enumText(dto.experienceLevel, ['NO_EXPERIENCE','LESS_THAN_ONE_YEAR','ONE_TO_THREE_YEARS','MORE_THAN_THREE_YEARS'], 'NO_EXPERIENCE'),
      experienceDescription: this.text(dto.experienceDescription),
      cameraSkills: this.array(dto.cameraSkills),
      gateMotorSkills: this.array(dto.gateMotorSkills),
      toolsAvailability: this.enumText(dto.toolsAvailability, ['YES', 'SOME', 'NO'], 'NO'),
      tools: this.array(dto.tools),
      otherTools: this.text(dto.otherTools),
      transportation: this.required(dto.transportation, 'Transporte obligatorio.'),
      availability: this.required(dto.availability, 'Disponibilidad obligatoria.'),
      availabilityNotes: this.text(dto.availabilityNotes),
      canTravel: this.bool(dto.canTravel),
      canWorkWeekends: this.bool(dto.canWorkWeekends),
      profilePhotoUrl: this.text(dto.profilePhotoUrl),
      identityFrontPhotoUrl: this.text(dto.identityFrontPhotoUrl),
      identityBackPhotoUrl: this.text(dto.identityBackPhotoUrl),
      workEvidencePhotoUrls: this.array(dto.workEvidencePhotoUrls),
      referenceName: this.text(dto.referenceName),
      referencePhone: this.digits(dto.referencePhone),
      previousCompany: this.text(dto.previousCompany),
      internalNotes: this.text(dto.internalNotes),
    };
  }

  private mapApplication(row: ApplicationRow) {
    return {
      id: row.id,
      applicationCode: row.application_code,
      fullName: row.full_name,
      identityNumber: row.identity_number,
      phone: row.phone,
      whatsapp: row.whatsapp,
      email: row.email,
      province: row.province,
      municipality: row.municipality,
      sector: row.sector,
      specialty: row.specialty,
      experienceLevel: row.experience_level,
      experienceDescription: row.experience_description,
      cameraSkills: this.array(row.camera_skills),
      gateMotorSkills: this.array(row.gate_motor_skills),
      toolsAvailability: row.tools_availability,
      tools: this.array(row.tools),
      otherTools: row.other_tools,
      transportation: row.transportation,
      availability: row.availability,
      availabilityNotes: row.availability_notes,
      canTravel: row.can_travel,
      canWorkWeekends: row.can_work_weekends,
      profilePhotoUrl: row.profile_photo_url,
      identityFrontPhotoUrl: row.identity_front_photo_url,
      identityBackPhotoUrl: row.identity_back_photo_url,
      workEvidencePhotoUrls: this.array(row.work_evidence_photo_urls),
      referenceName: row.reference_name,
      referencePhone: row.reference_phone,
      previousCompany: row.previous_company,
      status: row.status,
      rejectionReason: row.rejection_reason,
      internalNotes: row.internal_notes,
      submittedAt: row.submitted_at,
      reviewedAt: row.reviewed_at,
      reviewedById: row.reviewed_by_id,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  private mapTechnician(row: TechnicianRow) {
    return {
      id: row.id,
      technicianCode: row.technician_code,
      applicationId: row.application_id,
      fullName: row.full_name,
      identityNumber: row.identity_number,
      phone: row.phone,
      whatsapp: row.whatsapp,
      email: row.email,
      province: row.province,
      municipality: row.municipality,
      sector: row.sector,
      specialty: row.specialty,
      experienceLevel: row.experience_level,
      experienceDescription: row.experience_description,
      cameraSkills: this.array(row.camera_skills),
      gateMotorSkills: this.array(row.gate_motor_skills),
      toolsAvailability: row.tools_availability,
      tools: this.array(row.tools),
      otherTools: row.other_tools,
      transportation: row.transportation,
      availability: row.availability,
      availabilityNotes: row.availability_notes,
      canTravel: row.can_travel,
      canWorkWeekends: row.can_work_weekends,
      profilePhotoUrl: row.profile_photo_url,
      identityDocumentUrls: this.array(row.identity_document_urls),
      workEvidencePhotoUrls: this.array(row.work_evidence_photo_urls),
      status: row.status,
      isFavorite: row.is_favorite,
      completedJobsCount: row.completed_jobs_count,
      rating: Number(row.rating ?? 0),
      internalNotes: row.internal_notes,
      approvedAt: row.approved_at,
      approvedById: row.approved_by_id,
      lastJobAt: row.last_job_at,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  private mapJob(row: any) {
    return {
      id: row.id,
      technicianId: row.technician_id,
      type: row.type,
      date: row.job_date,
      location: row.location,
      description: row.description,
      agreedPayment: row.agreed_payment == null ? null : Number(row.agreed_payment),
      status: row.status,
      internalNote: row.internal_note,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  private mapEvaluation(row: any) {
    return {
      id: row.id,
      technicianId: row.technician_id,
      rating: row.rating,
      note: row.note,
      createdAt: row.created_at,
    };
  }

  private required(value: unknown, message: string) {
    const text = this.text(value);
    if (!text) throw new BadRequestException(message);
    return text;
  }

  private text(value: unknown) {
    const text = `${value ?? ''}`.trim();
    return text.length ? text : null;
  }

  private digits(value: unknown) {
    return `${value ?? ''}`.replace(/\D/g, '');
  }

  private bool(value: unknown) {
    return value === true || value === 'true' || value === 'on' || value === '1';
  }

  private date(value: unknown) {
    const raw = this.text(value);
    if (!raw) return null;
    const date = new Date(raw);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  private money(value: unknown) {
    const n = Number(value ?? 0);
    return Number.isFinite(n) && n > 0 ? n : null;
  }

  private enumText(value: unknown, allowed: string[], fallback: string) {
    const text = `${value ?? ''}`.trim().toUpperCase();
    if (allowed.includes(text)) return text;
    if (!fallback) return '';
    return fallback;
  }

  private array(value: unknown): string[] {
    if (Array.isArray(value)) {
      return value.map((item) => `${item}`.trim()).filter(Boolean);
    }
    if (typeof value === 'string' && value.trim().startsWith('[')) {
      try {
        return this.array(JSON.parse(value));
      } catch {
        return [];
      }
    }
    if (typeof value === 'string' && value.trim()) {
      return value.split(',').map((item) => item.trim()).filter(Boolean);
    }
    return [];
  }
}
