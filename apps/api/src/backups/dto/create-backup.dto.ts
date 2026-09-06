import { IsIn, IsOptional } from "class-validator";
import { BackupTypeName } from "../backup.types";

export class CreateBackupDto {
  @IsOptional()
  @IsIn(["MANUAL"])
  type?: BackupTypeName;
}
