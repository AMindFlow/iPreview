CREATE TABLE media_new (
    id INTEGER PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES sources(id),
    relative_path TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('image', 'video', 'audio')),
    available INTEGER NOT NULL DEFAULT 1 CHECK (available IN (0, 1)),
    UNIQUE (source_id, relative_path)
);

INSERT INTO media_new (id, source_id, relative_path, kind, available)
SELECT id, source_id, relative_path, kind, available FROM media;

DROP TABLE media;
ALTER TABLE media_new RENAME TO media;

CREATE TRIGGER remember_media_id AFTER INSERT ON media
BEGIN
    UPDATE catalog_identity_sequence SET last_id = NEW.id
    WHERE entity = 'media' AND last_id < NEW.id;
END;

PRAGMA user_version = 6;
