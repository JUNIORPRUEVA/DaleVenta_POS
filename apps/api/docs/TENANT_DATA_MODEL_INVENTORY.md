# Tenant Data Model Inventory

Generated at: 2026-11-09T03:05:42.270Z

| Model | Table | Classification | Tenant Column | Nullable | FK | Index | Recommended Action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EcfSupportGrant | ecf_support_grants | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| EcfDosaCertificationSession | ecf_dosa_certification_sessions | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfCertificationPortalTicket | ecf_certification_portal_tickets | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfCertificationPortalSession | ecf_certification_portal_sessions | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfDosaWebhookEvent | ecf_dosa_webhook_events | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfDosaCompanyCredential | ecf_dosa_company_credentials | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| Company | companies | Global platform data | - | - | not_applicable | not_applicable | No tenant migration required. |
| OpenSalesTicketState | open_sales_ticket_states | Company-owned root entity | company_id | false | present | missing | Add companyId-leading index. |
| CompanyLicenseAuditLog | company_license_audit_logs | Audit/retention data | company_id | false | present | present | No tenant migration required. |
| EcfCompanyConfiguration | ecf_company_configurations | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfOnboardingStep | ecf_onboarding_steps | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfCertificationAttempt | ecf_certification_attempts | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfEvidence | ecf_evidences | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfAuditLog | ecf_audit_logs | Audit/retention data | company_id | false | present | present | No tenant migration required. |
| EcfDosaIncident | ecf_dosa_incidents | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfPortalEnrollment | ecf_portal_enrollments | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfDgiiHabilitation | ecf_dgii_habilitations | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfDgiiApplicationSnapshot | ecf_dgii_application_snapshots | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfElectronicDocument | ecf_electronic_documents | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfCreditReservation | ecf_credit_reservations | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| EcfCreditReservationEvent | ecf_credit_reservation_events | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| EcfElectronicDocumentAttempt | ecf_electronic_document_attempts | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfEvidenceReceipt | ecf_evidence_receipts | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| EcfSandboxE32Trial | ecf_sandbox_e32_trials | Company-owned root entity | company_id | false | missing | missing | Add Company foreign key after ownership audit passes. |
| EcfSandboxE32TrialEvent | ecf_sandbox_e32_trial_events | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| EcfElectronicDocumentStatusLog | ecf_electronic_document_status_logs | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| CompanyMember | company_members | Join table | company_id | false | present | present | No tenant migration required. |
| AuthSession | auth_sessions | Session/security data | company_id | true | present | present | No tenant migration required. |
| User | users | User-personal data | company_id | true | present | present | No tenant migration required. |
| BackupRecord | backup_records | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| AppRelease | app_releases | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| PasswordResetToken | password_reset_tokens | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PasswordResetAuditLog | password_reset_audit_logs | Audit/retention data | company_id | true | present | present | No tenant migration required. |
| EmployeeWarning | employee_warnings | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| EmployeeWarningEvidence | employee_warning_evidences | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| EmployeeWarningSignature | employee_warning_signatures | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| EmployeeWarningAuditLog | employee_warning_audit_logs | Audit/retention data | - | - | not_applicable | not_applicable | No tenant migration required. |
| MarketingFlowConfig | marketing_flow_configs | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| MarketingDailyStory | marketing_daily_stories | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| MarketingMediaAsset | marketing_media_assets | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| MarketingAdCampaign | marketing_ad_campaigns | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| MarketingSocialAccount | marketing_social_accounts | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| MarketingActivityLog | marketing_activity_logs | Audit/retention data | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| MarketingResearchConfig | marketing_research_configs | Company-owned root entity | company_id | false | missing | missing | Add Company foreign key after ownership audit passes. |
| MarketingResearch | marketing_researches | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| MarketingLearningMemory | marketing_learning_memories | Audit/retention data | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| UserWhatsappInstance | user_whatsapp_instances | User-personal data | - | - | not_applicable | not_applicable | No tenant migration required. |
| WhatsappConversation | whatsapp_conversations | Audit/retention data | - | - | not_applicable | not_applicable | No tenant migration required. |
| WhatsappMessage | whatsapp_messages | Audit/retention data | - | - | not_applicable | not_applicable | No tenant migration required. |
| WhatsappAiMediaSummary | whatsapp_ai_media_summaries | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| WhatsappAiAnalysisReport | whatsapp_ai_analysis_reports | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| UserLocation | user_locations | User-personal data | - | - | not_applicable | not_applicable | No tenant migration required. |
| AppConfig | app_config | Company-owned root entity | company_id | true | present | present | Backfill deterministically, add FK/index, then make companyId NOT NULL. |
| ServiceExecutionReport | service_execution_reports | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| ServiceExecutionChange | service_execution_changes | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| ServiceCategory | service_categories | Global platform data | - | - | not_applicable | not_applicable | No tenant migration required. |
| ServicePhase | service_phases | Global platform data | - | - | not_applicable | not_applicable | No tenant migration required. |
| ChecklistTemplate | checklist_templates | Global platform data | - | - | not_applicable | not_applicable | No tenant migration required. |
| ChecklistItem | checklist_items | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| ChecklistExecution | checklist_executions | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| NotificationOutbox | notification_outbox | Audit/retention data | - | - | not_applicable | not_applicable | No tenant migration required. |
| TelemetryOutbox | telemetry_outbox | Audit/retention data | company_id | false | present | present | No tenant migration required. |
| ServiceOrderNotificationJob | service_order_notification_jobs | Audit/retention data | - | - | not_applicable | not_applicable | No tenant migration required. |
| Punch | Punch | Global platform data | - | - | not_applicable | not_applicable | No tenant migration required. |
| Product | Product | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| Warehouse | warehouses | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| WarehouseStock | warehouse_stocks | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| Terminal | terminals | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| InventoryMovement | inventory_movements | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| WarehouseTransfer | warehouse_transfers | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| WarehouseTransferItem | warehouse_transfer_items | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| InventoryZeroConfigState | inventory_zero_config_states | Company-owned root entity | company_id | false | present | missing | Add companyId-leading index. |
| UnitOfMeasure | unit_of_measures | Company-owned root entity | company_id | true | present | present | Backfill deterministically, add FK/index, then make companyId NOT NULL. |
| Tax | taxes | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| Supplier | suppliers | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PurchaseInvoice | purchase_invoices | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PurchaseOrderSequence | purchase_order_sequences | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| PurchaseOrder | purchase_orders | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PurchaseOrderItem | purchase_order_items | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| PurchaseReceipt | purchase_receipts | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| PurchaseReceiptItem | purchase_receipt_items | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| WebsiteProductOverride | website_product_overrides | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| Client | Client | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PriceList | price_lists | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PriceListProductRule | price_list_product_rules | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| PriceListQuantityTier | price_list_quantity_tiers | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| CrmCommercialCustomer | crm_commercial_customers | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| CrmCommercialStatusHistory | crm_commercial_status_history | Audit/retention data | - | - | not_applicable | not_applicable | No tenant migration required. |
| CrmCommercialNote | crm_commercial_notes | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| CrmCommercialActivity | crm_commercial_activities | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| CrmCommercialFollowupTask | crm_commercial_followup_tasks | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| CrmCommercialSetting | crm_commercial_settings | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| CrmCommercialLibraryItem | crm_commercial_library_items | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| Sale | Sale | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| SaleCreditPayment | sale_credit_payments | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| CashboxDaily | cashbox_daily | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| CashSession | cash_sessions | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| CashMovement | cash_movements | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| SaleItem | SaleItem | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| NcfSequence | ncf_sequences | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| NcfAuditLog | ncf_audit_logs | Audit/retention data | company_id | false | present | present | No tenant migration required. |
| EcfSequence | ecf_sequences | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfDgiiAuthorizedSequence | ecf_dgii_authorized_sequences | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfSaleWithoutDocument | ecf_sales_without_document | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| EcfSequenceAuditLog | ecf_sequence_audit_logs | Audit/retention data | company_id | false | present | present | No tenant migration required. |
| Close | Close | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| CloseTransfer | CloseTransfer | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| CloseTransferVoucher | CloseTransferVoucher | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| DepositOrder | DepositOrder | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| DepositBank | deposit_banks | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| DepositBankAccount | deposit_bank_accounts | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| FiscalInvoice | FiscalInvoice | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PayableService | PayableService | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PayablePayment | PayablePayment | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PayrollEmployee | PayrollEmployee | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PayrollPeriod | PayrollPeriod | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PayrollEmployeeConfig | PayrollEmployeeConfig | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PayrollEntry | PayrollEntry | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PayrollEmployeePeriodStatus | PayrollEmployeePeriodStatus | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PayrollServiceCommissionRequest | payroll_service_commission_requests | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| CompanyManualEntry | CompanyManualEntry | Global platform data | - | - | not_applicable | not_applicable | No tenant migration required. |
| Service | Service | Global platform data | - | - | not_applicable | not_applicable | No tenant migration required. |
| ServiceClosing | ServiceClosing | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| WarrantyProductConfig | warranty_product_configs | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| TechnicalVisit | technical_visits | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| Vehiculo | vehiculos | Global platform data | - | - | not_applicable | not_applicable | No tenant migration required. |
| PrecioCombustible | precios_combustible | Global platform data | - | - | not_applicable | not_applicable | No tenant migration required. |
| PagoCombustibleTecnico | pagos_combustible_tecnicos | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| SalidaTecnica | salidas_tecnicas | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| ServicePhaseHistory | ServicePhaseHistory | Audit/retention data | - | - | not_applicable | not_applicable | No tenant migration required. |
| ServiceAssignment | ServiceAssignment | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| ServiceStep | ServiceStep | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| ServiceUpdate | ServiceUpdate | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| ServiceFile | ServiceFile | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| ServiceOrder | service_orders | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| ServiceOrderStatusHistory | service_order_status_history | Audit/retention data | - | - | not_applicable | not_applicable | No tenant migration required. |
| ServiceEvidence | service_evidences | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| ServiceReport | service_reports | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| PublicidadImage | publicidad_images | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| Cotizacion | Cotizacion | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| CotizacionItem | CotizacionItem | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| WorkScheduleProfile | work_schedule_profiles | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| WorkScheduleProfileDay | work_schedule_profile_days | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| WorkCoverageRule | work_coverage_rules | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| WorkEmployeeConfig | work_employee_configs | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| WorkScheduleException | work_schedule_exceptions | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| WorkWeekSchedule | work_week_schedules | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| WorkDayAssignment | work_day_assignments | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| WorkScheduleAuditLog | work_schedule_audit_logs | Audit/retention data | company_id | false | present | present | No tenant migration required. |
| AiAssistantConversationTurn | ai_assistant_conversation_turns | Audit/retention data | company_id | false | present | present | No tenant migration required. |
| AiAssistantMemory | ai_assistant_memories | Audit/retention data | company_id | false | present | present | No tenant migration required. |
| GuardianIncidentGroup | guardian_incident_groups | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| GuardianIncident | guardian_incidents | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| GuardianEvidence | guardian_evidences | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| GuardianDiagnosis | guardian_diagnoses | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| GuardianIncidentEvent | guardian_incident_events | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| GuardianAccessLog | guardian_access_logs | Company-owned root entity | company_id | true | missing | missing | Backfill deterministically, add FK/index, then make companyId NOT NULL. |
| GuardianCompanyQuota | guardian_company_quotas | Company-owned root entity | company_id | false | present | missing | Add companyId-leading index. |
| GuardianAlert | guardian_alerts | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| GuardianAlertAttempt | guardian_alert_attempts | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| GuardianMachineCredential | guardian_machine_credentials | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| GuardianEnrollmentCode | guardian_enrollment_codes | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| GuardianWorkerHeartbeat | guardian_worker_heartbeats | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| SaleReconciliationObligation | sale_reconciliation_obligations | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| SaleReconciliationDeclarationEvent | sale_reconciliation_declaration_events | Company-owned root entity | company_id | false | missing | present | Add Company foreign key after ownership audit passes. |
| EcfLineClassification | ecf_line_classifications | Company-owned root entity | company_id | false | present | present | No tenant migration required. |

## Notes

- This inventory is generated from Prisma schema text.
- Company-owned root entities with nullable companyId require database audit and deterministic backfill before NOT NULL enforcement.
- Child entities without direct companyId must be protected through required parent ownership or migrated to direct ownership where high-risk.
