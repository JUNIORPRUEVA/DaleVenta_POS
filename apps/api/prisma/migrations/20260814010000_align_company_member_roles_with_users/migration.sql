UPDATE company_members cm
SET role = CASE u.role::text
  WHEN 'ADMIN' THEN 'ADMIN'::company_member_role
  WHEN 'CAJERO' THEN 'CASHIER'::company_member_role
  WHEN 'VENDEDOR' THEN 'SELLER'::company_member_role
  WHEN 'ASISTENTE' THEN 'MANAGER'::company_member_role
  WHEN 'MARKETING' THEN 'MANAGER'::company_member_role
  WHEN 'TECNICO' THEN 'MANAGER'::company_member_role
  ELSE cm.role
END,
updated_at = NOW()
FROM users u
WHERE cm.user_id = u.id
  AND cm.status = 'ACTIVE'::company_member_status
  AND cm.role = 'VIEWER'::company_member_role;
