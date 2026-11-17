CREATE TABLE pending_rename (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    source_id INTEGER NOT NULL REFERENCES sources(id),
    old_path TEXT NOT NULL,
    new_path TEXT NOT NULL,
    is_directory INTEGER NOT NULL CHECK (is_directory IN (0, 1)),
    file_identity TEXT NOT NULL
);

PRAGMA user_version = 2;
