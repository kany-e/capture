CREATE TABLE capture_attachments (
    id TEXT PRIMARY KEY,
    capture_id TEXT NOT NULL REFERENCES captures(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('image')),
    media_type TEXT NOT NULL CHECK (media_type IN ('image/png', 'image/jpeg')),
    relative_path TEXT NOT NULL UNIQUE,
    byte_size INTEGER NOT NULL CHECK (byte_size > 0 AND byte_size <= 8388608),
    pixel_width INTEGER NOT NULL CHECK (pixel_width > 0 AND pixel_width <= 20000),
    pixel_height INTEGER NOT NULL CHECK (pixel_height > 0 AND pixel_height <= 20000),
    sha256 TEXT NOT NULL CHECK (length(sha256) = 64),
    sort_order INTEGER NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    UNIQUE (capture_id, sort_order)
);

CREATE INDEX capture_attachments_capture_id_idx
ON capture_attachments(capture_id, sort_order);
