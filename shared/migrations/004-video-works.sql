CREATE TABLE video_works (
    video_id INTEGER PRIMARY KEY REFERENCES media(id) ON DELETE CASCADE,
    structure TEXT NOT NULL CHECK (structure IN ('complete', 'compact'))
);

CREATE TABLE video_work_images (
    video_id INTEGER NOT NULL REFERENCES video_works(video_id) ON DELETE CASCADE,
    media_id INTEGER NOT NULL REFERENCES media(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('sample', 'cover', 'photo')),
    set_position INTEGER NOT NULL CHECK (set_position >= 0),
    position INTEGER NOT NULL CHECK (position >= 0),
    PRIMARY KEY (video_id, role, set_position, position),
    UNIQUE (video_id, media_id)
);

PRAGMA user_version = 4;
