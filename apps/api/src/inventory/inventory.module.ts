import { Global, Module } from "@nestjs/common";
import { InventoryMutationService } from "./inventory-mutation.service";

@Global()
@Module({
  providers: [InventoryMutationService],
  exports: [InventoryMutationService],
})
export class InventoryModule {}
