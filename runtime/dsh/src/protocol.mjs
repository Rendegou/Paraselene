/** Experimental line-JSON protocol. No credentials, paths, or provider configuration cross it. */
export const PROTOCOL_VERSION = 1;
export const MAX_LINE_BYTES = 65_536;
const ID = /^[a-zA-Z0-9_-]{1,80}$/;
const spaces = new Set(["personal", "idea", "novel", "learning"]);

/** Safe parser errors deliberately exclude the rejected input. */
export class ProtocolError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function keys(value, allowed) {
  if (Object.keys(value).some(key => !allowed.includes(key))) {
    throw new ProtocolError("INVALID_COMMAND", "Unexpected command fields");
  }
}

/** Parse one complete UTF-8 JSON line into a validated command, without executing it. */
export function parseCommand(line) {
  if (Buffer.byteLength(line, "utf8") > MAX_LINE_BYTES) {
    throw new ProtocolError("INPUT_TOO_LARGE", "Command exceeds the input limit");
  }
  let command;
  try { command = JSON.parse(line); }
  catch { throw new ProtocolError("INVALID_JSON", "Command must be JSON"); }
  if (!object(command) || command.version !== PROTOCOL_VERSION) {
    throw new ProtocolError("PROTOCOL_VERSION", "Unsupported protocol version");
  }
  if (command.type === "shutdown") {
    keys(command, ["version", "type"]);
    return command;
  }
  if (typeof command.requestId !== "string" || !ID.test(command.requestId)) {
    throw new ProtocolError("INVALID_ID", "A bounded request identifier is required");
  }
  if (command.type === "cancel") {
    keys(command, ["version", "type", "requestId"]);
    return command;
  }
  if (command.type !== "run") throw new ProtocolError("INVALID_COMMAND", "Unknown command");
  keys(command, ["version", "type", "requestId", "scope", "prompt"]);
  if (!object(command.scope) || !spaces.has(command.scope.space)) {
    throw new ProtocolError("INVALID_SCOPE", "A recognized memory space is required");
  }
  keys(command.scope, ["space", "workId"]);
  if (command.scope.space === "novel") {
    if (typeof command.scope.workId !== "string" || !ID.test(command.scope.workId)) {
      throw new ProtocolError("INVALID_SCOPE", "Novel requests require a work identifier");
    }
  } else if (command.scope.workId !== undefined) {
    throw new ProtocolError("INVALID_SCOPE", "Work identifiers belong to the novel space");
  }
  if (typeof command.prompt !== "string" || !command.prompt.trim() || command.prompt.length > 8_192) {
    throw new ProtocolError("INVALID_PROMPT", "A nonempty prompt within the input limit is required");
  }
  return command;
}
