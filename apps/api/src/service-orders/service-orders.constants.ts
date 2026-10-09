import { ServiceOrderStatus } from '@prisma/client';

export const SERVICE_ORDER_DEFAULT_STATUSES = [
  ServiceOrderStatus.PENDIENTE,
  ServiceOrderStatus.EN_PROCESO,
  ServiceOrderStatus.EN_PAUSA,
];

export const SERVICE_ORDER_TRANSITIONS: Record<
  ServiceOrderStatus,
  ServiceOrderStatus[]
> = {
  [ServiceOrderStatus.PENDIENTE]: [
    ServiceOrderStatus.EN_PROCESO,
    ServiceOrderStatus.POSPUESTA,
    ServiceOrderStatus.CANCELADO,
  ],
  [ServiceOrderStatus.EN_PROCESO]: [
    ServiceOrderStatus.EN_PAUSA,
    ServiceOrderStatus.FINALIZADO,
    ServiceOrderStatus.POSPUESTA,
    ServiceOrderStatus.CANCELADO,
  ],
  [ServiceOrderStatus.EN_PAUSA]: [
    ServiceOrderStatus.EN_PROCESO,
    ServiceOrderStatus.POSPUESTA,
    ServiceOrderStatus.CANCELADO,
  ],
  [ServiceOrderStatus.POSPUESTA]: [
    ServiceOrderStatus.PENDIENTE,
    ServiceOrderStatus.CANCELADO,
  ],
  [ServiceOrderStatus.FINALIZADO]: [],
  [ServiceOrderStatus.CANCELADO]: [ServiceOrderStatus.POSPUESTA],
};
