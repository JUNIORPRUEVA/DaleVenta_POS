-- CreateEnum
CREATE TYPE "Role" AS ENUM ('ADMIN', 'CAJERO', 'ASISTENTE', 'MARKETING', 'VENDEDOR', 'TECNICO');

-- CreateEnum
CREATE TYPE "company_status" AS ENUM ('ACTIVE', 'SUSPENDED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "company_plan" AS ENUM ('STANDARD', 'ENTERPRISE');

-- CreateEnum
CREATE TYPE "license_status" AS ENUM ('TRIAL', 'ACTIVE', 'BLOCKED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "company_member_role" AS ENUM ('OWNER', 'ADMIN', 'MANAGER', 'CASHIER', 'SELLER', 'WAREHOUSE', 'ACCOUNTANT', 'VIEWER');

-- CreateEnum
CREATE TYPE "company_member_status" AS ENUM ('ACTIVE', 'INVITED', 'DISABLED', 'REMOVED');

-- CreateEnum
CREATE TYPE "purchase_order_status" AS ENUM ('DRAFT', 'PENDING_APPROVAL', 'APPROVED', 'SENT', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "PunchType" AS ENUM ('ENTRADA_LABOR', 'SALIDA_LABOR', 'SALIDA_PERMISO', 'ENTRADA_PERMISO', 'SALIDA_ALMUERZO', 'ENTRADA_ALMUERZO');

-- CreateEnum
CREATE TYPE "CloseType" AS ENUM ('CAPSULAS', 'POS', 'TIENDA', 'PHYTOEMAGRY');

-- CreateEnum
CREATE TYPE "DepositOrderStatus" AS ENUM ('PENDING', 'EXECUTED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "FiscalInvoiceKind" AS ENUM ('SALE_CARD', 'SALE', 'PURCHASE');

-- CreateEnum
CREATE TYPE "product_tax_treatment" AS ENUM ('INHERIT', 'TAXABLE', 'EXEMPT');

-- CreateEnum
CREATE TYPE "tax_price_mode" AS ENUM ('NO_TAX', 'TAX_ADDED', 'TAX_INCLUDED');

-- CreateEnum
CREATE TYPE "PayableProviderKind" AS ENUM ('PERSON', 'COMPANY');

-- CreateEnum
CREATE TYPE "PayableFrequency" AS ENUM ('ONE_TIME', 'MONTHLY', 'BIWEEKLY');

-- CreateEnum
CREATE TYPE "PayrollPeriodStatus" AS ENUM ('OPEN', 'CLOSED');

-- CreateEnum
CREATE TYPE "PayrollEntryType" AS ENUM ('AUSENCIA', 'TARDE', 'FERIADO_TRABAJADO', 'COMISION_SERVICIO', 'COMISION_VENTAS', 'BONIFICACION', 'PAGO_COMBUSTIBLE', 'ADELANTO', 'DESCUENTO', 'OTRO');

-- CreateEnum
CREATE TYPE "PayrollServiceCommissionStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'CANCELED');

-- CreateEnum
CREATE TYPE "PayrollPaymentStatus" AS ENUM ('DRAFT', 'PAID');

-- CreateEnum
CREATE TYPE "CompanyManualEntryKind" AS ENUM ('GENERAL_RULE', 'ROLE_RULE', 'POLICY', 'WARRANTY_POLICY', 'RESPONSIBILITY', 'PRODUCT_SERVICE', 'PRICE_RULE', 'SERVICE_RULE', 'MODULE_GUIDE');

-- CreateEnum
CREATE TYPE "CompanyManualAudience" AS ENUM ('GENERAL', 'ROLE_SPECIFIC');

-- CreateEnum
CREATE TYPE "ServiceType" AS ENUM ('INSTALLATION', 'MAINTENANCE', 'WARRANTY', 'POS_SUPPORT', 'OTHER');

-- CreateEnum
CREATE TYPE "ServiceStatus" AS ENUM ('RESERVED', 'SURVEY', 'SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'WARRANTY', 'CLOSED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "OrderType" AS ENUM ('RESERVA', 'SERVICIO', 'LEVANTAMIENTO', 'GARANTIA', 'MANTENIMIENTO', 'INSTALACION');

-- CreateEnum
CREATE TYPE "OrderState" AS ENUM ('PENDING', 'CONFIRMED', 'ASSIGNED', 'IN_PROGRESS', 'FINALIZED', 'CANCELLED', 'RESCHEDULED');

-- CreateEnum
CREATE TYPE "ServiceAssignmentRole" AS ENUM ('LEAD', 'ASSISTANT');

-- CreateEnum
CREATE TYPE "ServiceUpdateType" AS ENUM ('STATUS_CHANGE', 'NOTE', 'SCHEDULE_CHANGE', 'ASSIGNMENT_CHANGE', 'PAYMENT_UPDATE', 'STEP_UPDATE', 'FILE_UPLOAD', 'WARRANTY_CREATED');

-- CreateEnum
CREATE TYPE "ServicePhaseType" AS ENUM ('RESERVA', 'LEVANTAMIENTO', 'INSTALACION', 'MANTENIMIENTO', 'GARANTIA');

-- CreateEnum
CREATE TYPE "ChecklistTemplateType" AS ENUM ('HERRAMIENTAS', 'PRODUCTOS', 'INSTALACION');

-- CreateEnum
CREATE TYPE "AdminOrderPhase" AS ENUM ('RESERVA', 'CONFIRMACION', 'PROGRAMACION', 'EJECUCION', 'REVISION', 'FACTURACION', 'CIERRE', 'CANCELADA');

-- CreateEnum
CREATE TYPE "AdminOrderStatus" AS ENUM ('PENDIENTE', 'CONFIRMADA', 'ASIGNADA', 'EN_CAMINO', 'EN_PROCESO', 'FINALIZADA', 'REAGENDADA', 'CANCELADA', 'CERRADA');

-- CreateEnum
CREATE TYPE "WorkShiftKind" AS ENUM ('NORMAL', 'REDUCED', 'SPECIAL');

-- CreateEnum
CREATE TYPE "WorkAssignmentStatus" AS ENUM ('WORK', 'DAY_OFF', 'EXCEPTION_OFF');

-- CreateEnum
CREATE TYPE "WorkScheduleExceptionType" AS ENUM ('HOLIDAY', 'VACATION', 'SICK', 'LEAVE', 'LICENSE', 'ABSENCE', 'BLOCKED_DAY');

-- CreateEnum
CREATE TYPE "WorkWeekScheduleStatus" AS ENUM ('GENERATED');

-- CreateEnum
CREATE TYPE "WorkScheduleAuditAction" AS ENUM ('GENERATE_WEEK', 'REGENERATE_WEEK', 'UPDATE_SETTINGS', 'UPDATE_EMPLOYEE_CONFIG', 'CREATE_EXCEPTION', 'UPDATE_EXCEPTION', 'DELETE_EXCEPTION', 'MANUAL_MOVE_DAY_OFF', 'MANUAL_SWAP_DAY_OFF');

-- CreateEnum
CREATE TYPE "SalidaTecnicaEstado" AS ENUM ('INICIADA', 'LLEGADA', 'FINALIZADA', 'APROBADA', 'RECHAZADA', 'PAGADA');

-- CreateEnum
CREATE TYPE "PagoCombustibleTecnicoEstado" AS ENUM ('PENDIENTE', 'PAGADO', 'CANCELADO');

-- CreateEnum
CREATE TYPE "NotificationChannel" AS ENUM ('WHATSAPP');

-- CreateEnum
CREATE TYPE "NotificationStatus" AS ENUM ('PENDING', 'SENDING', 'SENT', 'FAILED');

-- CreateEnum
CREATE TYPE "marketing_research_status" AS ENUM ('DRAFT', 'APPROVED', 'REJECTED', 'USED');

-- CreateEnum
CREATE TYPE "marketing_learning_status" AS ENUM ('ACTIVE', 'DISCARDED');

-- CreateEnum
CREATE TYPE "marketing_story_type" AS ENUM ('SALES', 'TRUST', 'EDUCATIONAL');

-- CreateEnum
CREATE TYPE "marketing_story_status" AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'REGENERATED');

-- CreateEnum
CREATE TYPE "marketing_platform_format" AS ENUM ('STORY_9_16');

-- CreateEnum
CREATE TYPE "marketing_image_status" AS ENUM ('PENDING', 'QUEUED', 'PROCESSING', 'GENERATED', 'FAILED');

-- CreateEnum
CREATE TYPE "marketing_campaign_status" AS ENUM ('DRAFT', 'READY', 'PUBLISHING', 'ACTIVE', 'PAUSED', 'ERROR', 'REJECTED');

-- CreateEnum
CREATE TYPE "marketing_campaign_phase" AS ENUM ('DESIGN', 'COPY_SEGMENTATION', 'PUBLISH');

-- CreateEnum
CREATE TYPE "marketing_campaign_type" AS ENUM ('META_ADS');

-- CreateEnum
CREATE TYPE "marketing_campaign_currency" AS ENUM ('DOP', 'USD');

-- CreateEnum
CREATE TYPE "marketing_social_account_type" AS ENUM ('FACEBOOK', 'INSTAGRAM', 'WHATSAPP');

-- CreateEnum
CREATE TYPE "NotificationContentType" AS ENUM ('TEXT', 'DOCUMENT');

-- CreateEnum
CREATE TYPE "crm_commercial_customer_status" AS ENUM ('NUEVO', 'INTERESADO', 'COTIZACION', 'NEGOCIACION', 'PENDIENTE_PAGO', 'GANADO', 'PERDIDO', 'SEGUIMIENTO', 'SOPORTE', 'COBRO_PENDIENTE');

-- CreateEnum
CREATE TYPE "crm_commercial_followup_task_status" AS ENUM ('PENDIENTE', 'COMPLETADA', 'VENCIDA', 'CANCELADA');

-- CreateEnum
CREATE TYPE "crm_commercial_followup_task_priority" AS ENUM ('BAJA', 'NORMAL', 'ALTA', 'URGENTE');

-- CreateEnum
CREATE TYPE "crm_commercial_library_item_type" AS ENUM ('TEXT', 'IMAGE', 'VIDEO', 'AUDIO', 'DOCUMENT', 'LOCATION', 'BANK_ACCOUNT', 'BUSINESS_HOURS', 'CATALOG', 'QUOTE_TEMPLATE', 'LINK', 'PROMOTION', 'WARRANTY', 'FAQ', 'FOLLOW_UP');

-- CreateEnum
CREATE TYPE "ServiceOrderNotificationJobKind" AS ENUM ('THIRTY_MINUTES_BEFORE', 'FIFTEEN_MINUTES_PENDING');

-- CreateEnum
CREATE TYPE "ServiceOrderNotificationJobStatus" AS ENUM ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "ServiceClosingApprovalStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

-- CreateEnum
CREATE TYPE "ServiceClosingSignatureStatus" AS ENUM ('PENDING', 'SIGNED', 'SKIPPED');

-- CreateEnum
CREATE TYPE "WarrantyDurationUnit" AS ENUM ('DAYS', 'MONTHS', 'YEARS');

-- CreateEnum
CREATE TYPE "service_order_category" AS ENUM ('camara', 'motor_porton', 'alarma', 'cerco_electrico', 'intercom', 'punto_venta');

-- CreateEnum
CREATE TYPE "service_order_type" AS ENUM ('instalacion', 'mantenimiento', 'levantamiento', 'garantia');

-- CreateEnum
CREATE TYPE "service_order_status" AS ENUM ('pendiente', 'en_proceso', 'en_pausa', 'pospuesta', 'finalizado', 'cancelado');

-- CreateEnum
CREATE TYPE "service_evidence_type" AS ENUM ('referencia_texto', 'referencia_imagen', 'referencia_video', 'evidencia_texto', 'evidencia_imagen', 'evidencia_video');

-- CreateEnum
CREATE TYPE "service_report_type" AS ENUM ('requerimiento_cliente', 'servicio_finalizado', 'otros');

-- CreateEnum
CREATE TYPE "employee_warning_severity" AS ENUM ('low', 'medium', 'high', 'critical');

-- CreateEnum
CREATE TYPE "employee_warning_status" AS ENUM ('draft', 'issued', 'pending_signature', 'signed', 'refused_to_sign', 'annulled', 'archived');

-- CreateEnum
CREATE TYPE "employee_warning_type" AS ENUM ('verbal_documented', 'written', 'reincidence', 'other');

-- CreateEnum
CREATE TYPE "employee_warning_category" AS ENUM ('tardiness', 'absence', 'misconduct', 'negligence', 'policy_violation', 'insubordination', 'other');

-- CreateEnum
CREATE TYPE "employee_warning_signature_type" AS ENUM ('signed', 'refused');

-- CreateEnum
CREATE TYPE "whatsapp_message_direction" AS ENUM ('INCOMING', 'OUTGOING');

-- CreateEnum
CREATE TYPE "whatsapp_message_type" AS ENUM ('TEXT', 'IMAGE', 'AUDIO', 'VIDEO', 'DOCUMENT', 'STICKER', 'OTHER', 'CONVERSATION');

-- CreateTable
CREATE TABLE "companies" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "status" "company_status" NOT NULL DEFAULT 'ACTIVE',
    "plan" "company_plan" NOT NULL DEFAULT 'STANDARD',
    "license_status" "license_status" NOT NULL DEFAULT 'TRIAL',
    "license_key" TEXT,
    "trial_started_at" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,
    "trial_ends_at" TIMESTAMP(3),
    "license_activated_at" TIMESTAMP(3),
    "license_expires_at" TIMESTAMP(3),
    "license_blocked_at" TIMESTAMP(3),
    "license_notes" TEXT,
    "max_users" INTEGER NOT NULL DEFAULT 2,
    "max_products" INTEGER NOT NULL DEFAULT 100,
    "tax_enabled" BOOLEAN NOT NULL DEFAULT false,
    "default_tax_id" UUID,
    "default_tax_rate" DECIMAL(5,4) NOT NULL DEFAULT 0,
    "prices_include_tax" BOOLEAN NOT NULL DEFAULT false,
    "ncf_enabled" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "companies_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "open_sales_ticket_states" (
    "company_id" UUID NOT NULL,
    "active_ticket_id" TEXT,
    "tickets" JSONB NOT NULL DEFAULT '[]',
    "updated_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "open_sales_ticket_states_pkey" PRIMARY KEY ("company_id")
);

-- CreateTable
CREATE TABLE "company_license_audit_logs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "actor_id" UUID,
    "actor_email" TEXT,
    "action" TEXT NOT NULL,
    "reason" TEXT,
    "before" JSONB,
    "after" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "company_license_audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "company_members" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "role" "company_member_role" NOT NULL DEFAULT 'VIEWER',
    "status" "company_member_status" NOT NULL DEFAULT 'ACTIVE',
    "invited_by" UUID,
    "joined_at" TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "company_members_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "auth_sessions" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "company_id" UUID,
    "refresh_token_hash" TEXT NOT NULL,
    "token_family" UUID NOT NULL,
    "user_agent" TEXT,
    "ip_address" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_used_at" TIMESTAMP(3),
    "expires_at" TIMESTAMP(3) NOT NULL,
    "revoked_at" TIMESTAMP(3),
    "revocation_reason" TEXT,

    CONSTRAINT "auth_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "company_id" UUID,
    "email" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "nombreCompleto" TEXT NOT NULL,
    "telefono" TEXT NOT NULL,
    "numeroFlota" TEXT,
    "telefonoFamiliar" TEXT,
    "cedula" TEXT,
    "fotoCedulaUrl" TEXT,
    "fotoLicenciaUrl" TEXT,
    "fotoPersonalUrl" TEXT,
    "workContractSignatureUrl" TEXT,
    "workContractSignedAt" TIMESTAMP(3),
    "workContractVersion" TEXT,
    "workContractJobTitle" TEXT,
    "workContractSalary" TEXT,
    "workContractPaymentFrequency" TEXT,
    "workContractPaymentMethod" TEXT,
    "workContractWorkSchedule" TEXT,
    "workContractWorkLocation" TEXT,
    "workContractClauseOverrides" JSONB,
    "workContractCustomClauses" TEXT,
    "workContractStartDate" TIMESTAMP(3),
    "edad" INTEGER NOT NULL,
    "tieneHijos" BOOLEAN NOT NULL DEFAULT false,
    "estaCasado" BOOLEAN NOT NULL DEFAULT false,
    "casaPropia" BOOLEAN NOT NULL DEFAULT false,
    "vehiculo" BOOLEAN NOT NULL DEFAULT false,
    "licenciaConducir" BOOLEAN NOT NULL DEFAULT false,
    "fechaIngreso" TIMESTAMP(3),
    "fechaNacimiento" TIMESTAMP(3),
    "cuentaNominaPreferencial" TEXT,
    "habilidades" JSONB,
    "user_permissions" JSONB,
    "role" "Role" NOT NULL,
    "blocked" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "employee_warnings" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "employee_user_id" UUID NOT NULL,
    "created_by_user_id" UUID NOT NULL,
    "warning_number" TEXT NOT NULL,
    "warning_date" TIMESTAMP(3) NOT NULL,
    "incident_date" TIMESTAMP(3) NOT NULL,
    "title" TEXT NOT NULL,
    "category" "employee_warning_category" NOT NULL,
    "severity" "employee_warning_severity" NOT NULL,
    "legal_basis" TEXT,
    "internal_rule_reference" TEXT,
    "description" TEXT NOT NULL,
    "employee_explanation" TEXT,
    "corrective_action" TEXT,
    "consequence_note" TEXT,
    "evidence_notes" TEXT,
    "warning_type" "employee_warning_type" NOT NULL DEFAULT 'written',
    "reason" TEXT,
    "details" TEXT,
    "incident_time" TEXT,
    "incident_place" TEXT,
    "issued_by_user_id" UUID,
    "issued_by_name_snapshot" TEXT,
    "issued_by_position_snapshot" TEXT,
    "internal_notes" TEXT,
    "generated_text" TEXT,
    "employee_name_snapshot" TEXT,
    "employee_cedula_snapshot" TEXT,
    "employee_position_snapshot" TEXT,
    "employee_department_snapshot" TEXT,
    "employee_phone_snapshot" TEXT,
    "company_name_snapshot" TEXT,
    "company_rnc_snapshot" TEXT,
    "company_address_snapshot" TEXT,
    "deleted_at" TIMESTAMP(3),
    "status" "employee_warning_status" NOT NULL DEFAULT 'draft',
    "pdf_url" TEXT,
    "signed_pdf_url" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "submitted_at" TIMESTAMP(3),
    "signed_at" TIMESTAMP(3),
    "refused_at" TIMESTAMP(3),
    "annulled_at" TIMESTAMP(3),
    "annulled_by_user_id" UUID,
    "annulment_reason" TEXT,

    CONSTRAINT "employee_warnings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "employee_warning_evidences" (
    "id" UUID NOT NULL,
    "warning_id" UUID NOT NULL,
    "file_url" TEXT NOT NULL,
    "file_name" TEXT NOT NULL,
    "file_type" TEXT NOT NULL,
    "storage_key" TEXT,
    "uploaded_by_user_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "employee_warning_evidences_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "employee_warning_signatures" (
    "id" UUID NOT NULL,
    "warning_id" UUID NOT NULL,
    "employee_user_id" UUID NOT NULL,
    "signature_type" "employee_warning_signature_type" NOT NULL,
    "signature_image_url" TEXT,
    "typed_name" TEXT NOT NULL,
    "comment" TEXT,
    "ip_address" TEXT,
    "device_info" TEXT,
    "signed_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "employee_warning_signatures_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "employee_warning_audit_logs" (
    "id" UUID NOT NULL,
    "warning_id" UUID NOT NULL,
    "action" TEXT NOT NULL,
    "actor_user_id" UUID,
    "old_status" "employee_warning_status",
    "new_status" "employee_warning_status",
    "metadata_json" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "employee_warning_audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "marketing_flow_configs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT false,
    "paused" BOOLEAN NOT NULL DEFAULT false,
    "daily_stories_count" INTEGER NOT NULL DEFAULT 3,
    "generation_time" TEXT NOT NULL DEFAULT '08:00',
    "auto_regenerate" BOOLEAN NOT NULL DEFAULT false,
    "regenerate_after_hours" INTEGER NOT NULL DEFAULT 6,
    "target_city" TEXT,
    "brand_tone" TEXT,
    "priority_products" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "updated_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "marketing_flow_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "marketing_daily_stories" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "date" DATE NOT NULL,
    "type" "marketing_story_type" NOT NULL,
    "title" TEXT NOT NULL,
    "short_text" TEXT NOT NULL,
    "long_text" TEXT,
    "hashtags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "image_prompt" TEXT,
    "image_url" TEXT,
    "status" "marketing_story_status" NOT NULL DEFAULT 'PENDING',
    "generation_attempt" INTEGER NOT NULL DEFAULT 1,
    "approved_by_user_id" UUID,
    "approved_at" TIMESTAMP(3),
    "rejected_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "research_id" UUID,
    "media_asset_id" UUID,
    "visual_concept" TEXT,
    "design_notes" TEXT,
    "platform_format" "marketing_platform_format" NOT NULL DEFAULT 'STORY_9_16',
    "image_status" "marketing_image_status" NOT NULL DEFAULT 'PENDING',
    "generated_image_url" TEXT,
    "generated_image_provider" TEXT,
    "image_generation_metadata" JSONB,
    "used_research_angle" TEXT,
    "used_offer" TEXT,
    "used_cta" TEXT,
    "published_at" TIMESTAMP(3),
    "facebook_story_id" TEXT,
    "facebook_post_id" TEXT,
    "instagram_post_id" TEXT,
    "instagram_media_id" TEXT,
    "instagram_story_id" TEXT,
    "instagram_container_id" TEXT,
    "instagram_story_container_id" TEXT,
    "instagram_story_published_at" TIMESTAMP(3),
    "facebook_story_status" TEXT,
    "instagram_story_status" TEXT,
    "facebook_post_status" TEXT,
    "instagram_post_status" TEXT,
    "facebook_story_error" TEXT,
    "published_channels" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "publish_targets" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "publish_status" TEXT NOT NULL DEFAULT 'PENDING',
    "publish_error" TEXT,
    "publish_error_code" TEXT,
    "publish_error_details" JSONB,
    "retry_count" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "marketing_daily_stories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "marketing_media_assets" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "file_url" TEXT NOT NULL,
    "thumbnail_url" TEXT,
    "file_name" TEXT NOT NULL,
    "mime_type" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "related_service" TEXT,
    "tags" JSONB,
    "description" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "is_featured" BOOLEAN NOT NULL DEFAULT false,
    "use_count" INTEGER NOT NULL DEFAULT 0,
    "last_used_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "marketing_media_assets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "marketing_ad_campaigns" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "date" DATE NOT NULL,
    "campaign_type" "marketing_campaign_type" NOT NULL DEFAULT 'META_ADS',
    "status" "marketing_campaign_status" NOT NULL DEFAULT 'DRAFT',
    "phase" "marketing_campaign_phase" NOT NULL DEFAULT 'DESIGN',
    "base_image_url" TEXT,
    "final_design_url" TEXT,
    "gallery_asset_id" UUID,
    "headline" TEXT,
    "primary_text" TEXT,
    "description" TEXT,
    "cta" TEXT,
    "hashtags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "ai_angle" TEXT,
    "ai_research_id" UUID,
    "recommended_audience_json" JSONB,
    "final_audience_json" JSONB,
    "daily_budget" DECIMAL(12,2),
    "total_budget" DECIMAL(12,2),
    "currency" "marketing_campaign_currency" NOT NULL DEFAULT 'DOP',
    "whatsapp_phone" TEXT,
    "whatsapp_message_template" TEXT,
    "destination_url" TEXT,
    "start_time" TIMESTAMP(3),
    "end_time" TIMESTAMP(3),
    "keep_running_until_paused" BOOLEAN NOT NULL DEFAULT true,
    "meta_campaign_id" TEXT,
    "meta_ad_set_id" TEXT,
    "meta_creative_id" TEXT,
    "meta_ad_id" TEXT,
    "meta_image_hash" TEXT,
    "meta_video_id" TEXT,
    "meta_media_type" TEXT,
    "meta_media_url" TEXT,
    "meta_media_upload_status" TEXT,
    "meta_publish_progress_json" JSONB,
    "meta_status" TEXT,
    "meta_error" TEXT,
    "meta_error_code" TEXT,
    "meta_error_subcode" TEXT,
    "fbtrace_id" TEXT,
    "created_by_user_id" UUID,
    "updated_by_user_id" UUID,
    "published_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "marketing_ad_campaigns_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "marketing_social_accounts" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "type" "marketing_social_account_type" NOT NULL,
    "account_name" TEXT NOT NULL,
    "username" TEXT,
    "password_encrypted" TEXT,
    "profile_link" TEXT,
    "whatsapp_number" TEXT,
    "whatsapp_wa_link" TEXT,
    "observations" TEXT,
    "avatar_url" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_by_user_id" UUID,
    "updated_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "marketing_social_accounts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "marketing_activity_logs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "action" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "user_id" UUID,
    "metadata" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "marketing_activity_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "marketing_research_configs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "default_research_prompt" TEXT NOT NULL,
    "business_name" TEXT NOT NULL DEFAULT 'FULLTECH SRL',
    "business_location" TEXT NOT NULL DEFAULT 'Higüey, La Altagracia, República Dominicana',
    "business_description" TEXT,
    "main_services" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "priority_services" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "target_market" TEXT,
    "brand_tone" TEXT NOT NULL DEFAULT 'Profesional, confiable, claro, dominicano, directo, moderno, orientado a ventas.',
    "learning_enabled" BOOLEAN NOT NULL DEFAULT true,
    "research_frequency_days" INTEGER NOT NULL DEFAULT 7,
    "require_approval" BOOLEAN NOT NULL DEFAULT false,
    "phone" TEXT,
    "address" TEXT,
    "city" TEXT NOT NULL DEFAULT 'Higüey',
    "province" TEXT NOT NULL DEFAULT 'La Altagracia',
    "country" TEXT NOT NULL DEFAULT 'República Dominicana',
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "service_radius_km" INTEGER NOT NULL DEFAULT 25,
    "service_zones" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "default_cta" TEXT,
    "brand_colors" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "business_hours" TEXT,
    "internal_notes" TEXT,
    "updated_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "marketing_research_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "marketing_researches" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "date" DATE NOT NULL,
    "research_prompt" TEXT NOT NULL,
    "business_snapshot" JSONB,
    "country" TEXT NOT NULL DEFAULT 'República Dominicana',
    "city" TEXT NOT NULL DEFAULT 'Higüey',
    "main_focus" TEXT,
    "services_analyzed" JSONB,
    "market_summary" TEXT,
    "competitor_publishing_patterns" TEXT,
    "common_offers" TEXT,
    "observed_price_ranges" TEXT,
    "strong_angles" JSONB,
    "weak_angles" JSONB,
    "content_opportunities" TEXT,
    "recommended_products" JSONB,
    "recommended_content_types" JSONB,
    "recommended_offers" JSONB,
    "recommended_hooks" JSONB,
    "recommended_ctas" JSONB,
    "do_more_of_this" JSONB,
    "avoid_this" JSONB,
    "confidence_score" DOUBLE PRECISION NOT NULL DEFAULT 0.5,
    "data_sources" JSONB,
    "status" "marketing_research_status" NOT NULL DEFAULT 'DRAFT',
    "forced_by_user_id" UUID,
    "approved_by_user_id" UUID,
    "approved_at" TIMESTAMP(3),
    "rejected_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "marketing_researches_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "marketing_learning_memories" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "category" TEXT NOT NULL,
    "insight" TEXT NOT NULL,
    "source_research_id" UUID,
    "score" DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    "status" "marketing_learning_status" NOT NULL DEFAULT 'ACTIVE',
    "reason" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "marketing_learning_memories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_whatsapp_instances" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "instance_name" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "phone_number" TEXT,
    "webhook_enabled" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_whatsapp_instances_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "whatsapp_conversations" (
    "id" UUID NOT NULL,
    "instance_id" UUID NOT NULL,
    "remote_jid" TEXT NOT NULL,
    "remote_phone" TEXT,
    "remote_name" TEXT,
    "last_message_at" TIMESTAMP(3),
    "unread_count" INTEGER NOT NULL DEFAULT 0,
    "bot_paused" BOOLEAN NOT NULL DEFAULT false,
    "bot_paused_at" TIMESTAMP(3),
    "bot_paused_by_user_id" UUID,
    "bot_pause_reason" TEXT,
    "assigned_human_user_id" UUID,
    "last_human_message_at" TIMESTAMP(3),
    "bot_last_reply_at" TIMESTAMP(3),
    "bot_skipped_reason" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "whatsapp_conversations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "whatsapp_messages" (
    "id" UUID NOT NULL,
    "conversation_id" UUID NOT NULL,
    "evolution_id" TEXT,
    "direction" "whatsapp_message_direction" NOT NULL,
    "message_type" "whatsapp_message_type" NOT NULL DEFAULT 'TEXT',
    "body" TEXT,
    "media_url" TEXT,
    "media_mime_type" TEXT,
    "media_storage_key" TEXT,
    "media_file_size" INTEGER,
    "original_file_name" TEXT,
    "playable_storage_key" TEXT,
    "playable_mime_type" TEXT,
    "media_status" TEXT,
    "media_error" TEXT,
    "caption" TEXT,
    "sender_name" TEXT,
    "sent_at" TIMESTAMP(3) NOT NULL,
    "ai_generated" BOOLEAN NOT NULL DEFAULT false,
    "ai_model" TEXT,
    "ai_prompt_version" TEXT,
    "ai_error" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "raw_payload" JSONB,

    CONSTRAINT "whatsapp_messages_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "whatsapp_ai_media_summaries" (
    "id" UUID NOT NULL,
    "message_id" UUID NOT NULL,
    "media_type" TEXT NOT NULL,
    "summary" TEXT,
    "evidence" JSONB,
    "transcription_status" TEXT NOT NULL DEFAULT 'not_applicable',
    "transcription_text" TEXT,
    "model" TEXT,
    "generated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "whatsapp_ai_media_summaries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "whatsapp_ai_analysis_reports" (
    "id" UUID NOT NULL,
    "conversation_id" UUID,
    "scope" TEXT NOT NULL,
    "date_range_key" TEXT NOT NULL,
    "start_at" TIMESTAMP(3) NOT NULL,
    "end_at" TIMESTAMP(3) NOT NULL,
    "message_fingerprint" TEXT NOT NULL,
    "risk_level" TEXT NOT NULL,
    "summary" TEXT NOT NULL,
    "alerts" JSONB,
    "image_summaries" JSONB,
    "audio_transcription_status" JSONB,
    "report" JSONB NOT NULL,
    "generated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "generated_by" UUID,

    CONSTRAINT "whatsapp_ai_analysis_reports_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_locations" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "latitude" DOUBLE PRECISION NOT NULL,
    "longitude" DOUBLE PRECISION NOT NULL,
    "accuracyMeters" DOUBLE PRECISION,
    "altitudeMeters" DOUBLE PRECISION,
    "headingDegrees" DOUBLE PRECISION,
    "speedMps" DOUBLE PRECISION,
    "recordedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_locations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "app_config" (
    "id" TEXT NOT NULL DEFAULT 'global',
    "company_id" UUID,
    "companyName" TEXT NOT NULL DEFAULT '',
    "rnc" TEXT NOT NULL DEFAULT '',
    "phone" TEXT NOT NULL DEFAULT '',
    "phone_preferential" TEXT NOT NULL DEFAULT '',
    "address" TEXT NOT NULL DEFAULT '',
    "description" TEXT NOT NULL DEFAULT '',
    "instagram_url" TEXT NOT NULL DEFAULT '',
    "facebook_url" TEXT NOT NULL DEFAULT '',
    "website_url" TEXT NOT NULL DEFAULT '',
    "gps_location_url" TEXT NOT NULL DEFAULT '',
    "business_hours" TEXT NOT NULL DEFAULT '',
    "bank_accounts" JSONB NOT NULL DEFAULT '[]',
    "legal_representative_name" TEXT NOT NULL DEFAULT '',
    "legal_representative_cedula" TEXT NOT NULL DEFAULT '',
    "legal_representative_role" TEXT NOT NULL DEFAULT '',
    "legal_representative_nationality" TEXT NOT NULL DEFAULT '',
    "legal_representative_civil_status" TEXT NOT NULL DEFAULT '',
    "logoBase64" TEXT,
    "openAiApiKey" TEXT,
    "openAiModel" TEXT NOT NULL DEFAULT 'gpt-4o-mini',
    "evolution_api_base_url" TEXT NOT NULL DEFAULT '',
    "evolution_api_instance_name" TEXT NOT NULL DEFAULT '',
    "evolution_api_api_key" TEXT,
    "whatsapp_webhook_enabled" BOOLEAN NOT NULL DEFAULT false,
    "operations_tech_can_view_all_services" BOOLEAN NOT NULL DEFAULT false,
    "admin_authorization_pin_hash" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "app_config_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_execution_reports" (
    "id" UUID NOT NULL,
    "service_id" UUID NOT NULL,
    "technician_id" UUID NOT NULL,
    "phase" "ServicePhaseType" NOT NULL,
    "arrived_at" TIMESTAMP(3),
    "started_at" TIMESTAMP(3),
    "finished_at" TIMESTAMP(3),
    "notes" TEXT,
    "checklist_data" JSONB,
    "phase_specific_data" JSONB,
    "client_approved" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "service_execution_reports_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_execution_changes" (
    "id" UUID NOT NULL,
    "service_id" UUID NOT NULL,
    "execution_report_id" UUID NOT NULL,
    "created_by_user_id" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "quantity" DECIMAL(12,3),
    "extra_cost" DECIMAL(12,2),
    "client_approved" BOOLEAN,
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "service_execution_changes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_categories" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "service_categories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_phases" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "order_index" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "service_phases_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "checklist_templates" (
    "id" UUID NOT NULL,
    "category_id" UUID NOT NULL,
    "phase_id" UUID NOT NULL,
    "type" "ChecklistTemplateType" NOT NULL,
    "title" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "checklist_templates_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "checklist_items" (
    "id" UUID NOT NULL,
    "template_id" UUID NOT NULL,
    "label" TEXT NOT NULL,
    "is_required" BOOLEAN NOT NULL DEFAULT true,
    "order_index" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "checklist_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "checklist_executions" (
    "id" UUID NOT NULL,
    "service_order_id" UUID NOT NULL,
    "template_id" UUID NOT NULL,
    "checklist_item_id" UUID NOT NULL,
    "is_checked" BOOLEAN NOT NULL DEFAULT false,
    "checked_at" TIMESTAMP(3),
    "checked_by" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "checklist_executions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notification_outbox" (
    "id" UUID NOT NULL,
    "channel" "NotificationChannel" NOT NULL DEFAULT 'WHATSAPP',
    "status" "NotificationStatus" NOT NULL DEFAULT 'PENDING',
    "content_type" "NotificationContentType" NOT NULL DEFAULT 'TEXT',
    "template_key" TEXT NOT NULL,
    "dedupe_key" TEXT,
    "message_text" TEXT NOT NULL,
    "media_base64" TEXT,
    "media_file_name" TEXT,
    "media_mime_type" TEXT,
    "payload" JSONB,
    "recipient_user_id" UUID,
    "to_number" TEXT NOT NULL,
    "to_number_normalized" TEXT NOT NULL DEFAULT '',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "next_attempt_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "locked_at" TIMESTAMP(3),
    "locked_by" TEXT,
    "last_error" TEXT,
    "last_status_code" INTEGER,
    "sent_at" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "notification_outbox_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_order_notification_jobs" (
    "id" UUID NOT NULL,
    "order_id" UUID NOT NULL,
    "kind" "ServiceOrderNotificationJobKind" NOT NULL,
    "status" "ServiceOrderNotificationJobStatus" NOT NULL DEFAULT 'PENDING',
    "dedupe_key" TEXT NOT NULL,
    "run_at" TIMESTAMP(3) NOT NULL,
    "payload" JSONB,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "locked_at" TIMESTAMP(3),
    "locked_by" TEXT,
    "last_error" TEXT,
    "completed_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "service_order_notification_jobs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Punch" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "type" "PunchType" NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Punch_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Product" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "nombre" TEXT NOT NULL,
    "codigo" TEXT,
    "categoria" TEXT NOT NULL,
    "costo" DECIMAL(12,2) NOT NULL,
    "precio" DECIMAL(12,2) NOT NULL,
    "stock" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "tax_treatment" "product_tax_treatment" NOT NULL DEFAULT 'INHERIT',
    "tax_rate" DECIMAL(5,4),
    "tax_price_mode" "tax_price_mode",
    "imagen" TEXT,
    "image_storage_provider" TEXT,
    "image_key" TEXT,
    "image_mime_type" TEXT,
    "image_original_file_name" TEXT,
    "image_updated_at" TIMESTAMP(3),

    CONSTRAINT "Product_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "taxes" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "rate" DECIMAL(5,4) NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "is_default" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "taxes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "suppliers" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "business_id" UUID,
    "commercial_name" TEXT NOT NULL,
    "legal_name" TEXT,
    "tax_id" TEXT,
    "contact_name" TEXT,
    "phone" TEXT,
    "whatsapp" TEXT,
    "email" TEXT,
    "address" TEXT,
    "city" TEXT,
    "country" TEXT,
    "website" TEXT,
    "payment_terms" TEXT,
    "estimated_delivery_days" INTEGER,
    "notes" TEXT,
    "logo" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "purchase_invoices" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "supplier_id" UUID NOT NULL,
    "purchase_order_id" UUID,
    "invoice_number" TEXT,
    "invoice_date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "amount" DECIMAL(12,2),
    "currency" TEXT NOT NULL DEFAULT 'DOP',
    "file_name" TEXT NOT NULL,
    "file_url" TEXT NOT NULL,
    "storage_key" TEXT NOT NULL,
    "mime_type" TEXT NOT NULL,
    "file_size" INTEGER NOT NULL,
    "notes" TEXT,
    "uploaded_by" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "purchase_invoices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "purchase_order_sequences" (
    "scope" TEXT NOT NULL,
    "next_value" INTEGER NOT NULL DEFAULT 1,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "purchase_order_sequences_pkey" PRIMARY KEY ("scope")
);

-- CreateTable
CREATE TABLE "purchase_orders" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "business_id" UUID,
    "branch_id" UUID,
    "order_number" TEXT NOT NULL,
    "supplier_id" UUID,
    "status" "purchase_order_status" NOT NULL DEFAULT 'DRAFT',
    "order_date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expected_delivery_date" TIMESTAMP(3),
    "subtotal" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "discount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "shipping_cost" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "additional_cost" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "tax" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "total" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "payment_terms" TEXT,
    "payment_method" TEXT,
    "shipping_method" TEXT,
    "notes" TEXT,
    "supplier_instructions" TEXT,
    "created_by" UUID NOT NULL,
    "approved_by" UUID,
    "approved_at" TIMESTAMP(3),
    "sent_at" TIMESTAMP(3),
    "cancelled_at" TIMESTAMP(3),
    "cancellation_reason" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "purchase_orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "purchase_order_items" (
    "id" UUID NOT NULL,
    "purchase_order_id" UUID NOT NULL,
    "product_id" UUID,
    "external_product_id" UUID,
    "product_name_snapshot" TEXT NOT NULL,
    "product_code_snapshot" TEXT,
    "description_snapshot" TEXT,
    "image_snapshot" TEXT,
    "quantity" DECIMAL(12,3) NOT NULL,
    "received_quantity" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "pending_quantity" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "unit_cost" DECIMAL(12,2) NOT NULL,
    "actual_unit_cost" DECIMAL(12,2),
    "subtotal" DECIMAL(12,2) NOT NULL,
    "supplier_id" UUID,
    "notes" TEXT,
    "create_inventory_product_on_receipt" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "purchase_order_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "purchase_receipts" (
    "id" UUID NOT NULL,
    "purchase_order_id" UUID NOT NULL,
    "supplier_invoice_number" TEXT,
    "receipt_date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "notes" TEXT,
    "invoice_image" TEXT,
    "received_by" UUID NOT NULL,
    "inventory_updated" BOOLEAN NOT NULL DEFAULT false,
    "inventory_updated_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "purchase_receipts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "purchase_receipt_items" (
    "id" UUID NOT NULL,
    "purchase_receipt_id" UUID NOT NULL,
    "purchase_order_item_id" UUID NOT NULL,
    "quantity_received" DECIMAL(12,3) NOT NULL,
    "unit_cost" DECIMAL(12,2) NOT NULL,
    "condition" TEXT,
    "notes" TEXT,
    "inventory_movement_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "purchase_receipt_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "website_product_overrides" (
    "id" UUID NOT NULL,
    "product_id" TEXT NOT NULL,
    "title" TEXT,
    "description" TEXT,
    "category" TEXT,
    "image_url" TEXT,
    "extra_image_urls" JSONB,
    "visible" BOOLEAN NOT NULL DEFAULT true,
    "featured" BOOLEAN NOT NULL DEFAULT false,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "seo_title" TEXT,
    "seo_description" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "website_product_overrides_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Client" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "nombre" TEXT NOT NULL,
    "telefono" TEXT NOT NULL,
    "phoneNormalized" TEXT NOT NULL DEFAULT '',
    "email" TEXT,
    "direccion" TEXT,
    "notas" TEXT,
    "tax_id" TEXT,
    "business_name" TEXT,
    "tax_id_type" TEXT,
    "latitude" DECIMAL(10,8),
    "longitude" DECIMAL(11,8),
    "location_url" TEXT,
    "lastActivityAt" TIMESTAMP(3),
    "isDeleted" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Client_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crm_commercial_customers" (
    "id" UUID NOT NULL,
    "client_id" UUID,
    "nombre" TEXT NOT NULL,
    "telefono" TEXT NOT NULL,
    "direccion" TEXT,
    "ciudad" TEXT,
    "estado_actual" "crm_commercial_customer_status" NOT NULL DEFAULT 'NUEVO',
    "etiqueta" TEXT,
    "responsable_user_id" UUID,
    "ultima_interaccion" TIMESTAMP(3),
    "proxima_accion_fecha" TIMESTAMP(3),
    "proxima_accion" TEXT,
    "observacion" TEXT,
    "created_by_user_id" UUID NOT NULL,
    "fecha_creacion" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fecha_actualizacion" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "crm_commercial_customers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crm_commercial_status_history" (
    "id" UUID NOT NULL,
    "cliente_id" UUID NOT NULL,
    "estado_anterior" "crm_commercial_customer_status",
    "estado_nuevo" "crm_commercial_customer_status" NOT NULL,
    "usuario_que_cambio" UUID NOT NULL,
    "nota" TEXT,
    "fecha" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "crm_commercial_status_history_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crm_commercial_notes" (
    "id" UUID NOT NULL,
    "cliente_id" UUID NOT NULL,
    "usuario_id" UUID NOT NULL,
    "nota" TEXT NOT NULL,
    "fecha_creacion" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fecha_actualizacion" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "crm_commercial_notes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crm_commercial_activities" (
    "id" UUID NOT NULL,
    "cliente_id" UUID NOT NULL,
    "creado_por_usuario_id" UUID NOT NULL,
    "asignado_usuario_id" UUID,
    "tipo" TEXT NOT NULL,
    "descripcion" TEXT NOT NULL,
    "fecha_programada" TIMESTAMP(3),
    "fecha_completada" TIMESTAMP(3),
    "fecha_creacion" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fecha_actualizacion" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "crm_commercial_activities_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crm_commercial_followup_tasks" (
    "id" UUID NOT NULL,
    "cliente_id" UUID NOT NULL,
    "titulo" TEXT NOT NULL,
    "descripcion" TEXT,
    "fecha_vencimiento" TIMESTAMP(3),
    "estado" "crm_commercial_followup_task_status" NOT NULL DEFAULT 'PENDIENTE',
    "prioridad" "crm_commercial_followup_task_priority" NOT NULL DEFAULT 'NORMAL',
    "asignado_usuario_id" UUID,
    "creado_por_usuario_id" UUID NOT NULL,
    "completado_en" TIMESTAMP(3),
    "completado_por_usuario_id" UUID,
    "fecha_creacion" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fecha_actualizacion" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "crm_commercial_followup_tasks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crm_commercial_settings" (
    "id" TEXT NOT NULL DEFAULT 'global',
    "selected_whatsapp_instance_id" TEXT,
    "selected_whatsapp_instance_name" TEXT,
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "bot_enabled" BOOLEAN NOT NULL DEFAULT false,
    "bot_system_prompt" TEXT,
    "business_context" TEXT,
    "auto_reply_delay_seconds" INTEGER NOT NULL DEFAULT 2,
    "human_takeover_minutes" INTEGER NOT NULL DEFAULT 30,
    "bot_default_status" TEXT NOT NULL DEFAULT 'ACTIVE',
    "bot_excluded_numbers" JSONB NOT NULL DEFAULT '[]',
    "bot_allowed_channels" JSONB NOT NULL DEFAULT '["WHATSAPP"]',
    "updated_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "crm_commercial_settings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crm_commercial_library_items" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "type" "crm_commercial_library_item_type" NOT NULL,
    "content_text" TEXT,
    "media_url" TEXT,
    "file_name" TEXT,
    "mime_type" TEXT,
    "latitude" DECIMAL(10,7),
    "longitude" DECIMAL(10,7),
    "external_url" TEXT,
    "category" TEXT,
    "tags" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "sort_order" INTEGER NOT NULL DEFAULT 0,
    "created_by_user_id" UUID NOT NULL,
    "updated_by_user_id" UUID NOT NULL,
    "use_count" INTEGER NOT NULL DEFAULT 0,
    "last_used_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "crm_commercial_library_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Sale" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "customerId" UUID,
    "cashSessionId" UUID,
    "client_request_id" TEXT,
    "saleDate" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "note" TEXT,
    "paymentMethod" TEXT NOT NULL DEFAULT 'cash',
    "paymentCashAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "paymentTransferAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "creditAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "creditPaidAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "creditBalance" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "creditStatus" TEXT NOT NULL DEFAULT 'none',
    "kind" TEXT NOT NULL DEFAULT 'invoice',
    "status" TEXT NOT NULL DEFAULT 'PAID',
    "totalSold" DECIMAL(12,2) NOT NULL,
    "fiscal_tax_enabled" BOOLEAN NOT NULL DEFAULT false,
    "fiscal_price_mode" "tax_price_mode" NOT NULL DEFAULT 'NO_TAX',
    "taxable_base" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "tax_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "exempt_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "discount_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "fiscal_voucher_type" TEXT,
    "ncf" TEXT,
    "fiscal_customer_tax_id" TEXT,
    "fiscal_customer_name" TEXT,
    "totalCost" DECIMAL(12,2) NOT NULL,
    "totalProfit" DECIMAL(12,2) NOT NULL,
    "commissionRate" DECIMAL(5,4) NOT NULL DEFAULT 0.10,
    "commissionAmount" DECIMAL(12,2) NOT NULL,
    "isDeleted" BOOLEAN NOT NULL DEFAULT false,
    "deletedAt" TIMESTAMP(3),
    "deletedById" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Sale_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sale_credit_payments" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "saleId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "cashSessionId" UUID,
    "amount" DECIMAL(12,2) NOT NULL,
    "cashAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "transferAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "note" TEXT,
    "paidAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sale_credit_payments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cashbox_daily" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "businessDate" TEXT NOT NULL,
    "openedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "openedByUserId" UUID NOT NULL,
    "initialAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "currentAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "status" TEXT NOT NULL DEFAULT 'OPEN',
    "closedAt" TIMESTAMP(3),
    "closedByUserId" UUID,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "cashbox_daily_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cash_sessions" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "openedByUserId" UUID NOT NULL,
    "userName" TEXT,
    "openedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "initialAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "closingAmount" DECIMAL(12,2),
    "expectedAmount" DECIMAL(12,2),
    "difference" DECIMAL(12,2),
    "status" TEXT NOT NULL DEFAULT 'OPEN',
    "closedAt" TIMESTAMP(3),
    "closedByUserId" UUID,
    "cashboxDailyId" UUID,
    "businessDate" TEXT,
    "requiresClosure" BOOLEAN NOT NULL DEFAULT false,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "cash_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cash_movements" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "sessionId" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "reason" TEXT,
    "movementType" TEXT NOT NULL DEFAULT 'expense',
    "affectsProfit" BOOLEAN NOT NULL DEFAULT true,
    "userId" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "cash_movements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SaleItem" (
    "id" UUID NOT NULL,
    "saleId" UUID NOT NULL,
    "productId" UUID,
    "productNameSnapshot" TEXT NOT NULL,
    "productImageSnapshot" TEXT,
    "qty" DECIMAL(12,3) NOT NULL,
    "priceSoldUnit" DECIMAL(12,2) NOT NULL,
    "gross_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "line_discount_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "taxable_base" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "tax_rate" DECIMAL(5,4) NOT NULL DEFAULT 0,
    "tax_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "exempt_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "tax_included" BOOLEAN NOT NULL DEFAULT false,
    "tax_exempt" BOOLEAN NOT NULL DEFAULT false,
    "costUnitSnapshot" DECIMAL(12,2) NOT NULL,
    "subtotalSold" DECIMAL(12,2) NOT NULL,
    "subtotalCost" DECIMAL(12,2) NOT NULL,
    "profit" DECIMAL(12,2) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SaleItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ncf_sequences" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "voucher_type" TEXT NOT NULL,
    "prefix" TEXT NOT NULL,
    "start_number" INTEGER NOT NULL DEFAULT 1,
    "next_number" INTEGER NOT NULL DEFAULT 1,
    "end_number" INTEGER NOT NULL,
    "valid_until" TIMESTAMP(3),
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ncf_sequences_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ncf_audit_logs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "sequence_id" UUID,
    "sale_id" UUID,
    "user_id" UUID,
    "ncf" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ncf_audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Close" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "type" "CloseType" NOT NULL,
    "date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "cash" DECIMAL(12,2) NOT NULL,
    "transfer" DECIMAL(12,2) NOT NULL,
    "transferBank" TEXT,
    "card" DECIMAL(12,2) NOT NULL,
    "otherIncome" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "expenses" DECIMAL(12,2) NOT NULL,
    "cashDelivered" DECIMAL(12,2) NOT NULL,
    "totalIncome" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "netTotal" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "difference" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "cashDeposited" BOOLEAN NOT NULL DEFAULT false,
    "cashDepositedAt" TIMESTAMP(3),
    "cashDepositedById" UUID,
    "cashDepositedByName" TEXT,
    "notes" TEXT,
    "evidenceUrl" TEXT,
    "evidenceFileName" TEXT,
    "evidenceStorageKey" TEXT,
    "evidenceMimeType" TEXT,
    "expenseDetails" JSONB,
    "pdfUrl" TEXT,
    "pdfStorageKey" TEXT,
    "pdfFileName" TEXT,
    "notificationStatus" TEXT,
    "notificationError" TEXT,
    "createdById" UUID,
    "createdByName" TEXT,
    "reviewedById" UUID,
    "reviewedByName" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "reviewNote" TEXT,
    "aiRiskLevel" TEXT,
    "aiReportSummary" TEXT,
    "aiReportJson" JSONB,
    "aiGeneratedAt" TIMESTAMP(3),
    "correctionOfCloseId" UUID,
    "correctionReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Close_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CloseTransfer" (
    "id" UUID NOT NULL,
    "closeId" UUID NOT NULL,
    "bankName" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "referenceNumber" TEXT,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CloseTransfer_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CloseTransferVoucher" (
    "id" UUID NOT NULL,
    "transferId" UUID NOT NULL,
    "storageKey" TEXT NOT NULL,
    "fileUrl" TEXT NOT NULL,
    "fileName" TEXT NOT NULL,
    "mimeType" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CloseTransferVoucher_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DepositOrder" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "windowFrom" TIMESTAMP(3) NOT NULL,
    "windowTo" TIMESTAMP(3) NOT NULL,
    "bankName" TEXT NOT NULL,
    "bankAccount" TEXT,
    "collaboratorName" TEXT,
    "note" TEXT,
    "reserveAmount" DECIMAL(12,2) NOT NULL,
    "totalAvailableCash" DECIMAL(12,2) NOT NULL,
    "depositTotal" DECIMAL(12,2) NOT NULL,
    "closesCountByType" JSONB NOT NULL,
    "depositByType" JSONB NOT NULL,
    "accountByType" JSONB NOT NULL,
    "status" "DepositOrderStatus" NOT NULL DEFAULT 'PENDING',
    "voucherUrl" TEXT,
    "voucherFileName" TEXT,
    "voucherMimeType" TEXT,
    "createdById" UUID,
    "createdByName" TEXT,
    "executedById" UUID,
    "executedByName" TEXT,
    "executedAt" TIMESTAMP(3),
    "correctionOfDepositOrderId" UUID,
    "correctionReason" TEXT,
    "deletedAt" TIMESTAMP(3),
    "deletedById" UUID,
    "deletedByName" TEXT,
    "deletedReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DepositOrder_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "deposit_banks" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "deposit_banks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "deposit_bank_accounts" (
    "id" UUID NOT NULL,
    "bank_id" UUID NOT NULL,
    "label" TEXT NOT NULL,
    "account_number" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "deposit_bank_accounts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FiscalInvoice" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "kind" "FiscalInvoiceKind" NOT NULL,
    "invoiceDate" TIMESTAMP(3) NOT NULL,
    "imageUrl" TEXT NOT NULL,
    "note" TEXT,
    "createdById" UUID,
    "createdByName" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FiscalInvoice_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PayableService" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "providerKind" "PayableProviderKind" NOT NULL,
    "providerName" TEXT NOT NULL,
    "description" TEXT,
    "frequency" "PayableFrequency" NOT NULL,
    "defaultAmount" DECIMAL(12,2),
    "nextDueDate" TIMESTAMP(3) NOT NULL,
    "lastPaidAt" TIMESTAMP(3),
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdById" UUID,
    "createdByName" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PayableService_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PayablePayment" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "serviceId" UUID NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "paidAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "note" TEXT,
    "createdById" UUID,
    "createdByName" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PayablePayment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PayrollEmployee" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "user_id" UUID,
    "nombre" TEXT NOT NULL,
    "telefono" TEXT,
    "puesto" TEXT,
    "salarioBaseQuincenal" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "cuotaMinima" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "seguroLeyMonto" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "seguro_ley_monto_locked" BOOLEAN NOT NULL DEFAULT false,
    "activo" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PayrollEmployee_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PayrollPeriod" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "startDate" TIMESTAMP(3) NOT NULL,
    "endDate" TIMESTAMP(3) NOT NULL,
    "status" "PayrollPeriodStatus" NOT NULL DEFAULT 'OPEN',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PayrollPeriod_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PayrollEmployeeConfig" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "periodId" UUID NOT NULL,
    "employeeId" UUID NOT NULL,
    "baseSalary" DECIMAL(12,2) NOT NULL,
    "includeCommissions" BOOLEAN NOT NULL DEFAULT false,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PayrollEmployeeConfig_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PayrollEntry" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "periodId" UUID NOT NULL,
    "employeeId" UUID NOT NULL,
    "pago_combustible_tecnico_id" UUID,
    "date" TIMESTAMP(3) NOT NULL,
    "type" "PayrollEntryType" NOT NULL,
    "concept" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "cantidad" DECIMAL(12,2),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PayrollEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PayrollEmployeePeriodStatus" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "periodId" UUID NOT NULL,
    "employeeId" UUID NOT NULL,
    "status" "PayrollPaymentStatus" NOT NULL DEFAULT 'DRAFT',
    "paidAt" TIMESTAMP(3),
    "paidById" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PayrollEmployeePeriodStatus_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payroll_service_commission_requests" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "service_order_id" UUID NOT NULL,
    "quotation_id" UUID,
    "employee_id" UUID NOT NULL,
    "technician_user_id" UUID NOT NULL,
    "created_by_user_id" UUID,
    "reviewed_by_user_id" UUID,
    "period_id" UUID,
    "payroll_entry_id" UUID,
    "service_type" "service_order_type" NOT NULL,
    "finalized_at" TIMESTAMP(3) NOT NULL,
    "profit_after_expense" DECIMAL(12,2) NOT NULL,
    "commission_rate" DECIMAL(5,4) NOT NULL DEFAULT 0.1000,
    "commission_amount" DECIMAL(12,2) NOT NULL,
    "concept" TEXT NOT NULL,
    "status" "PayrollServiceCommissionStatus" NOT NULL DEFAULT 'PENDING',
    "review_note" TEXT,
    "approved_at" TIMESTAMP(3),
    "rejected_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "payroll_service_commission_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CompanyManualEntry" (
    "id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "starterKey" TEXT,
    "title" TEXT NOT NULL,
    "normalizedTitle" TEXT NOT NULL DEFAULT '',
    "summary" TEXT,
    "content" TEXT NOT NULL,
    "contentHash" TEXT NOT NULL DEFAULT '',
    "kind" "CompanyManualEntryKind" NOT NULL,
    "audience" "CompanyManualAudience" NOT NULL DEFAULT 'GENERAL',
    "targetRoles" "Role"[] DEFAULT ARRAY[]::"Role"[],
    "moduleKey" TEXT,
    "moduleScopeKey" TEXT NOT NULL DEFAULT '',
    "targetRolesKey" TEXT NOT NULL DEFAULT '',
    "published" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdByUserId" UUID NOT NULL,
    "updatedByUserId" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CompanyManualEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Service" (
    "id" UUID NOT NULL,
    "orderNumber" TEXT,
    "customerId" UUID NOT NULL,
    "createdByUserId" UUID NOT NULL,
    "serviceType" "ServiceType" NOT NULL,
    "category" TEXT NOT NULL,
    "category_id" UUID,
    "status" "ServiceStatus" NOT NULL DEFAULT 'RESERVED',
    "currentPhase" "ServicePhaseType" NOT NULL DEFAULT 'RESERVA',
    "orderType" "OrderType" NOT NULL DEFAULT 'RESERVA',
    "orderState" "OrderState" NOT NULL DEFAULT 'PENDING',
    "adminPhase" "AdminOrderPhase",
    "adminStatus" "AdminOrderStatus",
    "technicianId" UUID,
    "priority" INTEGER NOT NULL DEFAULT 2,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "quotedAmount" DECIMAL(12,2),
    "depositAmount" DECIMAL(12,2),
    "paymentStatus" TEXT NOT NULL DEFAULT 'pending',
    "addressSnapshot" TEXT,
    "orderExtras" JSONB,
    "scheduledStart" TIMESTAMP(3),
    "scheduledEnd" TIMESTAMP(3),
    "completedAt" TIMESTAMP(3),
    "warrantyParentServiceId" UUID,
    "tags" TEXT[],
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "isDeleted" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "Service_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ServiceClosing" (
    "id" UUID NOT NULL,
    "serviceId" UUID NOT NULL,
    "invoiceData" JSONB,
    "warrantyData" JSONB,
    "invoiceDraftFileId" UUID,
    "warrantyDraftFileId" UUID,
    "invoiceApprovedFileId" UUID,
    "warrantyApprovedFileId" UUID,
    "invoiceFinalFileId" UUID,
    "warrantyFinalFileId" UUID,
    "approvalStatus" "ServiceClosingApprovalStatus" NOT NULL DEFAULT 'PENDING',
    "approvedByUserId" UUID,
    "approvedAt" TIMESTAMP(3),
    "rejectedByUserId" UUID,
    "rejectedAt" TIMESTAMP(3),
    "rejectReason" TEXT,
    "signatureStatus" "ServiceClosingSignatureStatus" NOT NULL DEFAULT 'PENDING',
    "signatureFileId" UUID,
    "signedAt" TIMESTAMP(3),
    "sentToTechnicianAt" TIMESTAMP(3),
    "sentToClientAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ServiceClosing_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "warranty_product_configs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "category_id" UUID,
    "category_code" TEXT,
    "category_name" TEXT,
    "product_name" TEXT,
    "product_key" TEXT,
    "has_warranty" BOOLEAN NOT NULL DEFAULT true,
    "duration_value" INTEGER,
    "duration_unit" "WarrantyDurationUnit",
    "warranty_summary" TEXT,
    "coverage_summary" TEXT,
    "exclusions_summary" TEXT,
    "notes" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "warranty_product_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "technical_visits" (
    "id" UUID NOT NULL,
    "order_id" UUID NOT NULL,
    "technician_id" UUID NOT NULL,
    "report_description" TEXT NOT NULL,
    "installation_notes" TEXT NOT NULL,
    "estimated_products" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "photos" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "videos" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "visit_date" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "technical_visits_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "vehiculos" (
    "id" UUID NOT NULL,
    "nombre" TEXT NOT NULL,
    "tipo" TEXT NOT NULL,
    "marca" TEXT,
    "modelo" TEXT,
    "placa" TEXT,
    "combustible_tipo" TEXT NOT NULL,
    "rendimiento_km_litro" DECIMAL(10,2),
    "capacidad_tanque_litros" DECIMAL(10,2),
    "es_empresa" BOOLEAN NOT NULL DEFAULT false,
    "tecnico_id_propietario" UUID,
    "activo" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "vehiculos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "precios_combustible" (
    "id" UUID NOT NULL,
    "combustible_tipo" TEXT NOT NULL,
    "precio_por_litro" DECIMAL(12,2) NOT NULL,
    "vigencia_desde" TIMESTAMP(3),
    "activo" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "precios_combustible_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pagos_combustible_tecnicos" (
    "id" UUID NOT NULL,
    "tecnico_id" UUID NOT NULL,
    "fecha_inicio" TIMESTAMP(3) NOT NULL,
    "fecha_fin" TIMESTAMP(3) NOT NULL,
    "total_monto" DECIMAL(12,2) NOT NULL,
    "estado" "PagoCombustibleTecnicoEstado" NOT NULL DEFAULT 'PENDIENTE',
    "fecha_pago" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "pagos_combustible_tecnicos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "salidas_tecnicas" (
    "id" UUID NOT NULL,
    "servicio_id" UUID NOT NULL,
    "tecnico_id" UUID NOT NULL,
    "vehiculo_id" UUID NOT NULL,
    "pago_combustible_id" UUID,
    "es_vehiculo_propio" BOOLEAN NOT NULL DEFAULT false,
    "genera_pago_combustible" BOOLEAN NOT NULL DEFAULT false,
    "fecha" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "hora_salida" TIMESTAMP(3) NOT NULL,
    "hora_llegada" TIMESTAMP(3),
    "hora_final" TIMESTAMP(3),
    "lat_salida" DOUBLE PRECISION NOT NULL,
    "lng_salida" DOUBLE PRECISION NOT NULL,
    "lat_llegada" DOUBLE PRECISION,
    "lng_llegada" DOUBLE PRECISION,
    "lat_final" DOUBLE PRECISION,
    "lng_final" DOUBLE PRECISION,
    "km_estimados" DECIMAL(12,2),
    "litros_estimados" DECIMAL(12,2),
    "precio_combustible_litro" DECIMAL(12,2),
    "monto_combustible" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "estado" "SalidaTecnicaEstado" NOT NULL DEFAULT 'INICIADA',
    "observacion" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "salidas_tecnicas_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ServicePhaseHistory" (
    "id" UUID NOT NULL,
    "serviceId" UUID NOT NULL,
    "phase" "ServicePhaseType" NOT NULL,
    "note" TEXT,
    "changedByUserId" UUID NOT NULL,
    "changedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fromPhase" "ServicePhaseType",
    "toPhase" "ServicePhaseType",

    CONSTRAINT "ServicePhaseHistory_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ServiceAssignment" (
    "id" UUID NOT NULL,
    "serviceId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "role" "ServiceAssignmentRole" NOT NULL DEFAULT 'ASSISTANT',
    "assignedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ServiceAssignment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ServiceStep" (
    "id" UUID NOT NULL,
    "serviceId" UUID NOT NULL,
    "stepKey" TEXT NOT NULL,
    "stepLabel" TEXT NOT NULL,
    "isDone" BOOLEAN NOT NULL DEFAULT false,
    "doneAt" TIMESTAMP(3),
    "doneByUserId" UUID,

    CONSTRAINT "ServiceStep_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ServiceUpdate" (
    "id" UUID NOT NULL,
    "serviceId" UUID NOT NULL,
    "changedByUserId" UUID NOT NULL,
    "type" "ServiceUpdateType" NOT NULL,
    "oldValue" JSONB,
    "newValue" JSONB,
    "message" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ServiceUpdate_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ServiceFile" (
    "id" UUID NOT NULL,
    "serviceId" UUID NOT NULL,
    "uploadedByUserId" UUID NOT NULL,
    "fileUrl" TEXT NOT NULL,
    "fileType" TEXT NOT NULL,
    "caption" TEXT,
    "storageProvider" TEXT NOT NULL DEFAULT 'LOCAL',
    "objectKey" TEXT,
    "originalFileName" TEXT,
    "mimeType" TEXT,
    "mediaType" TEXT,
    "kind" TEXT,
    "fileSize" INTEGER,
    "width" INTEGER,
    "height" INTEGER,
    "durationSeconds" INTEGER,
    "executionReportId" UUID,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ServiceFile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_orders" (
    "id" UUID NOT NULL,
    "client_id" UUID NOT NULL,
    "quotation_id" UUID,
    "category" "service_order_category" NOT NULL,
    "service_type" "service_order_type" NOT NULL,
    "status" "service_order_status" NOT NULL DEFAULT 'pendiente',
    "scheduled_for" TIMESTAMP(3),
    "finalized_at" TIMESTAMP(3),
    "technician_confirmed_at" TIMESTAMP(3),
    "technician_confirmed_by" UUID,
    "technical_note" TEXT,
    "extra_requirements" TEXT,
    "parent_order_id" UUID,
    "created_by" UUID NOT NULL,
    "assigned_to" UUID,
    "last_status_changed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_status_changed_by_user_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "service_orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_order_status_history" (
    "id" UUID NOT NULL,
    "service_order_id" UUID NOT NULL,
    "previous_status" "service_order_status",
    "next_status" "service_order_status" NOT NULL,
    "changed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "changed_by_user_id" UUID,
    "changed_by_user_name" TEXT,
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "service_order_status_history_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_evidences" (
    "id" UUID NOT NULL,
    "service_order_id" UUID NOT NULL,
    "type" "service_evidence_type" NOT NULL,
    "content" TEXT NOT NULL,
    "created_by" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "for_publicidad" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "service_evidences_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_reports" (
    "id" UUID NOT NULL,
    "service_order_id" UUID NOT NULL,
    "type" "service_report_type" NOT NULL DEFAULT 'otros',
    "report" TEXT NOT NULL,
    "created_by" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "service_reports_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "publicidad_images" (
    "id" UUID NOT NULL,
    "url" TEXT NOT NULL,
    "caption" TEXT,
    "uploaded_by_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "publicidad_images_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Cotizacion" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "createdByUserId" UUID NOT NULL,
    "customerId" UUID,
    "customerName" TEXT NOT NULL,
    "customerPhone" TEXT NOT NULL,
    "customerPhoneNormalized" TEXT NOT NULL DEFAULT '',
    "note" TEXT,
    "includeItbis" BOOLEAN NOT NULL DEFAULT false,
    "itbisRate" DECIMAL(5,4) NOT NULL DEFAULT 0.18,
    "globalDiscountAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "subtotal" DECIMAL(12,2) NOT NULL,
    "subtotalCost" DECIMAL(12,2),
    "itbisAmount" DECIMAL(12,2) NOT NULL,
    "totalCost" DECIMAL(12,2),
    "total" DECIMAL(12,2) NOT NULL,
    "totalProfit" DECIMAL(12,2),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Cotizacion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CotizacionItem" (
    "id" UUID NOT NULL,
    "cotizacionId" UUID NOT NULL,
    "productId" UUID,
    "productNameSnapshot" TEXT NOT NULL,
    "productImageSnapshot" TEXT,
    "qty" DECIMAL(12,3) NOT NULL,
    "originalUnitPriceSnapshot" DECIMAL(12,2),
    "unitPrice" DECIMAL(12,2) NOT NULL,
    "costUnitSnapshot" DECIMAL(12,2),
    "subtotalCost" DECIMAL(12,2),
    "lineTotal" DECIMAL(12,2) NOT NULL,
    "profit" DECIMAL(12,2),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CotizacionItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "work_schedule_profiles" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "is_default" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "work_schedule_profiles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "work_schedule_profile_days" (
    "id" UUID NOT NULL,
    "profile_id" UUID NOT NULL,
    "weekday" INTEGER NOT NULL,
    "is_working" BOOLEAN NOT NULL DEFAULT true,
    "kind" "WorkShiftKind" NOT NULL DEFAULT 'NORMAL',
    "start_minute" INTEGER NOT NULL,
    "end_minute" INTEGER NOT NULL,

    CONSTRAINT "work_schedule_profile_days_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "work_coverage_rules" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "role" "Role" NOT NULL,
    "weekday" INTEGER NOT NULL,
    "min_required" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "work_coverage_rules_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "work_employee_configs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "schedule_profile_id" UUID,
    "preferred_day_off_weekday" INTEGER,
    "fixed_day_off_weekday" INTEGER,
    "disallowed_day_off_weekdays" INTEGER[] DEFAULT ARRAY[]::INTEGER[],
    "unavailable_weekdays" INTEGER[] DEFAULT ARRAY[]::INTEGER[],
    "notes" TEXT,
    "last_assigned_day_off_weekday" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "work_employee_configs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "work_schedule_exceptions" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "user_id" UUID,
    "type" "WorkScheduleExceptionType" NOT NULL,
    "date_from" TIMESTAMP(3) NOT NULL,
    "date_to" TIMESTAMP(3) NOT NULL,
    "note" TEXT,
    "created_by_id" UUID,
    "created_by_name" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "work_schedule_exceptions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "work_week_schedules" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "week_start_date" TIMESTAMP(3) NOT NULL,
    "status" "WorkWeekScheduleStatus" NOT NULL DEFAULT 'GENERATED',
    "generated_by_id" UUID,
    "generated_by_name" TEXT,
    "generated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "warnings" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "work_week_schedules_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "work_day_assignments" (
    "id" UUID NOT NULL,
    "week_schedule_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "date" TIMESTAMP(3) NOT NULL,
    "weekday" INTEGER NOT NULL,
    "status" "WorkAssignmentStatus" NOT NULL,
    "start_minute" INTEGER,
    "end_minute" INTEGER,
    "manual_override" BOOLEAN NOT NULL DEFAULT false,
    "note" TEXT,
    "conflict_flags" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "work_day_assignments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "work_schedule_audit_logs" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "action" "WorkScheduleAuditAction" NOT NULL,
    "actor_user_id" UUID,
    "actor_user_name" TEXT,
    "target_user_id" UUID,
    "week_start_date" TIMESTAMP(3),
    "date_affected" TIMESTAMP(3),
    "reason" TEXT,
    "before" JSONB,
    "after" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "work_schedule_audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ai_assistant_conversation_turns" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "module" TEXT NOT NULL DEFAULT 'general',
    "route" TEXT,
    "entity_type" TEXT,
    "entity_id" TEXT,
    "user_message" TEXT NOT NULL,
    "assistant_response" TEXT NOT NULL,
    "response_source" TEXT NOT NULL DEFAULT 'rules-only',
    "denied" BOOLEAN NOT NULL DEFAULT false,
    "citations" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ai_assistant_conversation_turns_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ai_assistant_memories" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "scope" TEXT NOT NULL DEFAULT 'user',
    "module" TEXT NOT NULL DEFAULT 'general',
    "topic_key" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "summary" TEXT NOT NULL,
    "keywords" JSONB,
    "source_count" INTEGER NOT NULL DEFAULT 1,
    "last_source_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ai_assistant_memories_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "companies_slug_key" ON "companies"("slug");

-- CreateIndex
CREATE UNIQUE INDEX "companies_license_key_key" ON "companies"("license_key");

-- CreateIndex
CREATE INDEX "companies_status_idx" ON "companies"("status");

-- CreateIndex
CREATE INDEX "companies_license_status_idx" ON "companies"("license_status");

-- CreateIndex
CREATE INDEX "companies_license_expires_at_idx" ON "companies"("license_expires_at");

-- CreateIndex
CREATE INDEX "open_sales_ticket_states_updated_at_idx" ON "open_sales_ticket_states"("updated_at");

-- CreateIndex
CREATE INDEX "company_license_audit_logs_company_id_created_at_idx" ON "company_license_audit_logs"("company_id", "created_at");

-- CreateIndex
CREATE INDEX "company_license_audit_logs_action_idx" ON "company_license_audit_logs"("action");

-- CreateIndex
CREATE INDEX "company_members_company_id_status_idx" ON "company_members"("company_id", "status");

-- CreateIndex
CREATE INDEX "company_members_user_id_status_idx" ON "company_members"("user_id", "status");

-- CreateIndex
CREATE INDEX "company_members_company_id_role_idx" ON "company_members"("company_id", "role");

-- CreateIndex
CREATE UNIQUE INDEX "company_members_user_id_company_id_key" ON "company_members"("user_id", "company_id");

-- CreateIndex
CREATE INDEX "auth_sessions_user_id_revoked_at_idx" ON "auth_sessions"("user_id", "revoked_at");

-- CreateIndex
CREATE INDEX "auth_sessions_company_id_revoked_at_idx" ON "auth_sessions"("company_id", "revoked_at");

-- CreateIndex
CREATE INDEX "auth_sessions_token_family_idx" ON "auth_sessions"("token_family");

-- CreateIndex
CREATE INDEX "auth_sessions_expires_at_idx" ON "auth_sessions"("expires_at");

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE UNIQUE INDEX "users_cedula_key" ON "users"("cedula");

-- CreateIndex
CREATE INDEX "users_company_id_idx" ON "users"("company_id");

-- CreateIndex
CREATE INDEX "users_company_id_role_idx" ON "users"("company_id", "role");

-- CreateIndex
CREATE INDEX "employee_warnings_company_id_employee_user_id_idx" ON "employee_warnings"("company_id", "employee_user_id");

-- CreateIndex
CREATE INDEX "employee_warnings_company_id_status_idx" ON "employee_warnings"("company_id", "status");

-- CreateIndex
CREATE INDEX "employee_warnings_company_id_warning_type_idx" ON "employee_warnings"("company_id", "warning_type");

-- CreateIndex
CREATE INDEX "employee_warnings_issued_by_user_id_idx" ON "employee_warnings"("issued_by_user_id");

-- CreateIndex
CREATE INDEX "employee_warnings_company_id_created_at_idx" ON "employee_warnings"("company_id", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "employee_warnings_company_id_warning_number_key" ON "employee_warnings"("company_id", "warning_number");

-- CreateIndex
CREATE INDEX "employee_warning_evidences_warning_id_created_at_idx" ON "employee_warning_evidences"("warning_id", "created_at");

-- CreateIndex
CREATE INDEX "employee_warning_signatures_warning_id_signed_at_idx" ON "employee_warning_signatures"("warning_id", "signed_at");

-- CreateIndex
CREATE INDEX "employee_warning_audit_logs_warning_id_created_at_idx" ON "employee_warning_audit_logs"("warning_id", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "marketing_flow_configs_company_id_key" ON "marketing_flow_configs"("company_id");

-- CreateIndex
CREATE INDEX "marketing_flow_configs_company_id_active_idx" ON "marketing_flow_configs"("company_id", "active");

-- CreateIndex
CREATE INDEX "marketing_daily_stories_company_id_date_status_idx" ON "marketing_daily_stories"("company_id", "date", "status");

-- CreateIndex
CREATE INDEX "marketing_daily_stories_company_id_status_updated_at_idx" ON "marketing_daily_stories"("company_id", "status", "updated_at");

-- CreateIndex
CREATE INDEX "marketing_daily_stories_company_id_image_status_date_idx" ON "marketing_daily_stories"("company_id", "image_status", "date");

-- CreateIndex
CREATE INDEX "marketing_daily_stories_company_id_media_asset_id_idx" ON "marketing_daily_stories"("company_id", "media_asset_id");

-- CreateIndex
CREATE UNIQUE INDEX "marketing_daily_stories_company_id_date_type_key" ON "marketing_daily_stories"("company_id", "date", "type");

-- CreateIndex
CREATE INDEX "marketing_media_assets_company_id_is_active_is_featured_idx" ON "marketing_media_assets"("company_id", "is_active", "is_featured");

-- CreateIndex
CREATE INDEX "marketing_media_assets_company_id_category_related_service_idx" ON "marketing_media_assets"("company_id", "category", "related_service");

-- CreateIndex
CREATE INDEX "marketing_media_assets_company_id_use_count_last_used_at_idx" ON "marketing_media_assets"("company_id", "use_count", "last_used_at");

-- CreateIndex
CREATE INDEX "marketing_ad_campaigns_company_id_date_idx" ON "marketing_ad_campaigns"("company_id", "date");

-- CreateIndex
CREATE INDEX "marketing_ad_campaigns_company_id_status_updated_at_idx" ON "marketing_ad_campaigns"("company_id", "status", "updated_at");

-- CreateIndex
CREATE INDEX "marketing_ad_campaigns_company_id_phase_updated_at_idx" ON "marketing_ad_campaigns"("company_id", "phase", "updated_at");

-- CreateIndex
CREATE INDEX "marketing_ad_campaigns_gallery_asset_id_idx" ON "marketing_ad_campaigns"("gallery_asset_id");

-- CreateIndex
CREATE INDEX "marketing_ad_campaigns_ai_research_id_idx" ON "marketing_ad_campaigns"("ai_research_id");

-- CreateIndex
CREATE INDEX "marketing_social_accounts_company_id_type_is_active_idx" ON "marketing_social_accounts"("company_id", "type", "is_active");

-- CreateIndex
CREATE INDEX "marketing_social_accounts_company_id_updated_at_idx" ON "marketing_social_accounts"("company_id", "updated_at");

-- CreateIndex
CREATE INDEX "marketing_social_accounts_company_id_deleted_at_idx" ON "marketing_social_accounts"("company_id", "deleted_at");

-- CreateIndex
CREATE INDEX "marketing_activity_logs_company_id_created_at_idx" ON "marketing_activity_logs"("company_id", "created_at");

-- CreateIndex
CREATE INDEX "marketing_activity_logs_company_id_action_idx" ON "marketing_activity_logs"("company_id", "action");

-- CreateIndex
CREATE UNIQUE INDEX "marketing_research_configs_company_id_key" ON "marketing_research_configs"("company_id");

-- CreateIndex
CREATE INDEX "marketing_researches_company_id_date_status_idx" ON "marketing_researches"("company_id", "date", "status");

-- CreateIndex
CREATE INDEX "marketing_researches_company_id_status_created_at_idx" ON "marketing_researches"("company_id", "status", "created_at");

-- CreateIndex
CREATE INDEX "marketing_learning_memories_company_id_category_status_idx" ON "marketing_learning_memories"("company_id", "category", "status");

-- CreateIndex
CREATE INDEX "marketing_learning_memories_company_id_score_idx" ON "marketing_learning_memories"("company_id", "score" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "user_whatsapp_instances_user_id_key" ON "user_whatsapp_instances"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "user_whatsapp_instances_instance_name_key" ON "user_whatsapp_instances"("instance_name");

-- CreateIndex
CREATE INDEX "whatsapp_conversations_instance_id_last_message_at_idx" ON "whatsapp_conversations"("instance_id", "last_message_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_conversations_instance_id_remote_jid_key" ON "whatsapp_conversations"("instance_id", "remote_jid");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_conversations_instance_id_remote_phone_key" ON "whatsapp_conversations"("instance_id", "remote_phone");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_messages_evolution_id_key" ON "whatsapp_messages"("evolution_id");

-- CreateIndex
CREATE INDEX "whatsapp_messages_conversation_id_sent_at_idx" ON "whatsapp_messages"("conversation_id", "sent_at" DESC);

-- CreateIndex
CREATE INDEX "whatsapp_messages_media_storage_key_idx" ON "whatsapp_messages"("media_storage_key");

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_ai_media_summaries_message_id_key" ON "whatsapp_ai_media_summaries"("message_id");

-- CreateIndex
CREATE INDEX "whatsapp_ai_media_summaries_media_type_idx" ON "whatsapp_ai_media_summaries"("media_type");

-- CreateIndex
CREATE INDEX "whatsapp_ai_media_summaries_transcription_status_idx" ON "whatsapp_ai_media_summaries"("transcription_status");

-- CreateIndex
CREATE INDEX "whatsapp_ai_analysis_reports_conversation_id_generated_at_idx" ON "whatsapp_ai_analysis_reports"("conversation_id", "generated_at" DESC);

-- CreateIndex
CREATE INDEX "whatsapp_ai_analysis_reports_scope_date_range_key_generated_idx" ON "whatsapp_ai_analysis_reports"("scope", "date_range_key", "generated_at" DESC);

-- CreateIndex
CREATE INDEX "whatsapp_ai_analysis_reports_risk_level_idx" ON "whatsapp_ai_analysis_reports"("risk_level");

-- CreateIndex
CREATE UNIQUE INDEX "user_locations_userId_key" ON "user_locations"("userId");

-- CreateIndex
CREATE INDEX "user_locations_updatedAt_idx" ON "user_locations"("updatedAt");

-- CreateIndex
CREATE UNIQUE INDEX "app_config_company_id_key" ON "app_config"("company_id");

-- CreateIndex
CREATE INDEX "app_config_company_id_idx" ON "app_config"("company_id");

-- CreateIndex
CREATE INDEX "service_execution_reports_service_id_idx" ON "service_execution_reports"("service_id");

-- CreateIndex
CREATE INDEX "service_execution_reports_technician_id_idx" ON "service_execution_reports"("technician_id");

-- CreateIndex
CREATE INDEX "service_execution_reports_updated_at_idx" ON "service_execution_reports"("updated_at");

-- CreateIndex
CREATE UNIQUE INDEX "service_execution_reports_service_id_technician_id_key" ON "service_execution_reports"("service_id", "technician_id");

-- CreateIndex
CREATE INDEX "service_execution_changes_service_id_created_at_idx" ON "service_execution_changes"("service_id", "created_at");

-- CreateIndex
CREATE INDEX "service_execution_changes_execution_report_id_idx" ON "service_execution_changes"("execution_report_id");

-- CreateIndex
CREATE INDEX "service_execution_changes_created_by_user_id_idx" ON "service_execution_changes"("created_by_user_id");

-- CreateIndex
CREATE UNIQUE INDEX "service_categories_code_key" ON "service_categories"("code");

-- CreateIndex
CREATE INDEX "service_categories_name_idx" ON "service_categories"("name");

-- CreateIndex
CREATE UNIQUE INDEX "service_phases_code_key" ON "service_phases"("code");

-- CreateIndex
CREATE INDEX "service_phases_order_index_idx" ON "service_phases"("order_index");

-- CreateIndex
CREATE INDEX "service_phases_name_idx" ON "service_phases"("name");

-- CreateIndex
CREATE INDEX "checklist_templates_category_id_idx" ON "checklist_templates"("category_id");

-- CreateIndex
CREATE INDEX "checklist_templates_phase_id_idx" ON "checklist_templates"("phase_id");

-- CreateIndex
CREATE INDEX "checklist_templates_category_id_phase_id_idx" ON "checklist_templates"("category_id", "phase_id");

-- CreateIndex
CREATE UNIQUE INDEX "checklist_templates_category_id_phase_id_type_key" ON "checklist_templates"("category_id", "phase_id", "type");

-- CreateIndex
CREATE INDEX "checklist_items_template_id_idx" ON "checklist_items"("template_id");

-- CreateIndex
CREATE INDEX "checklist_items_template_id_order_index_idx" ON "checklist_items"("template_id", "order_index");

-- CreateIndex
CREATE INDEX "checklist_executions_service_order_id_idx" ON "checklist_executions"("service_order_id");

-- CreateIndex
CREATE INDEX "checklist_executions_template_id_idx" ON "checklist_executions"("template_id");

-- CreateIndex
CREATE INDEX "checklist_executions_checklist_item_id_idx" ON "checklist_executions"("checklist_item_id");

-- CreateIndex
CREATE INDEX "checklist_executions_checked_by_idx" ON "checklist_executions"("checked_by");

-- CreateIndex
CREATE UNIQUE INDEX "checklist_executions_service_order_id_checklist_item_id_key" ON "checklist_executions"("service_order_id", "checklist_item_id");

-- CreateIndex
CREATE UNIQUE INDEX "notification_outbox_dedupe_key_key" ON "notification_outbox"("dedupe_key");

-- CreateIndex
CREATE INDEX "notification_outbox_status_next_attempt_at_idx" ON "notification_outbox"("status", "next_attempt_at");

-- CreateIndex
CREATE INDEX "notification_outbox_locked_at_idx" ON "notification_outbox"("locked_at");

-- CreateIndex
CREATE UNIQUE INDEX "service_order_notification_jobs_dedupe_key_key" ON "service_order_notification_jobs"("dedupe_key");

-- CreateIndex
CREATE INDEX "service_order_notification_jobs_order_id_idx" ON "service_order_notification_jobs"("order_id");

-- CreateIndex
CREATE INDEX "service_order_notification_jobs_status_run_at_idx" ON "service_order_notification_jobs"("status", "run_at");

-- CreateIndex
CREATE INDEX "service_order_notification_jobs_locked_at_idx" ON "service_order_notification_jobs"("locked_at");

-- CreateIndex
CREATE INDEX "Punch_userId_idx" ON "Punch"("userId");

-- CreateIndex
CREATE INDEX "Punch_timestamp_idx" ON "Punch"("timestamp");

-- CreateIndex
CREATE INDEX "Product_company_id_idx" ON "Product"("company_id");

-- CreateIndex
CREATE INDEX "Product_company_id_nombre_idx" ON "Product"("company_id", "nombre");

-- CreateIndex
CREATE INDEX "Product_company_id_image_key_idx" ON "Product"("company_id", "image_key");

-- CreateIndex
CREATE INDEX "taxes_company_id_is_active_idx" ON "taxes"("company_id", "is_active");

-- CreateIndex
CREATE INDEX "taxes_company_id_is_default_idx" ON "taxes"("company_id", "is_default");

-- CreateIndex
CREATE UNIQUE INDEX "taxes_company_id_name_key" ON "taxes"("company_id", "name");

-- CreateIndex
CREATE INDEX "suppliers_company_id_idx" ON "suppliers"("company_id");

-- CreateIndex
CREATE INDEX "suppliers_company_id_commercial_name_idx" ON "suppliers"("company_id", "commercial_name");

-- CreateIndex
CREATE INDEX "suppliers_company_id_is_active_idx" ON "suppliers"("company_id", "is_active");

-- CreateIndex
CREATE INDEX "suppliers_business_id_idx" ON "suppliers"("business_id");

-- CreateIndex
CREATE INDEX "purchase_invoices_supplier_id_idx" ON "purchase_invoices"("supplier_id");

-- CreateIndex
CREATE INDEX "purchase_invoices_purchase_order_id_idx" ON "purchase_invoices"("purchase_order_id");

-- CreateIndex
CREATE INDEX "purchase_invoices_company_id_invoice_date_idx" ON "purchase_invoices"("company_id", "invoice_date");

-- CreateIndex
CREATE INDEX "purchase_invoices_deleted_at_idx" ON "purchase_invoices"("deleted_at");

-- CreateIndex
CREATE INDEX "purchase_orders_company_id_supplier_id_idx" ON "purchase_orders"("company_id", "supplier_id");

-- CreateIndex
CREATE INDEX "purchase_orders_company_id_status_idx" ON "purchase_orders"("company_id", "status");

-- CreateIndex
CREATE INDEX "purchase_orders_company_id_order_date_idx" ON "purchase_orders"("company_id", "order_date");

-- CreateIndex
CREATE INDEX "purchase_orders_created_by_idx" ON "purchase_orders"("created_by");

-- CreateIndex
CREATE INDEX "purchase_orders_deleted_at_idx" ON "purchase_orders"("deleted_at");

-- CreateIndex
CREATE UNIQUE INDEX "purchase_orders_company_id_order_number_key" ON "purchase_orders"("company_id", "order_number");

-- CreateIndex
CREATE INDEX "purchase_order_items_purchase_order_id_idx" ON "purchase_order_items"("purchase_order_id");

-- CreateIndex
CREATE INDEX "purchase_order_items_product_id_idx" ON "purchase_order_items"("product_id");

-- CreateIndex
CREATE INDEX "purchase_order_items_supplier_id_idx" ON "purchase_order_items"("supplier_id");

-- CreateIndex
CREATE INDEX "purchase_receipts_purchase_order_id_idx" ON "purchase_receipts"("purchase_order_id");

-- CreateIndex
CREATE INDEX "purchase_receipts_received_by_idx" ON "purchase_receipts"("received_by");

-- CreateIndex
CREATE INDEX "purchase_receipt_items_purchase_order_item_id_idx" ON "purchase_receipt_items"("purchase_order_item_id");

-- CreateIndex
CREATE UNIQUE INDEX "purchase_receipt_items_purchase_receipt_id_purchase_order_i_key" ON "purchase_receipt_items"("purchase_receipt_id", "purchase_order_item_id");

-- CreateIndex
CREATE UNIQUE INDEX "website_product_overrides_product_id_key" ON "website_product_overrides"("product_id");

-- CreateIndex
CREATE INDEX "website_product_overrides_visible_idx" ON "website_product_overrides"("visible");

-- CreateIndex
CREATE INDEX "website_product_overrides_featured_idx" ON "website_product_overrides"("featured");

-- CreateIndex
CREATE INDEX "website_product_overrides_sort_order_idx" ON "website_product_overrides"("sort_order");

-- CreateIndex
CREATE INDEX "Client_ownerId_idx" ON "Client"("ownerId");

-- CreateIndex
CREATE INDEX "Client_ownerId_nombre_idx" ON "Client"("ownerId", "nombre");

-- CreateIndex
CREATE INDEX "Client_ownerId_telefono_idx" ON "Client"("ownerId", "telefono");

-- CreateIndex
CREATE INDEX "Client_company_id_idx" ON "Client"("company_id");

-- CreateIndex
CREATE INDEX "Client_company_id_isDeleted_idx" ON "Client"("company_id", "isDeleted");

-- CreateIndex
CREATE INDEX "Client_company_id_phoneNormalized_idx" ON "Client"("company_id", "phoneNormalized");

-- CreateIndex
CREATE INDEX "Client_phoneNormalized_idx" ON "Client"("phoneNormalized");

-- CreateIndex
CREATE INDEX "Client_lastActivityAt_idx" ON "Client"("lastActivityAt");

-- CreateIndex
CREATE INDEX "Client_latitude_longitude_idx" ON "Client"("latitude", "longitude");

-- CreateIndex
CREATE INDEX "crm_commercial_customers_estado_actual_idx" ON "crm_commercial_customers"("estado_actual");

-- CreateIndex
CREATE INDEX "crm_commercial_customers_responsable_user_id_idx" ON "crm_commercial_customers"("responsable_user_id");

-- CreateIndex
CREATE INDEX "crm_commercial_customers_nombre_idx" ON "crm_commercial_customers"("nombre");

-- CreateIndex
CREATE INDEX "crm_commercial_customers_telefono_idx" ON "crm_commercial_customers"("telefono");

-- CreateIndex
CREATE INDEX "crm_commercial_customers_client_id_idx" ON "crm_commercial_customers"("client_id");

-- CreateIndex
CREATE INDEX "crm_commercial_status_history_cliente_id_fecha_idx" ON "crm_commercial_status_history"("cliente_id", "fecha");

-- CreateIndex
CREATE INDEX "crm_commercial_status_history_usuario_que_cambio_idx" ON "crm_commercial_status_history"("usuario_que_cambio");

-- CreateIndex
CREATE INDEX "crm_commercial_notes_cliente_id_fecha_creacion_idx" ON "crm_commercial_notes"("cliente_id", "fecha_creacion");

-- CreateIndex
CREATE INDEX "crm_commercial_notes_usuario_id_idx" ON "crm_commercial_notes"("usuario_id");

-- CreateIndex
CREATE INDEX "crm_commercial_activities_cliente_id_fecha_creacion_idx" ON "crm_commercial_activities"("cliente_id", "fecha_creacion");

-- CreateIndex
CREATE INDEX "crm_commercial_activities_asignado_usuario_id_idx" ON "crm_commercial_activities"("asignado_usuario_id");

-- CreateIndex
CREATE INDEX "crm_commercial_followup_tasks_cliente_id_estado_idx" ON "crm_commercial_followup_tasks"("cliente_id", "estado");

-- CreateIndex
CREATE INDEX "crm_commercial_followup_tasks_asignado_usuario_id_idx" ON "crm_commercial_followup_tasks"("asignado_usuario_id");

-- CreateIndex
CREATE INDEX "crm_commercial_followup_tasks_fecha_vencimiento_idx" ON "crm_commercial_followup_tasks"("fecha_vencimiento");

-- CreateIndex
CREATE INDEX "crm_commercial_followup_tasks_estado_fecha_vencimiento_idx" ON "crm_commercial_followup_tasks"("estado", "fecha_vencimiento");

-- CreateIndex
CREATE INDEX "crm_commercial_library_items_company_id_is_active_sort_orde_idx" ON "crm_commercial_library_items"("company_id", "is_active", "sort_order");

-- CreateIndex
CREATE INDEX "crm_commercial_library_items_company_id_type_is_active_idx" ON "crm_commercial_library_items"("company_id", "type", "is_active");

-- CreateIndex
CREATE INDEX "crm_commercial_library_items_company_id_category_is_active_idx" ON "crm_commercial_library_items"("company_id", "category", "is_active");

-- CreateIndex
CREATE INDEX "Sale_userId_idx" ON "Sale"("userId");

-- CreateIndex
CREATE INDEX "Sale_customerId_idx" ON "Sale"("customerId");

-- CreateIndex
CREATE INDEX "Sale_cashSessionId_idx" ON "Sale"("cashSessionId");

-- CreateIndex
CREATE INDEX "Sale_company_id_creditStatus_idx" ON "Sale"("company_id", "creditStatus");

-- CreateIndex
CREATE INDEX "Sale_company_id_saleDate_idx" ON "Sale"("company_id", "saleDate");

-- CreateIndex
CREATE INDEX "Sale_company_id_isDeleted_idx" ON "Sale"("company_id", "isDeleted");

-- CreateIndex
CREATE INDEX "Sale_company_id_fiscal_voucher_type_idx" ON "Sale"("company_id", "fiscal_voucher_type");

-- CreateIndex
CREATE UNIQUE INDEX "Sale_company_id_client_request_id_key" ON "Sale"("company_id", "client_request_id");

-- CreateIndex
CREATE UNIQUE INDEX "Sale_company_id_ncf_key" ON "Sale"("company_id", "ncf");

-- CreateIndex
CREATE INDEX "sale_credit_payments_saleId_idx" ON "sale_credit_payments"("saleId");

-- CreateIndex
CREATE INDEX "sale_credit_payments_userId_idx" ON "sale_credit_payments"("userId");

-- CreateIndex
CREATE INDEX "sale_credit_payments_cashSessionId_idx" ON "sale_credit_payments"("cashSessionId");

-- CreateIndex
CREATE INDEX "sale_credit_payments_company_id_paidAt_idx" ON "sale_credit_payments"("company_id", "paidAt");

-- CreateIndex
CREATE INDEX "cashbox_daily_company_id_status_idx" ON "cashbox_daily"("company_id", "status");

-- CreateIndex
CREATE UNIQUE INDEX "cashbox_daily_company_id_businessDate_key" ON "cashbox_daily"("company_id", "businessDate");

-- CreateIndex
CREATE INDEX "cash_sessions_openedByUserId_status_idx" ON "cash_sessions"("openedByUserId", "status");

-- CreateIndex
CREATE INDEX "cash_sessions_company_id_status_idx" ON "cash_sessions"("company_id", "status");

-- CreateIndex
CREATE INDEX "cash_sessions_cashboxDailyId_idx" ON "cash_sessions"("cashboxDailyId");

-- CreateIndex
CREATE INDEX "cash_sessions_company_id_businessDate_idx" ON "cash_sessions"("company_id", "businessDate");

-- CreateIndex
CREATE INDEX "cash_movements_sessionId_idx" ON "cash_movements"("sessionId");

-- CreateIndex
CREATE INDEX "cash_movements_company_id_createdAt_idx" ON "cash_movements"("company_id", "createdAt");

-- CreateIndex
CREATE INDEX "SaleItem_saleId_idx" ON "SaleItem"("saleId");

-- CreateIndex
CREATE INDEX "SaleItem_productId_idx" ON "SaleItem"("productId");

-- CreateIndex
CREATE INDEX "ncf_sequences_company_id_voucher_type_prefix_idx" ON "ncf_sequences"("company_id", "voucher_type", "prefix");

-- CreateIndex
CREATE INDEX "ncf_sequences_company_id_voucher_type_active_idx" ON "ncf_sequences"("company_id", "voucher_type", "active");

-- CreateIndex
CREATE INDEX "ncf_audit_logs_company_id_ncf_idx" ON "ncf_audit_logs"("company_id", "ncf");

-- CreateIndex
CREATE INDEX "ncf_audit_logs_company_id_type_created_at_idx" ON "ncf_audit_logs"("company_id", "type", "created_at");

-- CreateIndex
CREATE INDEX "ncf_audit_logs_sale_id_idx" ON "ncf_audit_logs"("sale_id");

-- CreateIndex
CREATE INDEX "Close_company_id_date_idx" ON "Close"("company_id", "date");

-- CreateIndex
CREATE INDEX "Close_company_id_type_idx" ON "Close"("company_id", "type");

-- CreateIndex
CREATE INDEX "Close_company_id_status_idx" ON "Close"("company_id", "status");

-- CreateIndex
CREATE INDEX "Close_createdById_idx" ON "Close"("createdById");

-- CreateIndex
CREATE INDEX "Close_reviewedById_idx" ON "Close"("reviewedById");

-- CreateIndex
CREATE INDEX "Close_cashDeposited_idx" ON "Close"("cashDeposited");

-- CreateIndex
CREATE INDEX "Close_correctionOfCloseId_idx" ON "Close"("correctionOfCloseId");

-- CreateIndex
CREATE INDEX "Close_company_id_date_type_idx" ON "Close"("company_id", "date", "type");

-- CreateIndex
CREATE INDEX "Close_company_id_createdById_date_idx" ON "Close"("company_id", "createdById", "date");

-- CreateIndex
CREATE INDEX "Close_company_id_date_createdById_type_idx" ON "Close"("company_id", "date", "createdById", "type");

-- CreateIndex
CREATE INDEX "CloseTransfer_closeId_idx" ON "CloseTransfer"("closeId");

-- CreateIndex
CREATE INDEX "CloseTransferVoucher_transferId_idx" ON "CloseTransferVoucher"("transferId");

-- CreateIndex
CREATE INDEX "DepositOrder_company_id_windowFrom_windowTo_idx" ON "DepositOrder"("company_id", "windowFrom", "windowTo");

-- CreateIndex
CREATE INDEX "DepositOrder_company_id_status_idx" ON "DepositOrder"("company_id", "status");

-- CreateIndex
CREATE INDEX "DepositOrder_createdById_idx" ON "DepositOrder"("createdById");

-- CreateIndex
CREATE INDEX "DepositOrder_correctionOfDepositOrderId_idx" ON "DepositOrder"("correctionOfDepositOrderId");

-- CreateIndex
CREATE INDEX "DepositOrder_deletedById_idx" ON "DepositOrder"("deletedById");

-- CreateIndex
CREATE INDEX "deposit_banks_company_id_active_idx" ON "deposit_banks"("company_id", "active");

-- CreateIndex
CREATE UNIQUE INDEX "deposit_banks_company_id_name_key" ON "deposit_banks"("company_id", "name");

-- CreateIndex
CREATE INDEX "deposit_bank_accounts_bank_id_active_idx" ON "deposit_bank_accounts"("bank_id", "active");

-- CreateIndex
CREATE UNIQUE INDEX "deposit_bank_accounts_bank_id_label_key" ON "deposit_bank_accounts"("bank_id", "label");

-- CreateIndex
CREATE INDEX "FiscalInvoice_company_id_kind_idx" ON "FiscalInvoice"("company_id", "kind");

-- CreateIndex
CREATE INDEX "FiscalInvoice_company_id_invoiceDate_idx" ON "FiscalInvoice"("company_id", "invoiceDate");

-- CreateIndex
CREATE INDEX "FiscalInvoice_createdById_idx" ON "FiscalInvoice"("createdById");

-- CreateIndex
CREATE INDEX "PayableService_company_id_active_nextDueDate_idx" ON "PayableService"("company_id", "active", "nextDueDate");

-- CreateIndex
CREATE INDEX "PayableService_company_id_providerKind_idx" ON "PayableService"("company_id", "providerKind");

-- CreateIndex
CREATE INDEX "PayableService_createdById_idx" ON "PayableService"("createdById");

-- CreateIndex
CREATE INDEX "PayablePayment_serviceId_paidAt_idx" ON "PayablePayment"("serviceId", "paidAt");

-- CreateIndex
CREATE INDEX "PayablePayment_company_id_paidAt_idx" ON "PayablePayment"("company_id", "paidAt");

-- CreateIndex
CREATE INDEX "PayablePayment_createdById_idx" ON "PayablePayment"("createdById");

-- CreateIndex
CREATE UNIQUE INDEX "PayrollEmployee_user_id_key" ON "PayrollEmployee"("user_id");

-- CreateIndex
CREATE INDEX "PayrollEmployee_ownerId_idx" ON "PayrollEmployee"("ownerId");

-- CreateIndex
CREATE INDEX "PayrollEmployee_company_id_idx" ON "PayrollEmployee"("company_id");

-- CreateIndex
CREATE INDEX "PayrollEmployee_user_id_idx" ON "PayrollEmployee"("user_id");

-- CreateIndex
CREATE INDEX "PayrollEmployee_company_id_nombre_idx" ON "PayrollEmployee"("company_id", "nombre");

-- CreateIndex
CREATE INDEX "PayrollPeriod_ownerId_idx" ON "PayrollPeriod"("ownerId");

-- CreateIndex
CREATE INDEX "PayrollPeriod_company_id_status_idx" ON "PayrollPeriod"("company_id", "status");

-- CreateIndex
CREATE INDEX "PayrollPeriod_company_id_startDate_endDate_idx" ON "PayrollPeriod"("company_id", "startDate", "endDate");

-- CreateIndex
CREATE INDEX "PayrollEmployeeConfig_company_id_idx" ON "PayrollEmployeeConfig"("company_id");

-- CreateIndex
CREATE INDEX "PayrollEmployeeConfig_periodId_employeeId_idx" ON "PayrollEmployeeConfig"("periodId", "employeeId");

-- CreateIndex
CREATE UNIQUE INDEX "PayrollEmployeeConfig_ownerId_periodId_employeeId_key" ON "PayrollEmployeeConfig"("ownerId", "periodId", "employeeId");

-- CreateIndex
CREATE UNIQUE INDEX "PayrollEntry_pago_combustible_tecnico_id_key" ON "PayrollEntry"("pago_combustible_tecnico_id");

-- CreateIndex
CREATE INDEX "PayrollEntry_company_id_idx" ON "PayrollEntry"("company_id");

-- CreateIndex
CREATE INDEX "PayrollEntry_periodId_employeeId_idx" ON "PayrollEntry"("periodId", "employeeId");

-- CreateIndex
CREATE INDEX "PayrollEntry_pago_combustible_tecnico_id_idx" ON "PayrollEntry"("pago_combustible_tecnico_id");

-- CreateIndex
CREATE INDEX "PayrollEntry_date_idx" ON "PayrollEntry"("date");

-- CreateIndex
CREATE INDEX "PayrollEmployeePeriodStatus_company_id_idx" ON "PayrollEmployeePeriodStatus"("company_id");

-- CreateIndex
CREATE INDEX "PayrollEmployeePeriodStatus_periodId_employeeId_idx" ON "PayrollEmployeePeriodStatus"("periodId", "employeeId");

-- CreateIndex
CREATE INDEX "PayrollEmployeePeriodStatus_status_idx" ON "PayrollEmployeePeriodStatus"("status");

-- CreateIndex
CREATE UNIQUE INDEX "PayrollEmployeePeriodStatus_ownerId_periodId_employeeId_key" ON "PayrollEmployeePeriodStatus"("ownerId", "periodId", "employeeId");

-- CreateIndex
CREATE UNIQUE INDEX "payroll_service_commission_requests_service_order_id_key" ON "payroll_service_commission_requests"("service_order_id");

-- CreateIndex
CREATE UNIQUE INDEX "payroll_service_commission_requests_payroll_entry_id_key" ON "payroll_service_commission_requests"("payroll_entry_id");

-- CreateIndex
CREATE INDEX "payroll_service_commission_requests_company_id_idx" ON "payroll_service_commission_requests"("company_id");

-- CreateIndex
CREATE INDEX "payroll_service_commission_requests_ownerId_idx" ON "payroll_service_commission_requests"("ownerId");

-- CreateIndex
CREATE INDEX "payroll_service_commission_requests_ownerId_status_idx" ON "payroll_service_commission_requests"("ownerId", "status");

-- CreateIndex
CREATE INDEX "payroll_service_commission_requests_employee_id_status_idx" ON "payroll_service_commission_requests"("employee_id", "status");

-- CreateIndex
CREATE INDEX "payroll_service_commission_requests_technician_user_id_stat_idx" ON "payroll_service_commission_requests"("technician_user_id", "status");

-- CreateIndex
CREATE INDEX "payroll_service_commission_requests_finalized_at_idx" ON "payroll_service_commission_requests"("finalized_at");

-- CreateIndex
CREATE INDEX "payroll_service_commission_requests_period_id_idx" ON "payroll_service_commission_requests"("period_id");

-- CreateIndex
CREATE INDEX "CompanyManualEntry_ownerId_idx" ON "CompanyManualEntry"("ownerId");

-- CreateIndex
CREATE INDEX "CompanyManualEntry_ownerId_published_idx" ON "CompanyManualEntry"("ownerId", "published");

-- CreateIndex
CREATE INDEX "CompanyManualEntry_ownerId_kind_idx" ON "CompanyManualEntry"("ownerId", "kind");

-- CreateIndex
CREATE INDEX "CompanyManualEntry_ownerId_audience_idx" ON "CompanyManualEntry"("ownerId", "audience");

-- CreateIndex
CREATE INDEX "CompanyManualEntry_ownerId_normalizedTitle_idx" ON "CompanyManualEntry"("ownerId", "normalizedTitle");

-- CreateIndex
CREATE INDEX "CompanyManualEntry_updatedAt_idx" ON "CompanyManualEntry"("updatedAt");

-- CreateIndex
CREATE UNIQUE INDEX "company_manual_owner_starter_key_unique" ON "CompanyManualEntry"("ownerId", "starterKey");

-- CreateIndex
CREATE UNIQUE INDEX "company_manual_dedup_unique" ON "CompanyManualEntry"("ownerId", "normalizedTitle", "kind", "audience", "moduleScopeKey", "targetRolesKey", "contentHash");

-- CreateIndex
CREATE UNIQUE INDEX "Service_orderNumber_key" ON "Service"("orderNumber");

-- CreateIndex
CREATE INDEX "Service_customerId_idx" ON "Service"("customerId");

-- CreateIndex
CREATE INDEX "Service_createdByUserId_idx" ON "Service"("createdByUserId");

-- CreateIndex
CREATE INDEX "Service_serviceType_idx" ON "Service"("serviceType");

-- CreateIndex
CREATE INDEX "Service_status_idx" ON "Service"("status");

-- CreateIndex
CREATE INDEX "Service_category_id_idx" ON "Service"("category_id");

-- CreateIndex
CREATE INDEX "Service_currentPhase_idx" ON "Service"("currentPhase");

-- CreateIndex
CREATE INDEX "Service_orderType_idx" ON "Service"("orderType");

-- CreateIndex
CREATE INDEX "Service_orderState_idx" ON "Service"("orderState");

-- CreateIndex
CREATE INDEX "Service_adminPhase_idx" ON "Service"("adminPhase");

-- CreateIndex
CREATE INDEX "Service_adminStatus_idx" ON "Service"("adminStatus");

-- CreateIndex
CREATE INDEX "Service_technicianId_idx" ON "Service"("technicianId");

-- CreateIndex
CREATE INDEX "Service_priority_idx" ON "Service"("priority");

-- CreateIndex
CREATE INDEX "Service_scheduledStart_idx" ON "Service"("scheduledStart");

-- CreateIndex
CREATE INDEX "Service_isDeleted_idx" ON "Service"("isDeleted");

-- CreateIndex
CREATE UNIQUE INDEX "ServiceClosing_serviceId_key" ON "ServiceClosing"("serviceId");

-- CreateIndex
CREATE INDEX "ServiceClosing_serviceId_idx" ON "ServiceClosing"("serviceId");

-- CreateIndex
CREATE INDEX "ServiceClosing_approvalStatus_idx" ON "ServiceClosing"("approvalStatus");

-- CreateIndex
CREATE INDEX "ServiceClosing_signatureStatus_idx" ON "ServiceClosing"("signatureStatus");

-- CreateIndex
CREATE INDEX "ServiceClosing_approvedAt_idx" ON "ServiceClosing"("approvedAt");

-- CreateIndex
CREATE INDEX "ServiceClosing_signedAt_idx" ON "ServiceClosing"("signedAt");

-- CreateIndex
CREATE INDEX "warranty_product_configs_owner_id_idx" ON "warranty_product_configs"("owner_id");

-- CreateIndex
CREATE INDEX "warranty_product_configs_company_id_is_active_idx" ON "warranty_product_configs"("company_id", "is_active");

-- CreateIndex
CREATE INDEX "warranty_product_configs_owner_id_is_active_idx" ON "warranty_product_configs"("owner_id", "is_active");

-- CreateIndex
CREATE INDEX "warranty_product_configs_owner_id_category_id_idx" ON "warranty_product_configs"("owner_id", "category_id");

-- CreateIndex
CREATE INDEX "warranty_product_configs_owner_id_category_code_idx" ON "warranty_product_configs"("owner_id", "category_code");

-- CreateIndex
CREATE INDEX "warranty_product_configs_owner_id_product_key_idx" ON "warranty_product_configs"("owner_id", "product_key");

-- CreateIndex
CREATE UNIQUE INDEX "technical_visits_order_id_key" ON "technical_visits"("order_id");

-- CreateIndex
CREATE INDEX "technical_visits_technician_id_idx" ON "technical_visits"("technician_id");

-- CreateIndex
CREATE INDEX "vehiculos_es_empresa_idx" ON "vehiculos"("es_empresa");

-- CreateIndex
CREATE INDEX "vehiculos_tecnico_id_propietario_idx" ON "vehiculos"("tecnico_id_propietario");

-- CreateIndex
CREATE INDEX "vehiculos_activo_idx" ON "vehiculos"("activo");

-- CreateIndex
CREATE INDEX "precios_combustible_combustible_tipo_idx" ON "precios_combustible"("combustible_tipo");

-- CreateIndex
CREATE INDEX "precios_combustible_combustible_tipo_activo_idx" ON "precios_combustible"("combustible_tipo", "activo");

-- CreateIndex
CREATE INDEX "precios_combustible_vigencia_desde_idx" ON "precios_combustible"("vigencia_desde");

-- CreateIndex
CREATE INDEX "pagos_combustible_tecnicos_tecnico_id_idx" ON "pagos_combustible_tecnicos"("tecnico_id");

-- CreateIndex
CREATE INDEX "pagos_combustible_tecnicos_createdAt_idx" ON "pagos_combustible_tecnicos"("createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "pagos_combustible_tecnicos_tecnico_id_fecha_inicio_fecha_fi_key" ON "pagos_combustible_tecnicos"("tecnico_id", "fecha_inicio", "fecha_fin");

-- CreateIndex
CREATE INDEX "salidas_tecnicas_tecnico_id_fecha_idx" ON "salidas_tecnicas"("tecnico_id", "fecha");

-- CreateIndex
CREATE INDEX "salidas_tecnicas_servicio_id_idx" ON "salidas_tecnicas"("servicio_id");

-- CreateIndex
CREATE INDEX "salidas_tecnicas_vehiculo_id_idx" ON "salidas_tecnicas"("vehiculo_id");

-- CreateIndex
CREATE INDEX "salidas_tecnicas_estado_idx" ON "salidas_tecnicas"("estado");

-- CreateIndex
CREATE INDEX "salidas_tecnicas_pago_combustible_id_idx" ON "salidas_tecnicas"("pago_combustible_id");

-- CreateIndex
CREATE INDEX "ServicePhaseHistory_serviceId_changedAt_idx" ON "ServicePhaseHistory"("serviceId", "changedAt");

-- CreateIndex
CREATE INDEX "ServicePhaseHistory_changedByUserId_idx" ON "ServicePhaseHistory"("changedByUserId");

-- CreateIndex
CREATE INDEX "ServiceAssignment_serviceId_idx" ON "ServiceAssignment"("serviceId");

-- CreateIndex
CREATE INDEX "ServiceAssignment_userId_idx" ON "ServiceAssignment"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "ServiceAssignment_serviceId_userId_key" ON "ServiceAssignment"("serviceId", "userId");

-- CreateIndex
CREATE INDEX "ServiceStep_serviceId_idx" ON "ServiceStep"("serviceId");

-- CreateIndex
CREATE UNIQUE INDEX "ServiceStep_serviceId_stepKey_key" ON "ServiceStep"("serviceId", "stepKey");

-- CreateIndex
CREATE INDEX "ServiceUpdate_serviceId_createdAt_idx" ON "ServiceUpdate"("serviceId", "createdAt");

-- CreateIndex
CREATE INDEX "ServiceUpdate_changedByUserId_idx" ON "ServiceUpdate"("changedByUserId");

-- CreateIndex
CREATE INDEX "ServiceFile_serviceId_idx" ON "ServiceFile"("serviceId");

-- CreateIndex
CREATE INDEX "ServiceFile_serviceId_createdAt_idx" ON "ServiceFile"("serviceId", "createdAt");

-- CreateIndex
CREATE INDEX "ServiceFile_serviceId_kind_idx" ON "ServiceFile"("serviceId", "kind");

-- CreateIndex
CREATE INDEX "ServiceFile_executionReportId_idx" ON "ServiceFile"("executionReportId");

-- CreateIndex
CREATE INDEX "ServiceFile_uploadedByUserId_idx" ON "ServiceFile"("uploadedByUserId");

-- CreateIndex
CREATE INDEX "service_orders_client_id_idx" ON "service_orders"("client_id");

-- CreateIndex
CREATE INDEX "service_orders_quotation_id_idx" ON "service_orders"("quotation_id");

-- CreateIndex
CREATE INDEX "service_orders_category_idx" ON "service_orders"("category");

-- CreateIndex
CREATE INDEX "service_orders_service_type_idx" ON "service_orders"("service_type");

-- CreateIndex
CREATE INDEX "service_orders_status_idx" ON "service_orders"("status");

-- CreateIndex
CREATE INDEX "service_orders_scheduled_for_idx" ON "service_orders"("scheduled_for");

-- CreateIndex
CREATE INDEX "service_orders_finalized_at_idx" ON "service_orders"("finalized_at");

-- CreateIndex
CREATE INDEX "service_orders_created_by_idx" ON "service_orders"("created_by");

-- CreateIndex
CREATE INDEX "service_orders_assigned_to_idx" ON "service_orders"("assigned_to");

-- CreateIndex
CREATE INDEX "service_orders_last_status_changed_at_idx" ON "service_orders"("last_status_changed_at");

-- CreateIndex
CREATE INDEX "service_orders_last_status_changed_by_user_id_idx" ON "service_orders"("last_status_changed_by_user_id");

-- CreateIndex
CREATE INDEX "service_orders_technician_confirmed_by_idx" ON "service_orders"("technician_confirmed_by");

-- CreateIndex
CREATE INDEX "service_orders_parent_order_id_idx" ON "service_orders"("parent_order_id");

-- CreateIndex
CREATE INDEX "service_orders_status_assigned_to_idx" ON "service_orders"("status", "assigned_to");

-- CreateIndex
CREATE INDEX "service_orders_status_last_status_changed_at_idx" ON "service_orders"("status", "last_status_changed_at");

-- CreateIndex
CREATE INDEX "service_orders_client_id_created_at_idx" ON "service_orders"("client_id", "created_at");

-- CreateIndex
CREATE INDEX "service_order_status_history_service_order_id_idx" ON "service_order_status_history"("service_order_id");

-- CreateIndex
CREATE INDEX "service_order_status_history_service_order_id_changed_at_idx" ON "service_order_status_history"("service_order_id", "changed_at");

-- CreateIndex
CREATE INDEX "service_order_status_history_changed_by_user_id_idx" ON "service_order_status_history"("changed_by_user_id");

-- CreateIndex
CREATE INDEX "service_evidences_service_order_id_idx" ON "service_evidences"("service_order_id");

-- CreateIndex
CREATE INDEX "service_evidences_service_order_id_created_at_idx" ON "service_evidences"("service_order_id", "created_at");

-- CreateIndex
CREATE INDEX "service_evidences_type_idx" ON "service_evidences"("type");

-- CreateIndex
CREATE INDEX "service_evidences_created_by_idx" ON "service_evidences"("created_by");

-- CreateIndex
CREATE INDEX "service_reports_service_order_id_idx" ON "service_reports"("service_order_id");

-- CreateIndex
CREATE INDEX "service_reports_service_order_id_created_at_idx" ON "service_reports"("service_order_id", "created_at");

-- CreateIndex
CREATE INDEX "service_reports_type_idx" ON "service_reports"("type");

-- CreateIndex
CREATE INDEX "service_reports_created_by_idx" ON "service_reports"("created_by");

-- CreateIndex
CREATE INDEX "publicidad_images_uploaded_by_id_idx" ON "publicidad_images"("uploaded_by_id");

-- CreateIndex
CREATE INDEX "publicidad_images_created_at_idx" ON "publicidad_images"("created_at");

-- CreateIndex
CREATE INDEX "Cotizacion_createdByUserId_idx" ON "Cotizacion"("createdByUserId");

-- CreateIndex
CREATE INDEX "Cotizacion_customerId_idx" ON "Cotizacion"("customerId");

-- CreateIndex
CREATE INDEX "Cotizacion_company_id_customerPhone_idx" ON "Cotizacion"("company_id", "customerPhone");

-- CreateIndex
CREATE INDEX "Cotizacion_company_id_customerPhoneNormalized_idx" ON "Cotizacion"("company_id", "customerPhoneNormalized");

-- CreateIndex
CREATE INDEX "Cotizacion_company_id_createdAt_idx" ON "Cotizacion"("company_id", "createdAt");

-- CreateIndex
CREATE INDEX "CotizacionItem_cotizacionId_idx" ON "CotizacionItem"("cotizacionId");

-- CreateIndex
CREATE INDEX "CotizacionItem_productId_idx" ON "CotizacionItem"("productId");

-- CreateIndex
CREATE INDEX "work_schedule_profiles_company_id_is_default_idx" ON "work_schedule_profiles"("company_id", "is_default");

-- CreateIndex
CREATE INDEX "work_schedule_profile_days_weekday_idx" ON "work_schedule_profile_days"("weekday");

-- CreateIndex
CREATE UNIQUE INDEX "work_schedule_profile_days_profile_id_weekday_key" ON "work_schedule_profile_days"("profile_id", "weekday");

-- CreateIndex
CREATE INDEX "work_coverage_rules_company_id_weekday_idx" ON "work_coverage_rules"("company_id", "weekday");

-- CreateIndex
CREATE UNIQUE INDEX "work_coverage_rules_company_id_role_weekday_key" ON "work_coverage_rules"("company_id", "role", "weekday");

-- CreateIndex
CREATE UNIQUE INDEX "work_employee_configs_user_id_key" ON "work_employee_configs"("user_id");

-- CreateIndex
CREATE INDEX "work_employee_configs_enabled_idx" ON "work_employee_configs"("enabled");

-- CreateIndex
CREATE INDEX "work_employee_configs_company_id_enabled_idx" ON "work_employee_configs"("company_id", "enabled");

-- CreateIndex
CREATE INDEX "work_employee_configs_schedule_profile_id_idx" ON "work_employee_configs"("schedule_profile_id");

-- CreateIndex
CREATE INDEX "work_schedule_exceptions_company_id_date_from_date_to_idx" ON "work_schedule_exceptions"("company_id", "date_from", "date_to");

-- CreateIndex
CREATE INDEX "work_schedule_exceptions_user_id_idx" ON "work_schedule_exceptions"("user_id");

-- CreateIndex
CREATE INDEX "work_schedule_exceptions_type_idx" ON "work_schedule_exceptions"("type");

-- CreateIndex
CREATE INDEX "work_schedule_exceptions_date_from_date_to_idx" ON "work_schedule_exceptions"("date_from", "date_to");

-- CreateIndex
CREATE INDEX "work_week_schedules_company_id_generated_at_idx" ON "work_week_schedules"("company_id", "generated_at");

-- CreateIndex
CREATE UNIQUE INDEX "work_week_schedules_company_id_week_start_date_key" ON "work_week_schedules"("company_id", "week_start_date");

-- CreateIndex
CREATE INDEX "work_day_assignments_week_schedule_id_idx" ON "work_day_assignments"("week_schedule_id");

-- CreateIndex
CREATE INDEX "work_day_assignments_user_id_idx" ON "work_day_assignments"("user_id");

-- CreateIndex
CREATE INDEX "work_day_assignments_date_idx" ON "work_day_assignments"("date");

-- CreateIndex
CREATE INDEX "work_day_assignments_weekday_idx" ON "work_day_assignments"("weekday");

-- CreateIndex
CREATE UNIQUE INDEX "work_day_assignments_week_schedule_id_user_id_date_key" ON "work_day_assignments"("week_schedule_id", "user_id", "date");

-- CreateIndex
CREATE INDEX "work_schedule_audit_logs_action_idx" ON "work_schedule_audit_logs"("action");

-- CreateIndex
CREATE INDEX "work_schedule_audit_logs_company_id_createdAt_idx" ON "work_schedule_audit_logs"("company_id", "createdAt");

-- CreateIndex
CREATE INDEX "work_schedule_audit_logs_actor_user_id_idx" ON "work_schedule_audit_logs"("actor_user_id");

-- CreateIndex
CREATE INDEX "work_schedule_audit_logs_target_user_id_idx" ON "work_schedule_audit_logs"("target_user_id");

-- CreateIndex
CREATE INDEX "work_schedule_audit_logs_week_start_date_idx" ON "work_schedule_audit_logs"("week_start_date");

-- CreateIndex
CREATE INDEX "work_schedule_audit_logs_createdAt_idx" ON "work_schedule_audit_logs"("createdAt");

-- CreateIndex
CREATE INDEX "ai_assistant_conversation_turns_owner_id_user_id_createdAt_idx" ON "ai_assistant_conversation_turns"("owner_id", "user_id", "createdAt");

-- CreateIndex
CREATE INDEX "ai_assistant_conversation_turns_company_id_module_createdAt_idx" ON "ai_assistant_conversation_turns"("company_id", "module", "createdAt");

-- CreateIndex
CREATE INDEX "ai_assistant_conversation_turns_owner_id_module_createdAt_idx" ON "ai_assistant_conversation_turns"("owner_id", "module", "createdAt");

-- CreateIndex
CREATE INDEX "ai_assistant_memories_company_id_module_idx" ON "ai_assistant_memories"("company_id", "module");

-- CreateIndex
CREATE INDEX "ai_assistant_memories_owner_id_user_id_module_idx" ON "ai_assistant_memories"("owner_id", "user_id", "module");

-- CreateIndex
CREATE INDEX "ai_assistant_memories_owner_id_user_id_last_source_at_idx" ON "ai_assistant_memories"("owner_id", "user_id", "last_source_at");

-- CreateIndex
CREATE UNIQUE INDEX "ai_assistant_memories_owner_id_user_id_scope_topic_key_key" ON "ai_assistant_memories"("owner_id", "user_id", "scope", "topic_key");

-- AddForeignKey
ALTER TABLE "open_sales_ticket_states" ADD CONSTRAINT "open_sales_ticket_states_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "company_license_audit_logs" ADD CONSTRAINT "company_license_audit_logs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "company_members" ADD CONSTRAINT "company_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "company_members" ADD CONSTRAINT "company_members_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "company_members" ADD CONSTRAINT "company_members_invited_by_fkey" FOREIGN KEY ("invited_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "auth_sessions" ADD CONSTRAINT "auth_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "auth_sessions" ADD CONSTRAINT "auth_sessions_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "employee_warnings" ADD CONSTRAINT "employee_warnings_employee_user_id_fkey" FOREIGN KEY ("employee_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "employee_warnings" ADD CONSTRAINT "employee_warnings_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "employee_warnings" ADD CONSTRAINT "employee_warnings_issued_by_user_id_fkey" FOREIGN KEY ("issued_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "employee_warnings" ADD CONSTRAINT "employee_warnings_annulled_by_user_id_fkey" FOREIGN KEY ("annulled_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "employee_warning_evidences" ADD CONSTRAINT "employee_warning_evidences_warning_id_fkey" FOREIGN KEY ("warning_id") REFERENCES "employee_warnings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "employee_warning_evidences" ADD CONSTRAINT "employee_warning_evidences_uploaded_by_user_id_fkey" FOREIGN KEY ("uploaded_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "employee_warning_signatures" ADD CONSTRAINT "employee_warning_signatures_warning_id_fkey" FOREIGN KEY ("warning_id") REFERENCES "employee_warnings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "employee_warning_signatures" ADD CONSTRAINT "employee_warning_signatures_employee_user_id_fkey" FOREIGN KEY ("employee_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "employee_warning_audit_logs" ADD CONSTRAINT "employee_warning_audit_logs_warning_id_fkey" FOREIGN KEY ("warning_id") REFERENCES "employee_warnings"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "employee_warning_audit_logs" ADD CONSTRAINT "employee_warning_audit_logs_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_flow_configs" ADD CONSTRAINT "marketing_flow_configs_updated_by_user_id_fkey" FOREIGN KEY ("updated_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_daily_stories" ADD CONSTRAINT "marketing_daily_stories_approved_by_user_id_fkey" FOREIGN KEY ("approved_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_daily_stories" ADD CONSTRAINT "marketing_daily_stories_research_id_fkey" FOREIGN KEY ("research_id") REFERENCES "marketing_researches"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_daily_stories" ADD CONSTRAINT "marketing_daily_stories_media_asset_id_fkey" FOREIGN KEY ("media_asset_id") REFERENCES "marketing_media_assets"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_ad_campaigns" ADD CONSTRAINT "marketing_ad_campaigns_gallery_asset_id_fkey" FOREIGN KEY ("gallery_asset_id") REFERENCES "marketing_media_assets"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_ad_campaigns" ADD CONSTRAINT "marketing_ad_campaigns_ai_research_id_fkey" FOREIGN KEY ("ai_research_id") REFERENCES "marketing_researches"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_ad_campaigns" ADD CONSTRAINT "marketing_ad_campaigns_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_ad_campaigns" ADD CONSTRAINT "marketing_ad_campaigns_updated_by_user_id_fkey" FOREIGN KEY ("updated_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_social_accounts" ADD CONSTRAINT "marketing_social_accounts_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_social_accounts" ADD CONSTRAINT "marketing_social_accounts_updated_by_user_id_fkey" FOREIGN KEY ("updated_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_activity_logs" ADD CONSTRAINT "marketing_activity_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_research_configs" ADD CONSTRAINT "marketing_research_configs_updated_by_user_id_fkey" FOREIGN KEY ("updated_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_researches" ADD CONSTRAINT "marketing_researches_forced_by_user_id_fkey" FOREIGN KEY ("forced_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_researches" ADD CONSTRAINT "marketing_researches_approved_by_user_id_fkey" FOREIGN KEY ("approved_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "marketing_learning_memories" ADD CONSTRAINT "marketing_learning_memories_source_research_id_fkey" FOREIGN KEY ("source_research_id") REFERENCES "marketing_researches"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_whatsapp_instances" ADD CONSTRAINT "user_whatsapp_instances_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_conversations" ADD CONSTRAINT "whatsapp_conversations_instance_id_fkey" FOREIGN KEY ("instance_id") REFERENCES "user_whatsapp_instances"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_messages" ADD CONSTRAINT "whatsapp_messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "whatsapp_conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_ai_media_summaries" ADD CONSTRAINT "whatsapp_ai_media_summaries_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "whatsapp_messages"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_ai_analysis_reports" ADD CONSTRAINT "whatsapp_ai_analysis_reports_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "whatsapp_conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_locations" ADD CONSTRAINT "user_locations_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "app_config" ADD CONSTRAINT "app_config_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_execution_reports" ADD CONSTRAINT "service_execution_reports_service_id_fkey" FOREIGN KEY ("service_id") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_execution_reports" ADD CONSTRAINT "service_execution_reports_technician_id_fkey" FOREIGN KEY ("technician_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_execution_changes" ADD CONSTRAINT "service_execution_changes_service_id_fkey" FOREIGN KEY ("service_id") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_execution_changes" ADD CONSTRAINT "service_execution_changes_execution_report_id_fkey" FOREIGN KEY ("execution_report_id") REFERENCES "service_execution_reports"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_execution_changes" ADD CONSTRAINT "service_execution_changes_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "checklist_templates" ADD CONSTRAINT "checklist_templates_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "service_categories"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "checklist_templates" ADD CONSTRAINT "checklist_templates_phase_id_fkey" FOREIGN KEY ("phase_id") REFERENCES "service_phases"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "checklist_items" ADD CONSTRAINT "checklist_items_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "checklist_templates"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "checklist_executions" ADD CONSTRAINT "checklist_executions_service_order_id_fkey" FOREIGN KEY ("service_order_id") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "checklist_executions" ADD CONSTRAINT "checklist_executions_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "checklist_templates"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "checklist_executions" ADD CONSTRAINT "checklist_executions_checklist_item_id_fkey" FOREIGN KEY ("checklist_item_id") REFERENCES "checklist_items"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "checklist_executions" ADD CONSTRAINT "checklist_executions_checked_by_fkey" FOREIGN KEY ("checked_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_outbox" ADD CONSTRAINT "notification_outbox_recipient_user_id_fkey" FOREIGN KEY ("recipient_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_order_notification_jobs" ADD CONSTRAINT "service_order_notification_jobs_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "service_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Punch" ADD CONSTRAINT "Punch_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Product" ADD CONSTRAINT "Product_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "taxes" ADD CONSTRAINT "taxes_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "suppliers" ADD CONSTRAINT "suppliers_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_invoices" ADD CONSTRAINT "purchase_invoices_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "suppliers"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_invoices" ADD CONSTRAINT "purchase_invoices_purchase_order_id_fkey" FOREIGN KEY ("purchase_order_id") REFERENCES "purchase_orders"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_invoices" ADD CONSTRAINT "purchase_invoices_uploaded_by_fkey" FOREIGN KEY ("uploaded_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_invoices" ADD CONSTRAINT "purchase_invoices_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "suppliers"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_orders" ADD CONSTRAINT "purchase_orders_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_order_items" ADD CONSTRAINT "purchase_order_items_purchase_order_id_fkey" FOREIGN KEY ("purchase_order_id") REFERENCES "purchase_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_order_items" ADD CONSTRAINT "purchase_order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_order_items" ADD CONSTRAINT "purchase_order_items_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "suppliers"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_receipts" ADD CONSTRAINT "purchase_receipts_purchase_order_id_fkey" FOREIGN KEY ("purchase_order_id") REFERENCES "purchase_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_receipts" ADD CONSTRAINT "purchase_receipts_received_by_fkey" FOREIGN KEY ("received_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_receipt_items" ADD CONSTRAINT "purchase_receipt_items_purchase_receipt_id_fkey" FOREIGN KEY ("purchase_receipt_id") REFERENCES "purchase_receipts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "purchase_receipt_items" ADD CONSTRAINT "purchase_receipt_items_purchase_order_item_id_fkey" FOREIGN KEY ("purchase_order_item_id") REFERENCES "purchase_order_items"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Client" ADD CONSTRAINT "Client_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Client" ADD CONSTRAINT "Client_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_customers" ADD CONSTRAINT "crm_commercial_customers_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "Client"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_customers" ADD CONSTRAINT "crm_commercial_customers_responsable_user_id_fkey" FOREIGN KEY ("responsable_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_customers" ADD CONSTRAINT "crm_commercial_customers_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_status_history" ADD CONSTRAINT "crm_commercial_status_history_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "crm_commercial_customers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_status_history" ADD CONSTRAINT "crm_commercial_status_history_usuario_que_cambio_fkey" FOREIGN KEY ("usuario_que_cambio") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_notes" ADD CONSTRAINT "crm_commercial_notes_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "crm_commercial_customers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_notes" ADD CONSTRAINT "crm_commercial_notes_usuario_id_fkey" FOREIGN KEY ("usuario_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_activities" ADD CONSTRAINT "crm_commercial_activities_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "crm_commercial_customers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_activities" ADD CONSTRAINT "crm_commercial_activities_creado_por_usuario_id_fkey" FOREIGN KEY ("creado_por_usuario_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_activities" ADD CONSTRAINT "crm_commercial_activities_asignado_usuario_id_fkey" FOREIGN KEY ("asignado_usuario_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_followup_tasks" ADD CONSTRAINT "crm_commercial_followup_tasks_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "crm_commercial_customers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_followup_tasks" ADD CONSTRAINT "crm_commercial_followup_tasks_asignado_usuario_id_fkey" FOREIGN KEY ("asignado_usuario_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_followup_tasks" ADD CONSTRAINT "crm_commercial_followup_tasks_creado_por_usuario_id_fkey" FOREIGN KEY ("creado_por_usuario_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_followup_tasks" ADD CONSTRAINT "crm_commercial_followup_tasks_completado_por_usuario_id_fkey" FOREIGN KEY ("completado_por_usuario_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_settings" ADD CONSTRAINT "crm_commercial_settings_updated_by_user_id_fkey" FOREIGN KEY ("updated_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_library_items" ADD CONSTRAINT "crm_commercial_library_items_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_library_items" ADD CONSTRAINT "crm_commercial_library_items_updated_by_user_id_fkey" FOREIGN KEY ("updated_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Sale" ADD CONSTRAINT "Sale_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Sale" ADD CONSTRAINT "Sale_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Client"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Sale" ADD CONSTRAINT "Sale_cashSessionId_fkey" FOREIGN KEY ("cashSessionId") REFERENCES "cash_sessions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Sale" ADD CONSTRAINT "Sale_deletedById_fkey" FOREIGN KEY ("deletedById") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Sale" ADD CONSTRAINT "Sale_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sale_credit_payments" ADD CONSTRAINT "sale_credit_payments_saleId_fkey" FOREIGN KEY ("saleId") REFERENCES "Sale"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sale_credit_payments" ADD CONSTRAINT "sale_credit_payments_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sale_credit_payments" ADD CONSTRAINT "sale_credit_payments_cashSessionId_fkey" FOREIGN KEY ("cashSessionId") REFERENCES "cash_sessions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sale_credit_payments" ADD CONSTRAINT "sale_credit_payments_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cashbox_daily" ADD CONSTRAINT "cashbox_daily_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cash_sessions" ADD CONSTRAINT "cash_sessions_cashboxDailyId_fkey" FOREIGN KEY ("cashboxDailyId") REFERENCES "cashbox_daily"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cash_sessions" ADD CONSTRAINT "cash_sessions_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cash_movements" ADD CONSTRAINT "cash_movements_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "cash_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cash_movements" ADD CONSTRAINT "cash_movements_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SaleItem" ADD CONSTRAINT "SaleItem_saleId_fkey" FOREIGN KEY ("saleId") REFERENCES "Sale"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SaleItem" ADD CONSTRAINT "SaleItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ncf_sequences" ADD CONSTRAINT "ncf_sequences_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ncf_audit_logs" ADD CONSTRAINT "ncf_audit_logs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ncf_audit_logs" ADD CONSTRAINT "ncf_audit_logs_sequence_id_fkey" FOREIGN KEY ("sequence_id") REFERENCES "ncf_sequences"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Close" ADD CONSTRAINT "Close_correctionOfCloseId_fkey" FOREIGN KEY ("correctionOfCloseId") REFERENCES "Close"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Close" ADD CONSTRAINT "Close_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CloseTransfer" ADD CONSTRAINT "CloseTransfer_closeId_fkey" FOREIGN KEY ("closeId") REFERENCES "Close"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CloseTransferVoucher" ADD CONSTRAINT "CloseTransferVoucher_transferId_fkey" FOREIGN KEY ("transferId") REFERENCES "CloseTransfer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DepositOrder" ADD CONSTRAINT "DepositOrder_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "deposit_banks" ADD CONSTRAINT "deposit_banks_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "deposit_bank_accounts" ADD CONSTRAINT "deposit_bank_accounts_bank_id_fkey" FOREIGN KEY ("bank_id") REFERENCES "deposit_banks"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FiscalInvoice" ADD CONSTRAINT "FiscalInvoice_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayableService" ADD CONSTRAINT "PayableService_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayablePayment" ADD CONSTRAINT "PayablePayment_serviceId_fkey" FOREIGN KEY ("serviceId") REFERENCES "PayableService"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayablePayment" ADD CONSTRAINT "PayablePayment_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEmployee" ADD CONSTRAINT "PayrollEmployee_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEmployee" ADD CONSTRAINT "PayrollEmployee_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEmployee" ADD CONSTRAINT "PayrollEmployee_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollPeriod" ADD CONSTRAINT "PayrollPeriod_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollPeriod" ADD CONSTRAINT "PayrollPeriod_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEmployeeConfig" ADD CONSTRAINT "PayrollEmployeeConfig_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEmployeeConfig" ADD CONSTRAINT "PayrollEmployeeConfig_periodId_fkey" FOREIGN KEY ("periodId") REFERENCES "PayrollPeriod"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEmployeeConfig" ADD CONSTRAINT "PayrollEmployeeConfig_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "PayrollEmployee"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEmployeeConfig" ADD CONSTRAINT "PayrollEmployeeConfig_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEntry" ADD CONSTRAINT "PayrollEntry_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEntry" ADD CONSTRAINT "PayrollEntry_periodId_fkey" FOREIGN KEY ("periodId") REFERENCES "PayrollPeriod"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEntry" ADD CONSTRAINT "PayrollEntry_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "PayrollEmployee"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEntry" ADD CONSTRAINT "PayrollEntry_pago_combustible_tecnico_id_fkey" FOREIGN KEY ("pago_combustible_tecnico_id") REFERENCES "pagos_combustible_tecnicos"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEntry" ADD CONSTRAINT "PayrollEntry_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEmployeePeriodStatus" ADD CONSTRAINT "PayrollEmployeePeriodStatus_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEmployeePeriodStatus" ADD CONSTRAINT "PayrollEmployeePeriodStatus_periodId_fkey" FOREIGN KEY ("periodId") REFERENCES "PayrollPeriod"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEmployeePeriodStatus" ADD CONSTRAINT "PayrollEmployeePeriodStatus_employeeId_fkey" FOREIGN KEY ("employeeId") REFERENCES "PayrollEmployee"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PayrollEmployeePeriodStatus" ADD CONSTRAINT "PayrollEmployeePeriodStatus_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_service_commission_requests" ADD CONSTRAINT "payroll_service_commission_requests_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_service_commission_requests" ADD CONSTRAINT "payroll_service_commission_requests_service_order_id_fkey" FOREIGN KEY ("service_order_id") REFERENCES "service_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_service_commission_requests" ADD CONSTRAINT "payroll_service_commission_requests_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "PayrollEmployee"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_service_commission_requests" ADD CONSTRAINT "payroll_service_commission_requests_period_id_fkey" FOREIGN KEY ("period_id") REFERENCES "PayrollPeriod"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_service_commission_requests" ADD CONSTRAINT "payroll_service_commission_requests_payroll_entry_id_fkey" FOREIGN KEY ("payroll_entry_id") REFERENCES "PayrollEntry"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_service_commission_requests" ADD CONSTRAINT "payroll_service_commission_requests_technician_user_id_fkey" FOREIGN KEY ("technician_user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_service_commission_requests" ADD CONSTRAINT "payroll_service_commission_requests_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_service_commission_requests" ADD CONSTRAINT "payroll_service_commission_requests_reviewed_by_user_id_fkey" FOREIGN KEY ("reviewed_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payroll_service_commission_requests" ADD CONSTRAINT "payroll_service_commission_requests_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Service" ADD CONSTRAINT "Service_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Client"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Service" ADD CONSTRAINT "Service_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "service_categories"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Service" ADD CONSTRAINT "Service_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Service" ADD CONSTRAINT "Service_technicianId_fkey" FOREIGN KEY ("technicianId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Service" ADD CONSTRAINT "Service_warrantyParentServiceId_fkey" FOREIGN KEY ("warrantyParentServiceId") REFERENCES "Service"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceClosing" ADD CONSTRAINT "ServiceClosing_serviceId_fkey" FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceClosing" ADD CONSTRAINT "ServiceClosing_approvedByUserId_fkey" FOREIGN KEY ("approvedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceClosing" ADD CONSTRAINT "ServiceClosing_rejectedByUserId_fkey" FOREIGN KEY ("rejectedByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceClosing" ADD CONSTRAINT "ServiceClosing_signatureFileId_fkey" FOREIGN KEY ("signatureFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceClosing" ADD CONSTRAINT "ServiceClosing_invoiceDraftFileId_fkey" FOREIGN KEY ("invoiceDraftFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceClosing" ADD CONSTRAINT "ServiceClosing_warrantyDraftFileId_fkey" FOREIGN KEY ("warrantyDraftFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceClosing" ADD CONSTRAINT "ServiceClosing_invoiceApprovedFileId_fkey" FOREIGN KEY ("invoiceApprovedFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceClosing" ADD CONSTRAINT "ServiceClosing_warrantyApprovedFileId_fkey" FOREIGN KEY ("warrantyApprovedFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceClosing" ADD CONSTRAINT "ServiceClosing_invoiceFinalFileId_fkey" FOREIGN KEY ("invoiceFinalFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceClosing" ADD CONSTRAINT "ServiceClosing_warrantyFinalFileId_fkey" FOREIGN KEY ("warrantyFinalFileId") REFERENCES "ServiceFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "warranty_product_configs" ADD CONSTRAINT "warranty_product_configs_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "warranty_product_configs" ADD CONSTRAINT "warranty_product_configs_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "service_categories"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "warranty_product_configs" ADD CONSTRAINT "warranty_product_configs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "technical_visits" ADD CONSTRAINT "technical_visits_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "technical_visits" ADD CONSTRAINT "technical_visits_technician_id_fkey" FOREIGN KEY ("technician_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vehiculos" ADD CONSTRAINT "vehiculos_tecnico_id_propietario_fkey" FOREIGN KEY ("tecnico_id_propietario") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pagos_combustible_tecnicos" ADD CONSTRAINT "pagos_combustible_tecnicos_tecnico_id_fkey" FOREIGN KEY ("tecnico_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "salidas_tecnicas" ADD CONSTRAINT "salidas_tecnicas_tecnico_id_fkey" FOREIGN KEY ("tecnico_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "salidas_tecnicas" ADD CONSTRAINT "salidas_tecnicas_vehiculo_id_fkey" FOREIGN KEY ("vehiculo_id") REFERENCES "vehiculos"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "salidas_tecnicas" ADD CONSTRAINT "salidas_tecnicas_servicio_id_fkey" FOREIGN KEY ("servicio_id") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "salidas_tecnicas" ADD CONSTRAINT "salidas_tecnicas_pago_combustible_id_fkey" FOREIGN KEY ("pago_combustible_id") REFERENCES "pagos_combustible_tecnicos"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServicePhaseHistory" ADD CONSTRAINT "ServicePhaseHistory_serviceId_fkey" FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServicePhaseHistory" ADD CONSTRAINT "ServicePhaseHistory_changedByUserId_fkey" FOREIGN KEY ("changedByUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceAssignment" ADD CONSTRAINT "ServiceAssignment_serviceId_fkey" FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceAssignment" ADD CONSTRAINT "ServiceAssignment_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceStep" ADD CONSTRAINT "ServiceStep_serviceId_fkey" FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceStep" ADD CONSTRAINT "ServiceStep_doneByUserId_fkey" FOREIGN KEY ("doneByUserId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceUpdate" ADD CONSTRAINT "ServiceUpdate_serviceId_fkey" FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceUpdate" ADD CONSTRAINT "ServiceUpdate_changedByUserId_fkey" FOREIGN KEY ("changedByUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceFile" ADD CONSTRAINT "ServiceFile_serviceId_fkey" FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceFile" ADD CONSTRAINT "ServiceFile_uploadedByUserId_fkey" FOREIGN KEY ("uploadedByUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ServiceFile" ADD CONSTRAINT "ServiceFile_executionReportId_fkey" FOREIGN KEY ("executionReportId") REFERENCES "service_execution_reports"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_orders" ADD CONSTRAINT "service_orders_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "Client"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_orders" ADD CONSTRAINT "service_orders_quotation_id_fkey" FOREIGN KEY ("quotation_id") REFERENCES "Cotizacion"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_orders" ADD CONSTRAINT "service_orders_parent_order_id_fkey" FOREIGN KEY ("parent_order_id") REFERENCES "service_orders"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_orders" ADD CONSTRAINT "service_orders_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_orders" ADD CONSTRAINT "service_orders_assigned_to_fkey" FOREIGN KEY ("assigned_to") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_orders" ADD CONSTRAINT "service_orders_last_status_changed_by_user_id_fkey" FOREIGN KEY ("last_status_changed_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_orders" ADD CONSTRAINT "service_orders_technician_confirmed_by_fkey" FOREIGN KEY ("technician_confirmed_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_order_status_history" ADD CONSTRAINT "service_order_status_history_service_order_id_fkey" FOREIGN KEY ("service_order_id") REFERENCES "service_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_order_status_history" ADD CONSTRAINT "service_order_status_history_changed_by_user_id_fkey" FOREIGN KEY ("changed_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_evidences" ADD CONSTRAINT "service_evidences_service_order_id_fkey" FOREIGN KEY ("service_order_id") REFERENCES "service_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_evidences" ADD CONSTRAINT "service_evidences_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_reports" ADD CONSTRAINT "service_reports_service_order_id_fkey" FOREIGN KEY ("service_order_id") REFERENCES "service_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "service_reports" ADD CONSTRAINT "service_reports_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "publicidad_images" ADD CONSTRAINT "publicidad_images_uploaded_by_id_fkey" FOREIGN KEY ("uploaded_by_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Cotizacion" ADD CONSTRAINT "Cotizacion_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Cotizacion" ADD CONSTRAINT "Cotizacion_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Client"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Cotizacion" ADD CONSTRAINT "Cotizacion_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CotizacionItem" ADD CONSTRAINT "CotizacionItem_cotizacionId_fkey" FOREIGN KEY ("cotizacionId") REFERENCES "Cotizacion"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CotizacionItem" ADD CONSTRAINT "CotizacionItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_schedule_profiles" ADD CONSTRAINT "work_schedule_profiles_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_schedule_profile_days" ADD CONSTRAINT "work_schedule_profile_days_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "work_schedule_profiles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_coverage_rules" ADD CONSTRAINT "work_coverage_rules_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_employee_configs" ADD CONSTRAINT "work_employee_configs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_employee_configs" ADD CONSTRAINT "work_employee_configs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_employee_configs" ADD CONSTRAINT "work_employee_configs_schedule_profile_id_fkey" FOREIGN KEY ("schedule_profile_id") REFERENCES "work_schedule_profiles"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_schedule_exceptions" ADD CONSTRAINT "work_schedule_exceptions_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_schedule_exceptions" ADD CONSTRAINT "work_schedule_exceptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "work_employee_configs"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_week_schedules" ADD CONSTRAINT "work_week_schedules_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_day_assignments" ADD CONSTRAINT "work_day_assignments_week_schedule_id_fkey" FOREIGN KEY ("week_schedule_id") REFERENCES "work_week_schedules"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_day_assignments" ADD CONSTRAINT "work_day_assignments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "work_employee_configs"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "work_schedule_audit_logs" ADD CONSTRAINT "work_schedule_audit_logs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ai_assistant_conversation_turns" ADD CONSTRAINT "ai_assistant_conversation_turns_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ai_assistant_memories" ADD CONSTRAINT "ai_assistant_memories_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

