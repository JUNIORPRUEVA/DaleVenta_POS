-- Excepcion de multi-almacen en las concesiones por empresa.
--
-- Un plan que no incluye multi-almacen (Basico o Negocio) puede concederselo a
-- una empresa concreta sin cambiarle el plan. Es lo que permite migrar a los
-- clientes antiguos al plan Basico sin quitarles una funcion que ya usaban.
--
-- Aditivo y no destructivo: la columna nace con `false`, asi que ninguna
-- concesion existente cambia de comportamiento.
ALTER TABLE "license_company_overrides"
  ADD COLUMN "allow_multi_warehouse" BOOLEAN NOT NULL DEFAULT false;
