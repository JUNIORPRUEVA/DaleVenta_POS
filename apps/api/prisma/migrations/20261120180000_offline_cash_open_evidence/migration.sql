-- Optional proof hash; historical openings and reception timestamps stay intact.
ALTER TABLE "cash_sessions" ADD COLUMN "offline_opening_evidence_hash" TEXT;
