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
    .map((entry) => entry.name);
  // Listed in the order of the names shown, not of the folders, so Nameplate titles comes before Nameplates.
  return folders.map((folder) => {
    const toc = readFileSync(join(addonRoot, folder, `${folder}.toc`), "utf8");
    const id = folder === "Everlook" ? "Everlook" : folder.slice("Everlook_".length);
    // The folder's words in sentence case, as Settings and the game's addon list name a module.
    const words = id.replace(/(?<!^)(?=[A-Z])/g, " ").toLowerCase();
    return {
      folder,
      name: words.charAt(0).toUpperCase() + words.slice(1),
      notes: field(toc, "Notes"),
      version: field(toc, "Version"),
      island: id.startsWith("Island"),
    };
  }).sort((left, right) => left.name.localeCompare(right.name));
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
