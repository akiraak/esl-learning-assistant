import fs from "fs";
import path from "path";
import { config } from "./config";

const logFilePath = path.join(config.dataDir, "server.log");

function write(level: "info" | "warn" | "error", message: string): void {
  const line = `[${new Date().toISOString()}] [${level}] ${message}`;
  if (level === "error") {
    console.error(line);
  } else {
    console.log(line);
  }
  try {
    fs.appendFileSync(logFilePath, line + "\n");
  } catch {
    // ログファイルへの書き込みに失敗してもサーバー本体は継続させる
  }
}

export const logger = {
  info: (message: string) => write("info", message),
  warn: (message: string) => write("warn", message),
  error: (message: string) => write("error", message),
};
