-- Add FIFTEEN_MINUTES_PENDING to ServiceOrderNotificationJobKind enum
DO $$
  BEGIN
    ALTER TYPE "ServiceOrderNotificationJobKind" ADD VALUE 'FIFTEEN_MINUTES_PENDING' AFTER 'THIRTY_MINUTES_BEFORE';
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END $$;
