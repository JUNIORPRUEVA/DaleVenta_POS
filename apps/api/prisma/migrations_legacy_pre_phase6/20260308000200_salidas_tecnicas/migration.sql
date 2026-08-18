-- Salidas Técnicas: vehículos, precios combustible, salidas y pagos

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  CREATE TYPE "SalidaTecnicaEstado" AS ENUM ('INICIADA', 'LLEGADA', 'FINALIZADA', 'APROBADA', 'RECHAZADA', 'PAGADA');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE "PagoCombustibleTecnicoEstado" AS ENUM ('PENDIENTE', 'PAGADO', 'CANCELADO');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS vehiculos (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  nombre TEXT NOT NULL,
  tipo TEXT NOT NULL,
  placa TEXT,
  combustible_tipo TEXT NOT NULL,
  rendimiento_km_litro DECIMAL(10,2),
  es_empresa BOOLEAN NOT NULL DEFAULT false,
  tecnico_id_propietario UUID,
  activo BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT vehiculos_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS precios_combustible (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  combustible_tipo TEXT NOT NULL,
  precio_por_litro DECIMAL(12,2) NOT NULL,
  vigencia_desde TIMESTAMP(3),
  activo BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT precios_combustible_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS pagos_combustible_tecnicos (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  tecnico_id UUID NOT NULL,
  fecha_inicio TIMESTAMP(3) NOT NULL,
  fecha_fin TIMESTAMP(3) NOT NULL,
  total_monto DECIMAL(12,2) NOT NULL DEFAULT 0,
  estado "PagoCombustibleTecnicoEstado" NOT NULL DEFAULT 'PENDIENTE',
  fecha_pago TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pagos_combustible_tecnicos_pkey PRIMARY KEY (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS pagos_combustible_tecnicos_tecnico_rango_key
  ON pagos_combustible_tecnicos (tecnico_id, fecha_inicio, fecha_fin);

CREATE INDEX IF NOT EXISTS pagos_combustible_tecnicos_tecnico_id_idx
  ON pagos_combustible_tecnicos (tecnico_id);

CREATE INDEX IF NOT EXISTS pagos_combustible_tecnicos_created_at_idx
  ON pagos_combustible_tecnicos ("createdAt");

CREATE TABLE IF NOT EXISTS salidas_tecnicas (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  servicio_id UUID NOT NULL,
  tecnico_id UUID NOT NULL,
  vehiculo_id UUID NOT NULL,
  pago_combustible_id UUID,

  es_vehiculo_propio BOOLEAN NOT NULL DEFAULT false,
  genera_pago_combustible BOOLEAN NOT NULL DEFAULT false,

  fecha TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  hora_salida TIMESTAMP(3) NOT NULL,
  hora_llegada TIMESTAMP(3),
  hora_final TIMESTAMP(3),

  lat_salida DOUBLE PRECISION NOT NULL,
  lng_salida DOUBLE PRECISION NOT NULL,
  lat_llegada DOUBLE PRECISION,
  lng_llegada DOUBLE PRECISION,
  lat_final DOUBLE PRECISION,
  lng_final DOUBLE PRECISION,

  km_estimados DECIMAL(12,2),
  litros_estimados DECIMAL(12,2),
  precio_combustible_litro DECIMAL(12,2),
  monto_combustible DECIMAL(12,2) NOT NULL DEFAULT 0,

  estado "SalidaTecnicaEstado" NOT NULL DEFAULT 'INICIADA',
  observacion TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT salidas_tecnicas_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS salidas_tecnicas_tecnico_id_fecha_idx
  ON salidas_tecnicas (tecnico_id, fecha);

CREATE INDEX IF NOT EXISTS salidas_tecnicas_servicio_id_idx
  ON salidas_tecnicas (servicio_id);

CREATE INDEX IF NOT EXISTS salidas_tecnicas_vehiculo_id_idx
  ON salidas_tecnicas (vehiculo_id);

CREATE INDEX IF NOT EXISTS salidas_tecnicas_estado_idx
  ON salidas_tecnicas (estado);

CREATE INDEX IF NOT EXISTS salidas_tecnicas_pago_combustible_id_idx
  ON salidas_tecnicas (pago_combustible_id);

-- Una sola salida abierta (INICIADA/LLEGADA) por técnico
CREATE UNIQUE INDEX IF NOT EXISTS salidas_tecnicas_tecnico_open_key
  ON salidas_tecnicas (tecnico_id)
  WHERE estado IN ('INICIADA', 'LLEGADA');

-- FKs (idempotentes)
DO $$
BEGIN
  ALTER TABLE vehiculos
    ADD CONSTRAINT vehiculos_tecnico_id_propietario_fkey
    FOREIGN KEY (tecnico_id_propietario) REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE pagos_combustible_tecnicos
    ADD CONSTRAINT pagos_combustible_tecnicos_tecnico_id_fkey
    FOREIGN KEY (tecnico_id) REFERENCES users(id) ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE salidas_tecnicas
    ADD CONSTRAINT salidas_tecnicas_servicio_id_fkey
    FOREIGN KEY (servicio_id) REFERENCES "Service"(id) ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE salidas_tecnicas
    ADD CONSTRAINT salidas_tecnicas_tecnico_id_fkey
    FOREIGN KEY (tecnico_id) REFERENCES users(id) ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE salidas_tecnicas
    ADD CONSTRAINT salidas_tecnicas_vehiculo_id_fkey
    FOREIGN KEY (vehiculo_id) REFERENCES vehiculos(id) ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE salidas_tecnicas
    ADD CONSTRAINT salidas_tecnicas_pago_combustible_id_fkey
    FOREIGN KEY (pago_combustible_id) REFERENCES pagos_combustible_tecnicos(id) ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
