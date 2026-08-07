# Tenant Data Model Inventory

Generated at: 2026-08-07T02:08:14.573Z

| Model | Table | Classification | Tenant Column | Nullable | FK | Index | Recommended Action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Company | companies | Global platform data | - | - | not_applicable | not_applicable | No tenant migration required. |
| CompanyLicenseAuditLog | company_license_audit_logs | Audit/retention data | company_id | false | present | present | No tenant migration required. |
| CompanyMember | company_members | Join table | company_id | false | present | present | No tenant migration required. |
| AuthSession | auth_sessions | Session/security data | company_id | true | present | present | No tenant migration required. |
| User | users | User-personal data | company_id | true | present | present | No tenant migration required. |
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
| ServiceOrderNotificationJob | service_order_notification_jobs | Audit/retention data | - | - | not_applicable | not_applicable | No tenant migration required. |
| Punch | Punch | Global platform data | - | - | not_applicable | not_applicable | No tenant migration required. |
| Product | Product | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| Supplier | suppliers | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PurchaseInvoice | purchase_invoices | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PurchaseOrderSequence | purchase_order_sequences | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| PurchaseOrder | purchase_orders | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| PurchaseOrderItem | purchase_order_items | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| PurchaseReceipt | purchase_receipts | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| PurchaseReceiptItem | purchase_receipt_items | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| WebsiteProductOverride | website_product_overrides | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| Client | Client | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
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
| Close | Close | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
| CloseTransfer | CloseTransfer | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| CloseTransferVoucher | CloseTransferVoucher | Company-owned child entity | - | - | not_applicable | not_applicable | Add companyId through trusted parent backfill or document inherited parent ownership. |
| DepositOrder | DepositOrder | Company-owned root entity | company_id | false | present | present | No tenant migration required. |
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

## Notes

- This inventory is generated from Prisma schema text.
- Company-owned root entities with nullable companyId require database audit and deterministic backfill before NOT NULL enforcement.
- Child entities without direct companyId must be protected through required parent ownership or migrated to direct ownership where high-risk.
