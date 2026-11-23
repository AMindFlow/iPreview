CREATE TABLE catalog_identity_sequence (
    entity TEXT PRIMARY KEY CHECK (entity IN ('source', 'media')),
    last_id INTEGER NOT NULL CHECK (last_id >= 0)
);

INSERT INTO catalog_identity_sequence (entity, last_id)
SELECT 'source', COALESCE(MAX(id), 0) FROM sources
UNION ALL
SELECT 'media', COALESCE(MAX(id), 0) FROM media;

CREATE TRIGGER remember_source_id AFTER INSERT ON sources
BEGIN
    UPDATE catalog_identity_sequence SET last_id = NEW.id
    WHERE entity = 'source' AND last_id < NEW.id;
END;

CREATE TRIGGER remember_media_id AFTER INSERT ON media
BEGIN
    UPDATE catalog_identity_sequence SET last_id = NEW.id
    WHERE entity = 'media' AND last_id < NEW.id;
END;

PRAGMA user_version = 5;
