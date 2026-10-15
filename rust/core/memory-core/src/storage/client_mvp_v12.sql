-- Explicit paid operations stay separate from editable discussion snapshots.
CREATE TABLE novel_operations (
 operation_id TEXT PRIMARY KEY,
 work_id TEXT NOT NULL REFERENCES works(id) ON DELETE CASCADE,
 document_id TEXT NOT NULL REFERENCES novel_documents(id) ON DELETE CASCADE,
 thread_id TEXT NOT NULL REFERENCES novel_threads(thread_id) ON DELETE CASCADE,
 binding TEXT NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('running','completed','cancelled','failed')),
 output TEXT, patch_id TEXT REFERENCES novel_patches(id) ON DELETE SET NULL,
 error TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE INDEX idx_novel_operations_thread ON novel_operations(work_id,document_id,thread_id,created_at);
