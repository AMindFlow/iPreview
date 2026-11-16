CREATE TABLE sources (
    id INTEGER PRIMARY KEY,
    path TEXT NOT NULL UNIQUE,
    layout TEXT NOT NULL CHECK (layout IN ('flat', 'creator', 'multi-creator')),
    available INTEGER NOT NULL DEFAULT 1 CHECK (available IN (0, 1))
);

CREATE TABLE media (
    id INTEGER PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES sources(id),
    relative_path TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('image', 'video')),
    available INTEGER NOT NULL DEFAULT 1 CHECK (available IN (0, 1)),
    UNIQUE (source_id, relative_path)
);

CREATE TABLE albums (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0)
);

CREATE TABLE album_media (
    album_id INTEGER NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
    media_id INTEGER NOT NULL REFERENCES media(id),
    position INTEGER NOT NULL CHECK (position >= 0),
    PRIMARY KEY (album_id, media_id)
);

PRAGMA user_version = 1;
