import { spawn } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const VERSION = "0.2.1-rc.2";
const PROFILE = "paraselene-offline";
const packages = ["llm", "session", "session-projection", "system-prompt", "tools", "agent", "agent-loop"];

/** Explicit least-capability profile. The CLI has more dependencies; none are implicitly mounted. */
export function offlineEntries() {
  return [
    ...packages.map(id => ({
      id, name: pathToFileURL(require.resolve(`@deepseek-ai/dsh-${id}`)).href,
      ...(id === "agent-loop" ? { config: { agents: [] } } : {}),
    })),
    { id: "paraselene-offline-provider", name: new URL("./offline-provider.mjs", import.meta.url).href },
    { id: "paraselene-offline-bridge", name: new URL("./bridge.mjs", import.meta.url).href },
  ];
}

/** Launch the official dsh CLI with an ephemeral profile without inheriting model credentials. */
export async function launchOfflineBridge() {
  const cliPackage = require.resolve("@deepseek-ai/dsh/package.json");
  const manifest = JSON.parse(await readFile(cliPackage, "utf8"));
  if (manifest.version !== VERSION) throw new Error("The installed dsh version does not match the probe");
  const directory = await mkdtemp(join(tmpdir(), "paraselene-dsh-"));
  try {
    const profileDirectory = join(directory, "profiles", PROFILE);
    await mkdir(profileDirectory, { recursive: true });
    await writeFile(join(profileDirectory, "package.json"), JSON.stringify({
      name: "paraselene-offline-profile", private: true, dsh: { profile: { bundles: [] } },
    }));
    await writeFile(join(profileDirectory, "cordis.patch.yml"), JSON.stringify([{ insert: offlineEntries() }]));
    const env = {};
    for (const key of ["PATH", "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "SystemRoot", "WINDIR", "TEMP", "TMP", "TMPDIR", "COMSPEC", "PATHEXT", "LANG", "LC_ALL", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "NODE_EXTRA_CA_CERTS", "SSL_CERT_FILE"]) {
      if (process.env[key] !== undefined) env[key] = process.env[key];
    }
    env.DSH_HOME = directory;
    const child = spawn(process.execPath, [join(dirname(cliPackage), "lib", "bin.js"), "--profile", PROFILE], {
      cwd: directory, env, stdio: ["pipe", "pipe", "pipe"], windowsHide: true,
    });
    const exited = new Promise(resolve => {
      child.once("error", error => resolve({ error }));
      child.once("exit", (code, signal) => resolve({ code, signal }));
    });
    let disposing;
    return {
      child, exited, directory,
      dispose() {
        disposing ??= (async () => {
          child.stdin.end();
          const grace = setTimeout(() => { child.kill("SIGTERM"); }, 2_000);
          const force = setTimeout(() => { child.kill("SIGKILL"); }, 5_000);
          try { await exited; }
          finally { clearTimeout(grace); clearTimeout(force); await rm(directory, { recursive: true, force: true }); }
        })();
        return disposing;
      },
    };
  } catch (error) {
    await rm(directory, { recursive: true, force: true });
    throw error;
  }
}
