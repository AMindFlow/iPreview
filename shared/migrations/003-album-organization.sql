CREATE TABLE source_album_organization (
    id INTEGER PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES sources(id),
    album_path TEXT NOT NULL,
    favorite INTEGER NOT NULL DEFAULT 0 CHECK (favorite IN (0, 1)),
    rating_half INTEGER CHECK (rating_half IS NULL OR (typeof(rating_half) = 'integer' AND rating_half BETWEEN 0 AND 10)),
    UNIQUE (source_id, album_path)
);

CREATE TABLE tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 100),
    normalized_name TEXT NOT NULL UNIQUE CHECK (length(normalized_name) > 0)
);

CREATE TABLE source_album_tags (
    source_album_id INTEGER NOT NULL REFERENCES source_album_organization(id) ON DELETE CASCADE,
    tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (source_album_id, tag_id)
);
CREATE INDEX source_album_tags_by_tag ON source_album_tags(tag_id, source_album_id);

CREATE TABLE source_album_cover_media (
    source_album_id INTEGER NOT NULL REFERENCES source_album_organization(id) ON DELETE CASCADE,
    media_id INTEGER NOT NULL REFERENCES media(id),
    position INTEGER NOT NULL CHECK (typeof(position) = 'integer' AND position BETWEEN 0 AND 3),
    PRIMARY KEY (source_album_id, position),
    UNIQUE (source_album_id, media_id)
);

PRAGMA user_version = 3;
