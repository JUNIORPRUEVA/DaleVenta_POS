ALTER TABLE ecf_electronic_documents ADD COLUMN print_stamp JSONB;
CREATE FUNCTION ecf_preserve_print_stamp() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.print_stamp IS NOT NULL AND NEW.print_stamp IS DISTINCT FROM OLD.print_stamp THEN
    RAISE EXCEPTION 'ECF_PRINT_STAMP_IMMUTABLE';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ecf_print_stamp_immutable BEFORE UPDATE OF print_stamp ON ecf_electronic_documents
  FOR EACH ROW EXECUTE FUNCTION ecf_preserve_print_stamp();
