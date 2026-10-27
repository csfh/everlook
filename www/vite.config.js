import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const addonRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "addon");
const virtualId = "virtual:everlook-modules";
const resolvedId = "\0" + virtualId;

function field(toc, key) {
  const match = toc.match(new RegExp(`^## ${key}:\\s*(.*)$`, "m"));
  return match ? match[1].trim() : "";
}

function modules() {
  const folders = readdirSync(addonRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && /^Everlook(_[A-Za-z0-9]+)?$/.test(entry.name))
    .map((entry) => entry.name)
    .sort((left, right) => left.localeCompare(right));
  return folders.map((folder) => {
    const toc = readFileSync(join(addonRoot, folder, `${folder}.toc`), "utf8");
    const name = folder === "Everlook" ? "Everlook" : folder.slice("Everlook_".length);
    return {
      folder,
      name,
      notes: field(toc, "Notes"),
      version: field(toc, "Version"),
      island: name === "Island" || name.startsWith("Island"),
    };
  });
}

function modulesPlugin() {
  return {
    name: "everlook-modules",
    resolveId(source) {
      if (source === virtualId) return resolvedId;
    },
    load(id) {
      if (id === resolvedId) return `export default ${JSON.stringify(modules())};\n`;
    },
  };
}

export default defineConfig({
  plugins: [modulesPlugin()],
});
