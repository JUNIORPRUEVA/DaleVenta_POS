/**
 * Read-only query used to capture the target snapshot for the legacy migration.
 *
 * It ONLY reads. It is executed through an authorized read-only channel
 * (e.g. `psql` inside the production database container) and its output is
 * stored as JSON to feed `--target-snapshot` in the migrator dry-run.
 *
 * Usage (authorized read-only channel, output redirected to a file):
 *   psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA -f - < target-snapshot.query.sql
 */

WITH ids AS (
  SELECT
    'f3651f62-be10-41aa-bde7-663cf990eae8'::uuid AS company_id,
    'ffc9ef9b-9157-418d-8aa1-94112278bb68'::uuid AS warehouse_id,
    '00931697-e152-48bc-9e44-02023e14d465'::uuid AS terminal_id,
    'adc4bf90-41b3-4e20-99eb-f37d398200f5'::uuid AS owner_user_id
)
SELECT jsonb_pretty(
  jsonb_build_object(
    'source', 'OFFLINE_READ_ONLY',
    'capturedAt', to_char((now() AT TIME ZONE 'UTC'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'company', (
      SELECT jsonb_build_object(
        'id', c.id,
        'name', c.name,
        'status', c.status::text,
        'plan', c.plan::text,
        'licenseStatus', c.license_status::text,
        'productSource', c.product_source::text,
        'maxProducts', c.max_products
      )
      FROM companies c, ids WHERE c.id = ids.company_id
    ),
    'warehouse', (
      SELECT jsonb_build_object(
        'id', w.id, 'companyId', w.company_id, 'name', w.name, 'code', w.code, 'isActive', w.is_active
      )
      FROM warehouses w, ids WHERE w.id = ids.warehouse_id
    ),
    'terminal', (
      SELECT jsonb_build_object(
        'id', t.id, 'companyId', t.company_id, 'name', t.name, 'code', t.code,
        'isActive', t.is_active, 'defaultWarehouseId', t.default_warehouse_id
      )
      FROM terminals t, ids WHERE t.id = ids.terminal_id
    ),
    'ownerUser', (
      SELECT jsonb_build_object('id', u.id, 'companyId', u.company_id, 'blocked', u.blocked)
      FROM users u, ids WHERE u.id = ids.owner_user_id
    ),
    'baseline', jsonb_build_object(
      'productsTotal', (SELECT count(*) FROM "Product" p, ids WHERE p.company_id = ids.company_id),
      'productsNonArchived', (SELECT count(*) FROM "Product" p, ids WHERE p.company_id = ids.company_id AND p.archived_at IS NULL),
      'sales', (SELECT count(*) FROM "Sale" s, ids WHERE s.company_id = ids.company_id),
      'saleItems', (SELECT count(*) FROM "SaleItem" i JOIN "Sale" s ON s.id = i."saleId", ids WHERE s.company_id = ids.company_id),
      'warehouseStocks', (SELECT count(*) FROM warehouse_stocks w, ids WHERE w.company_id = ids.company_id),
      'inventoryMovements', (SELECT count(*) FROM inventory_movements m, ids WHERE m.company_id = ids.company_id),
      'cashSessions', (SELECT count(*) FROM cash_sessions c, ids WHERE c.company_id = ids.company_id),
      'cashboxDaily', (SELECT count(*) FROM cashbox_daily d, ids WHERE d.company_id = ids.company_id),
      'cashMovements', (SELECT count(*) FROM cash_movements cm, ids WHERE cm.company_id = ids.company_id),
      'clients', (SELECT count(*) FROM "Client" cl, ids WHERE cl.company_id = ids.company_id),
      'suppliers', (SELECT count(*) FROM suppliers su, ids WHERE su.company_id = ids.company_id),
      'purchaseOrders', (SELECT count(*) FROM purchase_orders po, ids WHERE po.company_id = ids.company_id),
      'taxes', (SELECT count(*) FROM taxes tx, ids WHERE tx.company_id = ids.company_id),
      'ncfSequences', (SELECT count(*) FROM ncf_sequences ns, ids WHERE ns.company_id = ids.company_id)
    ),
    'notes', jsonb_build_array(
      'Snapshot de solo lectura para la validacion del destino (Fase 3).',
      'Baseline esperado: todo en 0 para el alcance de Fase 3.'
    )
  )
);
