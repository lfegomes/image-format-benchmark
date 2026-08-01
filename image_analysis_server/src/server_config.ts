import path from "node:path";

export interface ServerConfig {
  rootDir: string;
  host: string;
  port: number;
}

const DEFAULT_ROOT_DIR = "../dataset/generated";
const DEFAULT_HOST = "0.0.0.0";
const DEFAULT_PORT = 8080;

export function parseServerConfig(argv: readonly string[]): ServerConfig {
  let rootDir = DEFAULT_ROOT_DIR;
  let host = DEFAULT_HOST;
  let port = DEFAULT_PORT;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--root":
        rootDir = requireValue(argv, ++i, "--root");
        break;
      case "--host":
        host = requireValue(argv, ++i, "--host");
        break;
      case "--port": {
        const raw = requireValue(argv, ++i, "--port");
        const parsed = Number(raw);
        if (!Number.isInteger(parsed) || parsed <= 0) {
          throw new Error(`--port inválido: ${raw}`);
        }
        port = parsed;
        break;
      }
    }
  }

  return {
    rootDir: path.resolve(rootDir),
    host,
    port,
  };
}

function requireValue(
  argv: readonly string[],
  index: number,
  flag: string,
): string {
  const value = argv[index];
  if (value === undefined) {
    throw new Error(`Faltou valor para ${flag}`);
  }
  return value;
}
