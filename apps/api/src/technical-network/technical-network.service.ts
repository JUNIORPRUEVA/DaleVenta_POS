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
  manual_address: string | null;
  formatted_address: string | null;
  latitude: number | null;
  longitude: number | null;
  location_accuracy: number | null;
  location_captured_at: Date | null;
  location_source: string | null;
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
  resume_url: string | null;
  resume_original_name: string | null;
  resume_mime_type: string | null;
  resume_size_bytes: bigint | number | null;
  reference_name: string | null;
  reference_phone: string | null;
  previous_company: string | null;
  status: string;
  rejection_reason: string | null;
  internal_notes: string | null;
  submitted_at: Date;
  reviewed_at: Date | null;
  reviewed_by_id: string | null;
  consent_accepted: boolean;
  consent_accepted_at: Date | null;
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
  manual_address: string | null;
  formatted_address: string | null;
  latitude: number | null;
  longitude: number | null;
  location_accuracy: number | null;
  location_captured_at: Date | null;
  location_source: string | null;
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
  resume_url: string | null;
  resume_original_name: string | null;
  resume_mime_type: string | null;
  resume_size_bytes: bigint | number | null;
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
        province, municipality, sector, manual_address, formatted_address,
        latitude, longitude, location_accuracy, location_captured_at, location_source,
        specialty, experience_level,
        experience_description, camera_skills, gate_motor_skills,
        tools_availability, tools, other_tools, transportation, availability,
        availability_notes, can_travel, can_work_weekends, profile_photo_url,
        identity_front_photo_url, identity_back_photo_url, work_evidence_photo_urls,
        resume_url, resume_original_name, resume_mime_type, resume_size_bytes,
        reference_name, reference_phone, previous_company, status,
        internal_notes, consent_accepted, consent_accepted_at, submitted_at, created_at, updated_at
      ) VALUES (
        ${id}, ${code}, ${data.fullName}, ${data.identityNumber}, ${data.phone},
        ${data.whatsapp}, ${data.email}, ${data.province}, ${data.municipality},
        ${data.sector}, ${data.manualAddress}, ${data.formattedAddress},
        ${data.latitude}, ${data.longitude}, ${data.locationAccuracy},
        ${data.locationCapturedAt}, ${data.locationSource},
        ${data.specialty}, ${data.experienceLevel},
        ${data.experienceDescription}, ${JSON.stringify(data.cameraSkills)}::jsonb,
        ${JSON.stringify(data.gateMotorSkills)}::jsonb, ${data.toolsAvailability},
        ${JSON.stringify(data.tools)}::jsonb, ${data.otherTools}, ${data.transportation},
        ${data.availability}, ${data.availabilityNotes}, ${data.canTravel},
        ${data.canWorkWeekends}, ${data.profilePhotoUrl}, ${data.identityFrontPhotoUrl},
        ${data.identityBackPhotoUrl}, ${JSON.stringify(data.workEvidencePhotoUrls)}::jsonb,
        ${data.resumeUrl}, ${data.resumeOriginalName}, ${data.resumeMimeType}, ${data.resumeSizeBytes},
        ${data.referenceName}, ${data.referencePhone}, ${data.previousCompany},
        'PENDING', ${data.internalNotes}, ${data.consentAccepted}, ${data.consentAcceptedAt}, ${now}, ${now}, ${now}
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
          email, province, municipality, sector, manual_address, formatted_address,
          latitude, longitude, location_accuracy, location_captured_at, location_source,
          specialty, experience_level,
          experience_description, camera_skills, gate_motor_skills, tools_availability,
          tools, other_tools, transportation, availability, availability_notes,
          can_travel, can_work_weekends, profile_photo_url, identity_document_urls,
          work_evidence_photo_urls, resume_url, resume_original_name, resume_mime_type,
          resume_size_bytes, status, is_favorite, completed_jobs_count, rating,
          internal_notes, approved_at, approved_by_id, created_at, updated_at
        ) VALUES (
          ${technicianId}, ${code}, ${application.id}, ${application.full_name},
          ${application.identity_number}, ${application.phone}, ${application.whatsapp},
          ${application.email}, ${application.province}, ${application.municipality},
          ${application.sector}, ${application.manual_address}, ${application.formatted_address},
          ${application.latitude}, ${application.longitude}, ${application.location_accuracy},
          ${application.location_captured_at}, ${application.location_source},
          ${application.specialty}, ${application.experience_level},
          ${application.experience_description}, ${JSON.stringify(this.array(application.camera_skills))}::jsonb,
          ${JSON.stringify(this.array(application.gate_motor_skills))}::jsonb,
          ${application.tools_availability}, ${JSON.stringify(this.array(application.tools))}::jsonb,
          ${application.other_tools}, ${application.transportation}, ${application.availability},
          ${application.availability_notes}, ${application.can_travel}, ${application.can_work_weekends},
          ${application.profile_photo_url},
          ${JSON.stringify([application.identity_front_photo_url, application.identity_back_photo_url].filter(Boolean))}::jsonb,
          ${JSON.stringify(this.array(application.work_evidence_photo_urls))}::jsonb,
          ${application.resume_url}, ${application.resume_original_name}, ${application.resume_mime_type},
          ${application.resume_size_bytes == null ? null : Number(application.resume_size_bytes)},
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
        province, municipality, sector, manual_address, formatted_address,
        latitude, longitude, location_accuracy, location_captured_at, location_source,
        specialty, experience_level, experience_description,
        camera_skills, gate_motor_skills, tools_availability, tools, other_tools,
        transportation, availability, availability_notes, can_travel, can_work_weekends,
        profile_photo_url, identity_document_urls, work_evidence_photo_urls,
        resume_url, resume_original_name, resume_mime_type, resume_size_bytes, status,
        is_favorite, completed_jobs_count, rating, internal_notes, approved_at,
        approved_by_id, created_at, updated_at
      ) VALUES (
        ${id}, ${code}, ${data.fullName}, ${data.identityNumber}, ${data.phone},
        ${data.whatsapp}, ${data.email}, ${data.province}, ${data.municipality},
        ${data.sector}, ${data.manualAddress}, ${data.formattedAddress},
        ${data.latitude}, ${data.longitude}, ${data.locationAccuracy},
        ${data.locationCapturedAt}, ${data.locationSource},
        ${data.specialty}, ${data.experienceLevel},
        ${data.experienceDescription}, ${JSON.stringify(data.cameraSkills)}::jsonb,
        ${JSON.stringify(data.gateMotorSkills)}::jsonb, ${data.toolsAvailability},
        ${JSON.stringify(data.tools)}::jsonb, ${data.otherTools}, ${data.transportation},
        ${data.availability}, ${data.availabilityNotes}, ${data.canTravel},
        ${data.canWorkWeekends}, ${data.profilePhotoUrl}, ${JSON.stringify([data.identityFrontPhotoUrl, data.identityBackPhotoUrl].filter(Boolean))}::jsonb,
        ${JSON.stringify(data.workEvidencePhotoUrls)}::jsonb,
        ${data.resumeUrl}, ${data.resumeOriginalName}, ${data.resumeMimeType}, ${data.resumeSizeBytes},
        ${this.enumText(dto.status, ['AVAILABLE','BUSY','UNAVAILABLE','INACTIVE'], 'AVAILABLE')},
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
<title>Red Técnica FullTech | Cámaras y motores de portones</title>
<meta name="description" content="Únete a la Red Técnica FullTech y registra tu perfil para futuras oportunidades de instalación y mantenimiento de cámaras de seguridad y motores de portones.">
<meta property="og:title" content="Red Técnica FullTech">
<meta property="og:description" content="Registra tu perfil como técnico o ayudante aliado de FullTech SRL.">
<style>
*{box-sizing:border-box}body{margin:0;font-family:Inter,Arial,sans-serif;background:#f2f7fa;color:#0f172a}a{color:inherit}.nav{position:sticky;top:0;z-index:5;background:#ffffffeb;backdrop-filter:blur(10px);border-bottom:1px solid #dbe5ea}.navin{max-width:1160px;margin:auto;padding:12px 18px;display:flex;gap:14px;align-items:center}.brand{font-weight:900;font-size:18px}.links{margin-left:auto;display:flex;gap:14px;align-items:center;font-size:14px}.btn{border:0;border-radius:12px;background:#145bea;color:#fff;font-weight:900;padding:12px 16px;text-decoration:none;cursor:pointer}.btn.sec{background:#fff;color:#0f172a;border:1px solid #cbd5e1}.hero{background:linear-gradient(120deg,#06152f,#1248ad);color:#fff}.wrap{max-width:1160px;margin:auto;padding:48px 18px}.heroGrid{display:grid;grid-template-columns:1.05fr .95fr;gap:26px;align-items:center}.hero h1{font-size:clamp(34px,6vw,62px);line-height:.98;margin:0 0 14px}.hero p{color:#dbeafe;font-size:18px;line-height:1.5}.heroCard{min-height:330px;border-radius:24px;background:radial-gradient(circle at 30% 20%,#60a5fa55,transparent 35%),linear-gradient(145deg,#0f172a,#1e40af);border:1px solid #ffffff24;padding:24px;display:flex;align-items:end}.heroCard div{background:#ffffff12;border:1px solid #ffffff24;border-radius:18px;padding:18px}.section{max-width:1160px;margin:auto;padding:34px 18px}.cards{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}.card{background:#fff;border:1px solid #dbe5ea;border-radius:18px;padding:20px;box-shadow:0 14px 35px #0f172a10}.card h3,.card h2{margin-top:0}.muted{color:#64748b;line-height:1.45}.steps{counter-reset:s;display:grid;grid-template-columns:repeat(4,1fr);gap:12px}.step:before{counter-increment:s;content:counter(s);display:grid;place-items:center;width:34px;height:34px;border-radius:12px;background:#eaf1ff;color:#145bea;font-weight:900;margin-bottom:10px}.formShell{max-width:980px;margin:auto}.progress{font-weight:900;color:#145bea;margin-bottom:10px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.field label{display:block;font-size:13px;font-weight:800;margin-bottom:6px}.field input,.field select,.field textarea{width:100%;border:1px solid #cbd5e1;border-radius:12px;padding:12px;font-size:15px;background:#fff}.field textarea{min-height:88px}.full{grid-column:1/-1}.stepPanel{display:none}.stepPanel.active{display:block}.choices{display:flex;flex-wrap:wrap;gap:8px}.choice{border:1px solid #cbd5e1;border-radius:999px;padding:8px 10px;background:#fff}.choice input{margin-right:5px}.actions{display:flex;justify-content:space-between;gap:10px;margin-top:18px}.err{display:none;background:#fee2e2;color:#991b1b;border:1px solid #fecaca;border-radius:12px;padding:12px;margin:12px 0}.ok{display:none;text-align:center;padding:34px}.notice{background:#eff6ff;border:1px solid #bfdbfe;color:#1e3a8a;border-radius:14px;padding:14px}.foot{background:#0f172a;color:#dbeafe;margin-top:36px}.foot .wrap{padding-top:28px;padding-bottom:28px}.privacy{font-size:13px;color:#94a3b8}.hide{display:none!important}@media(max-width:820px){.links a:not(.btn){display:none}.heroGrid,.cards,.steps,.grid{grid-template-columns:1fr}.wrap{padding:32px 14px}.section{padding:24px 14px}.actions{flex-direction:column}.actions button,.actions a{width:100%;text-align:center}.heroCard{min-height:220px}}
</style></head><body><header class="nav"><div class="navin"><div class="brand">FULLTECH SRL</div><nav class="links"><a href="#sobre">Sobre FullTech</a><a href="#red">Red Técnica</a><a href="#proceso">Cómo funciona</a><a class="btn" href="#formulario">Llenar formulario</a></nav></div></header>
<main><section class="hero"><div class="wrap heroGrid"><div><h1>Únete a la Red Técnica FullTech</h1><p>Buscamos técnicos y ayudantes responsables para trabajos de instalación y mantenimiento de cámaras de seguridad y motores de portones.</p><p><a class="btn" href="#formulario">Llenar formulario</a> <a class="btn sec" href="#red">Conocer más</a></p></div><div class="heroCard"><div><b>Seguridad, automatización y soporte técnico</b><p>Más de 5 años ofreciendo soluciones tecnológicas desde Higüey, La Altagracia.</p></div></div></div></section>
<section id="sobre" class="section"><div class="cards"><div class="card"><h2>Conoce FullTech</h2><p class="muted">FullTech SRL es una empresa con más de cinco años de experiencia ofreciendo soluciones de seguridad, tecnología y automatización. Nos especializamos en instalación y mantenimiento de cámaras de seguridad y motores de portones.</p></div><div class="card"><h3>Servicios principales</h3><p class="muted">Cámaras, DVR, NVR, cableado, motores corredizos y batientes, automatización de accesos y mantenimiento técnico.</p></div><div class="card"><h3>Ubicación</h3><p class="muted">Centro de Higüey, calle Beller No. 9, detrás del Banco BHD principal, La Altagracia, República Dominicana.</p></div></div></section>
<section id="red" class="section"><div class="cards"><div class="card"><h2>Una red de técnicos aliados</h2><p class="muted">Reunimos técnicos independientes y ayudantes que pueden ser contactados cuando surjan trabajos. Cada solicitud será revisada antes de aprobarse.</p><div class="notice">Completar el formulario no garantiza contratación fija ni asignación inmediata de trabajos.</div></div><div class="card"><h3>Cámaras de seguridad</h3><p class="muted">Instalación, mantenimiento, cableado, configuración, DVR, NVR, cámaras analógicas e IP.</p></div><div class="card"><h3>Motores de portones</h3><p class="muted">Motores corredizos y batientes, cremalleras, fotoceldas, límites, controles y mantenimiento.</p></div></div></section>
<section class="section"><h2>A quién buscamos</h2><div class="cards"><div class="card">Técnicos con experiencia o ayudantes con deseos de aprender.</div><div class="card">Personas responsables, puntuales y disponibles para trabajar por proyecto.</div><div class="card">Técnicos con herramientas, transporte o disponibilidad para trasladarse.</div></div></section>
<section id="proceso" class="section"><h2>Cómo funciona</h2><div class="steps"><div class="card step"><b>Completa tu solicitud.</b></div><div class="card step"><b>Revisamos tus datos.</b></div><div class="card step"><b>Te contactamos para validar tu perfil.</b></div><div class="card step"><b>Podrás recibir propuestas cuando haya disponibilidad.</b></div></div></section>
<section class="section"><h2>Beneficios realistas</h2><div class="cards"><div class="card">Oportunidad de recibir trabajos por proyecto y participar en instalaciones reales.</div><div class="card">Contacto con una empresa establecida y posibilidad de colaborar en diferentes zonas.</div><div class="card">Pagos acordados antes de cada trabajo y flexibilidad según disponibilidad.</div></div></section>
<section id="formulario" class="section formShell"><div class="card"><h2>Formulario de solicitud</h2><p class="muted">Completa tus datos. Tu ubicación se usa solo para conocer tu zona de disponibilidad; no hacemos seguimiento en tiempo real.</p><div id="err" class="err"></div><form id="f"><div class="progress" id="progress">Paso 1 de 6</div>
<div class="stepPanel active" data-step="1"><div class="grid">${this.input('fullName','Nombre completo *')}${this.input('identityNumber','Cédula *')}${this.input('birthDate','Fecha de nacimiento', 'date')}${this.input('phone','Teléfono *')}${this.input('whatsapp','WhatsApp *')}${this.input('email','Correo electrónico', 'email')}</div></div>
<div class="stepPanel" data-step="2"><div class="grid">${this.input('province','Provincia *')}${this.input('municipality','Municipio *')}${this.input('sector','Sector o comunidad')}${this.input('manualAddress','Dirección escrita')}<div class="full"><button type="button" class="btn sec" id="geo">Usar mi ubicación actual</button><p class="muted" id="geoText">Puedes escribir tu dirección manualmente si prefieres.</p></div></div></div>
<div class="stepPanel" data-step="3"><div class="grid"><div class="field"><label>Especialidad *</label><select name="specialty" id="specialty"><option value="CAMERAS">Cámaras de seguridad</option><option value="GATE_MOTORS">Motores de portones</option><option value="BOTH">Ambas áreas</option></select></div><div class="field"><label>Experiencia *</label><select name="experienceLevel"><option value="NO_EXPERIENCE">Sin experiencia, deseo aprender</option><option value="LESS_THAN_ONE_YEAR">Menos de un año</option><option value="ONE_TO_THREE_YEARS">De uno a tres años</option><option value="MORE_THAN_THREE_YEARS">Más de tres años</option></select></div><div class="field full"><label>Cuéntanos brevemente sobre tu experiencia</label><textarea name="experienceDescription"></textarea></div><div class="full"><b>Conocimientos de cámaras</b><div class="choices skill camera">${this.checks(['Cámaras analógicas','Cámaras IP','DVR','NVR','Conectores BNC','Conectores RJ45','Configuración en celulares','Acceso remoto','Cableado','Mantenimiento'],'cameraSkills')}</div></div><div class="full"><b>Conocimientos de motores</b><div class="choices skill motor">${this.checks(['Motores corredizos','Motores batientes','Cremalleras','Fotoceldas','Programación de controles','Límites de apertura y cierre','Electricidad básica','Soldadura','Diagnóstico','Mantenimiento'],'gateMotorSkills')}</div></div></div></div>
<div class="stepPanel" data-step="4"><div class="grid"><div class="field"><label>¿Tienes herramientas propias? *</label><select name="toolsAvailability"><option value="YES">Sí</option><option value="SOME">Algunas</option><option value="NO">No</option></select></div><div class="field"><label>Transporte *</label><select name="transportation"><option>Moto</option><option>Carro</option><option>Camioneta</option><option>Transporte público</option><option>No tengo transporte</option></select></div><div class="field"><label>Disponibilidad *</label><select name="availability"><option>Lunes a sábado</option><option>Algunos días</option><option>Fines de semana</option><option>Cuando sea contactado</option></select></div><div class="field"><label>Otras herramientas</label><input name="otherTools"></div><div class="full choices">${this.checks(['Taladro','Rotomartillo','Escalera','Multímetro','Ponchadora RJ45','Probador de cable','Herramientas manuales','Pulidora','Soldadora','Laptop'],'tools')}</div><label class="choice"><input type="checkbox" name="canTravel"> Disponible para viajar</label><label class="choice"><input type="checkbox" name="canWorkWeekends"> Puede trabajar fines de semana</label></div></div>
<div class="stepPanel" data-step="5"><div class="grid"><div class="field"><label>Foto personal</label><input name="profilePhotoFile" type="file" accept="image/png,image/jpeg,image/webp"></div><div class="field"><label>Cédula frontal</label><input name="identityFrontPhotoFile" type="file" accept="image/png,image/jpeg,image/webp,application/pdf"></div><div class="field"><label>Cédula trasera</label><input name="identityBackPhotoFile" type="file" accept="image/png,image/jpeg,image/webp,application/pdf"></div><div class="field"><label>Currículum</label><input name="resumeFile" type="file" accept="application/pdf,.doc,.docx"></div><div class="field full"><label>Evidencias de trabajos</label><input name="workEvidenceFiles" type="file" accept="image/png,image/jpeg,image/webp,application/pdf" multiple></div><div class="field full"><label>Referencias / empresa anterior</label><textarea name="previousCompany"></textarea></div></div><p class="muted">Puedes enviar el formulario aunque no tengas documentos listos. Si adjuntas archivos, se guardarán de forma segura en FullTech.</p></div>
<div class="stepPanel" data-step="6"><div id="summary" class="notice"></div><label class="choice full"><input type="checkbox" name="consentAccepted" required> Declaro que la información suministrada es correcta y autorizo a FullTech SRL a utilizar estos datos para evaluar mi participación en su Red Técnica. Entiendo que completar esta solicitud no representa una contratación laboral ni garantiza la asignación de trabajos.</label></div>
<div class="actions"><button type="button" class="btn sec" id="prev">Anterior</button><button type="button" class="btn" id="next">Siguiente</button><button id="send" class="btn hide">Enviar solicitud</button></div></form><div id="ok" class="ok"><h2>Solicitud recibida</h2><p id="code"></p><p>Gracias por tu interés en formar parte de la Red Técnica FullTech. Revisaremos tu información y podremos contactarte cuando tengamos una oportunidad relacionada con tu perfil.</p><p><a class="btn" href="/">Volver al inicio</a></p></div></div></section></main>
<footer class="foot"><div class="wrap"><b>FullTech SRL</b><p>Centro de Higüey, calle Beller No. 9, detrás del Banco BHD principal, La Altagracia, República Dominicana.</p><p class="privacy">Usamos tus datos únicamente para evaluar tu solicitud. No hacemos rastreo GPS, no garantizamos trabajo fijo y los documentos no se comparten públicamente. © <span id="year"></span> FULLTECH, SRL. Todos los derechos reservados.</p></div></footer>
<script>
const f=document.getElementById('f'),err=document.getElementById('err'),ok=document.getElementById('ok'),panels=[...document.querySelectorAll('.stepPanel')],progress=document.getElementById('progress'),prev=document.getElementById('prev'),next=document.getElementById('next'),send=document.getElementById('send');let step=1;document.getElementById('year').textContent=new Date().getFullYear();
function show(){panels.forEach(p=>p.classList.toggle('active',Number(p.dataset.step)===step));progress.textContent='Paso '+step+' de 6';prev.style.visibility=step===1?'hidden':'visible';next.classList.toggle('hide',step===6);send.classList.toggle('hide',step!==6);if(step===6)summary();}
function data(){const fd=new FormData(f),o={};for(const [k,v] of fd.entries()){if(v instanceof File)continue;o[k]=v}o.canTravel=fd.has('canTravel');o.canWorkWeekends=fd.has('canWorkWeekends');o.consentAccepted=fd.has('consentAccepted');o.cameraSkills=fd.getAll('cameraSkills');o.gateMotorSkills=fd.getAll('gateMotorSkills');o.tools=fd.getAll('tools');return o}
async function uploadOne(name){const input=f.querySelector('[name='+name+']');const file=input?.files?.[0];if(!file)return null;const fd=new FormData();fd.append('file',file);const r=await fetch('/technical-network/public/upload',{method:'POST',body:fd});const j=await r.json();if(!r.ok)throw new Error(j.message||'No fue posible subir '+file.name);return j}
async function uploadMany(name){const input=f.querySelector('[name='+name+']');const files=[...(input?.files||[])];const urls=[];for(const file of files){const fd=new FormData();fd.append('file',file);const r=await fetch('/technical-network/public/upload',{method:'POST',body:fd});const j=await r.json();if(!r.ok)throw new Error(j.message||'No fue posible subir '+file.name);urls.push(j.url||j.path)}return urls}
function summary(){const d=data();document.getElementById('summary').innerHTML='<b>Resumen</b><br>Nombre: '+(d.fullName||'-')+'<br>Teléfono: '+(d.phone||'-')+'<br>Municipio: '+(d.municipality||'-')+'<br>Especialidad: '+(d.specialty||'-')+'<br>Experiencia: '+(d.experienceLevel||'-')+'<br>Transporte: '+(d.transportation||'-')+'<br>Ubicación: '+(d.formattedAddress||d.manualAddress||'-')+'<br>Currículum: '+(d.resumeUrl?'Sí':'No')}
prev.onclick=()=>{if(step>1){step--;show()}};next.onclick=()=>{if(step<6){step++;show()}};show();
document.getElementById('specialty').onchange=e=>{const v=e.target.value;document.querySelector('.camera').style.display=v==='GATE_MOTORS'?'none':'flex';document.querySelector('.motor').style.display=v==='CAMERAS'?'none':'flex'};
function hidden(name,value){let i=f.querySelector('[name='+name+']');if(!i){i=document.createElement('input');i.type='hidden';i.name=name;f.appendChild(i)}i.value=value??''}
document.getElementById('geo').onclick=()=>{const t=document.getElementById('geoText');if(!navigator.geolocation){t.textContent='Tu navegador no permite ubicación. Puedes escribir tu dirección manualmente.';return}t.textContent='Solicitando ubicación...';navigator.geolocation.getCurrentPosition(pos=>{const c=pos.coords;hidden('latitude',c.latitude);hidden('longitude',c.longitude);hidden('locationAccuracy',c.accuracy);hidden('locationCapturedAt',new Date().toISOString());hidden('locationSource','GPS');t.textContent='Ubicación capturada. Precisión aproximada: '+Math.round(c.accuracy)+' metros. Confirma o corrige tu dirección escrita.'},()=>{t.textContent='No fue posible obtener tu ubicación. Puedes escribir tu dirección manualmente.'},{enableHighAccuracy:true,timeout:12000})};
f.addEventListener('submit',async e=>{e.preventDefault();err.style.display='none';send.disabled=true;send.textContent='Enviando...';const payload=data();payload.consentAcceptedAt=new Date().toISOString();
try{const profile=await uploadOne('profilePhotoFile'),front=await uploadOne('identityFrontPhotoFile'),back=await uploadOne('identityBackPhotoFile'),resume=await uploadOne('resumeFile');payload.workEvidencePhotoUrls=await uploadMany('workEvidenceFiles');if(profile)payload.profilePhotoUrl=profile.url||profile.path;if(front)payload.identityFrontPhotoUrl=front.url||front.path;if(back)payload.identityBackPhotoUrl=back.url||back.path;if(resume){payload.resumeUrl=resume.url||resume.path;payload.resumeOriginalName=resume.originalName;payload.resumeMimeType=resume.mimeType;payload.resumeSizeBytes=resume.sizeBytes}const r=await fetch('/technical-network/public/applications',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});const j=await r.json();if(!r.ok)throw new Error(j.message||'No fue posible enviar la solicitud.');
f.style.display='none';ok.style.display='block';document.getElementById('code').textContent='Código de solicitud: '+j.applicationCode;}catch(ex){err.textContent=ex.message;err.style.display='block';send.disabled=false;send.textContent='Enviar solicitud';}});
</script></body></html>`;
  }

  private input(name: string, label: string, type = 'text') {
    return `<div class="field"><label>${label}</label><input name="${name}" type="${type}"></div>`;
  }

  private checks(options: string[], name: string) {
    return options.map((option) => `<label class="choice"><input type="checkbox" name="${name}" value="${option}">${option}</label>`).join('');
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
      manualAddress: this.text(dto.manualAddress),
      formattedAddress: this.text(dto.formattedAddress),
      latitude: this.coordinate(dto.latitude, -90, 90),
      longitude: this.coordinate(dto.longitude, -180, 180),
      locationAccuracy: this.positiveNumber(dto.locationAccuracy),
      locationCapturedAt: this.date(dto.locationCapturedAt),
      locationSource: this.enumText(dto.locationSource, ['GPS', 'MANUAL', 'GPS_CORRECTED'], ''),
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
      resumeUrl: this.text(dto.resumeUrl),
      resumeOriginalName: this.text(dto.resumeOriginalName),
      resumeMimeType: this.text(dto.resumeMimeType),
      resumeSizeBytes: this.intNumber(dto.resumeSizeBytes),
      referenceName: this.text(dto.referenceName),
      referencePhone: this.digits(dto.referencePhone),
      previousCompany: this.text(dto.previousCompany),
      internalNotes: this.text(dto.internalNotes),
      consentAccepted: this.bool(dto.consentAccepted),
      consentAcceptedAt: this.date(dto.consentAcceptedAt) ?? (this.bool(dto.consentAccepted) ? new Date() : null),
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
      manualAddress: row.manual_address,
      formattedAddress: row.formatted_address,
      latitude: row.latitude,
      longitude: row.longitude,
      locationAccuracy: row.location_accuracy,
      locationCapturedAt: row.location_captured_at,
      locationSource: row.location_source,
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
      resumeUrl: row.resume_url,
      resumeOriginalName: row.resume_original_name,
      resumeMimeType: row.resume_mime_type,
      resumeSizeBytes: row.resume_size_bytes == null ? null : Number(row.resume_size_bytes),
      referenceName: row.reference_name,
      referencePhone: row.reference_phone,
      previousCompany: row.previous_company,
      status: row.status,
      rejectionReason: row.rejection_reason,
      internalNotes: row.internal_notes,
      submittedAt: row.submitted_at,
      reviewedAt: row.reviewed_at,
      reviewedById: row.reviewed_by_id,
      consentAccepted: row.consent_accepted,
      consentAcceptedAt: row.consent_accepted_at,
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
      manualAddress: row.manual_address,
      formattedAddress: row.formatted_address,
      latitude: row.latitude,
      longitude: row.longitude,
      locationAccuracy: row.location_accuracy,
      locationCapturedAt: row.location_captured_at,
      locationSource: row.location_source,
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
      resumeUrl: row.resume_url,
      resumeOriginalName: row.resume_original_name,
      resumeMimeType: row.resume_mime_type,
      resumeSizeBytes: row.resume_size_bytes == null ? null : Number(row.resume_size_bytes),
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

  private positiveNumber(value: unknown) {
    if (value == null || value === '') return null;
    const n = Number(value);
    return Number.isFinite(n) && n >= 0 ? n : null;
  }

  private intNumber(value: unknown) {
    if (value == null || value === '') return null;
    const n = Number(value);
    return Number.isFinite(n) && n >= 0 ? Math.round(n) : null;
  }

  private coordinate(value: unknown, min: number, max: number) {
    if (value == null || value === '') return null;
    const n = Number(value);
    return Number.isFinite(n) && n >= min && n <= max ? n : null;
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
