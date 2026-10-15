-- CLIENT-MVP: archive without deleting versions, working copies or discussion.
ALTER TABLE novel_documents ADD COLUMN archived_at TEXT;

-- Rebuild the constrained parent and its only child in one migration transaction.
-- The temporary child copy prevents ON DELETE CASCADE from losing lore versions.
CREATE TEMP TABLE lore_versions_backup AS SELECT * FROM lore_versions;
DROP TABLE lore_versions;
CREATE TABLE lore_entries_v11 (
 id TEXT PRIMARY KEY,
 work_id TEXT NOT NULL REFERENCES works(id) ON DELETE CASCADE,
 kind TEXT NOT NULL CHECK(kind IN ('character','location','world','timeline','taboo','style')),
 name TEXT NOT NULL, aliases TEXT NOT NULL DEFAULT '[]',
 status TEXT NOT NULL CHECK(status IN ('candidate','confirmed','rejected')),
 scope TEXT NOT NULL DEFAULT 'whole', head_version INTEGER NOT NULL CHECK(head_version > 0),
 created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
INSERT INTO lore_entries_v11 SELECT * FROM lore_entries;
DROP TABLE lore_entries;
ALTER TABLE lore_entries_v11 RENAME TO lore_entries;
CREATE INDEX idx_lore_entries_work ON lore_entries(work_id,kind,status);
CREATE TABLE lore_versions (
 id TEXT PRIMARY KEY, entry_id TEXT NOT NULL REFERENCES lore_entries(id) ON DELETE CASCADE,
 version INTEGER NOT NULL, body TEXT NOT NULL,
 confirmed INTEGER NOT NULL CHECK(confirmed IN (0,1)),
 origin TEXT NOT NULL CHECK(origin IN ('author','ai')), created_at TEXT NOT NULL,
 UNIQUE(entry_id,version)
);
INSERT INTO lore_versions SELECT * FROM lore_versions_backup;
DROP TABLE lore_versions_backup;
CREATE TABLE lore_source_anchors (
 entry_id TEXT NOT NULL REFERENCES lore_entries(id) ON DELETE CASCADE,
 anchor_id TEXT NOT NULL REFERENCES source_anchors(id) ON DELETE CASCADE,
 PRIMARY KEY(entry_id,anchor_id)
);
CREATE TABLE novel_threads (
 thread_id TEXT PRIMARY KEY,
 work_id TEXT NOT NULL REFERENCES works(id) ON DELETE CASCADE,
 document_id TEXT NOT NULL REFERENCES novel_documents(id) ON DELETE CASCADE,
 revision INTEGER NOT NULL CHECK(revision > 0),
 schema_version INTEGER NOT NULL CHECK(schema_version = 1),
 snapshot TEXT NOT NULL, saved_at TEXT NOT NULL
);
CREATE INDEX idx_novel_threads_document ON novel_threads(work_id,document_id,saved_at);
