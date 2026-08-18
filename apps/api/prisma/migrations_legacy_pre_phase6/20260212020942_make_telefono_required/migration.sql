/*
  Warnings:

  - Made the column `telefono` on table `Client` required. This step will fail if there are existing NULL values in that column.

*/
-- AlterTable
ALTER TABLE "Category" ALTER COLUMN "id" DROP DEFAULT;

-- AlterTable
ALTER TABLE "Client" ALTER COLUMN "telefono" SET NOT NULL;
