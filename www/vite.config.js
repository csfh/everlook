import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

// The addons are the Everlook* folders at the repository root.
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const virtualId = "virtual:everlook-modules";
const resolvedId = "\0" + virtualId;

function field(toc, key) {
  const match = toc.match(new RegExp(`^## ${key}:\\s*(.*)$`, "m"));
  return match ? match[1].trim() : "";
}

// The settings folders, in the order /el shows them (EverlookPreferences.FOLDERS).
function folderOrder() {
  const source = readFileSync(join(root, "EverlookPreferences", "preferences.lua"), "utf8");
  const list = source.slice(source.indexOf("Preferences.FOLDERS"), source.indexOf("}\n", source.indexOf("Preferences.FOLDERS")));
  return [...list.matchAll(/name = "([^"]+)", about = "([^"]+)"/g)].map(([, name, about]) => ({ name, about }));
}

// The folder an addon puts its page in: the last quoted argument of its NewPage or NewCanvasPage call,
// in the Lua files its TOC lists.
function settingsFolder(folder, toc) {
  const files = toc
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.endsWith(".lua") && !line.startsWith("#"));
  // Comment lines are skipped: Preferences' own usage example names a folder.
  const source = files
    .map((file) => readFileSync(join(root, folder, ...file.split("\\")), "utf8"))
    .join("\n")
    .split("\n")
    .filter((line) => !line.trim().startsWith("--"))
    .join("\n");
  const call = source.match(/EverlookPreferences:New(?:Canvas)?Page\(([^)]*)\)/);
  if (!call) return null;
  const strings = [...call[1].matchAll(/"([^"]+)"/g)].map((match) => match[1]);
  return strings.length ? strings[strings.length - 1] : null;
}

function modules() {
  const addons = readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && /^Everlook[A-Za-z0-9]*$/.test(entry.name))
    .map((entry) => {
      const folder = entry.name;
      const toc = readFileSync(join(root, folder, `${folder}.toc`), "utf8");
      return {
        folder,
        name: field(toc, "Title"),
        notes: field(toc, "Notes"),
        version: field(toc, "Version"),
        settings: settingsFolder(folder, toc),
      };
    })
    .sort((left, right) => left.name.localeCompare(right.name));
  return { folders: folderOrder(), addons };
}

function modulesPlugin() {
  return {
    name: "everlook-modules",
    resolveId(source) {
      if (source === virtualId) return resolvedId;
    },
    load(id) {
      if (id !== resolvedId) return;
      const { folders, addons } = modules();
      return `export const folders = ${JSON.stringify(folders)};\nexport const addons = ${JSON.stringify(addons)};\n`;
    },
  };
}

export default defineConfig({
  plugins: [modulesPlugin()],
});
