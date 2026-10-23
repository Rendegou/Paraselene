import type { IssuedPreview, WorkingEditRequest, WorkingOperation, WorkingCopy } from "../../../lib/ipc";
export interface NativeGeneration {
  preview(request: Omit<WorkingEditRequest, "workId" | "expectedRevision">): Promise<IssuedPreview>;
  send(previewId: string): Promise<WorkingOperation>;
  cancel(operationId: string): Promise<boolean>;
  list(documentId: string): Promise<WorkingOperation[]>;
  apply(documentId: string, operationId: string): Promise<WorkingCopy>;
  reject(operationId: string): Promise<void>;
}
