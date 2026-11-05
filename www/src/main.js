import { folders, addons } from "virtual:everlook-modules";

const core = addons.find((entry) => entry.folder === "Everlook");
// Addons without a settings page of their own (the core and Preferences) are the foundation.
const foundation = addons.filter((entry) => !entry.settings);

function list(entries) {
  const ul = document.createElement("ul");
  ul.className = "modules";
  for (const entry of entries) {
    const item = document.createElement("li");
    const heading = document.createElement("h3");
    heading.textContent = entry.name;
    const notes = document.createElement("p");
    notes.textContent = entry.notes || entry.folder;
    item.append(heading, notes);
    ul.append(item);
  }
  return ul;
}

function section(title, note, entries) {
  const block = document.createElement("section");
  const heading = document.createElement("h2");
  heading.textContent = title;
  block.append(heading);
  if (note) {
    const copy = document.createElement("p");
    copy.className = "section-note";
    copy.textContent = note;
    block.append(copy);
  }
  block.append(list(entries));
  return block;
}

const app = document.querySelector("#app");
const wrap = document.createElement("main");
wrap.className = "wrap";

const header = document.createElement("header");
const title = document.createElement("h1");
title.textContent = "Everlook";
const version = document.createElement("p");
version.className = "version";
version.textContent = core && core.version ? `Version ${core.version}` : "Quality-of-life addons";
const lede = document.createElement("p");
lede.className = "lede";
lede.textContent =
  "Everlook is a set of small quality-of-life addons for World of Warcraft Forever. Each one is its own addon, grouped under Everlook in the AddOns list, with its settings under /el or the minimap button.";
const downloads = document.createElement("p");
downloads.className = "downloads";
const download = document.createElement("a");
download.href = "https://github.com/csfh/everlook/archive/refs/heads/main.zip";
download.textContent = "Download";
const source = document.createElement("a");
source.className = "quiet";
source.href = "https://github.com/csfh/everlook";
source.textContent = "Source on GitHub";
downloads.append(download, source);
const install = document.createElement("p");
install.className = "section-note";
install.textContent = "Unzip it and copy the Everlook folders into World of Warcraft/_forever_/Interface/AddOns.";
header.append(title, version, lede, downloads, install);

const modulesSection = document.createElement("div");
modulesSection.id = "modules";
modulesSection.append(section("Foundation", "Everything else builds on these.", foundation));
for (const folder of folders) {
  const entries = addons.filter((entry) => entry.settings === folder.name);
  if (entries.length) modulesSection.append(section(folder.name, folder.about, entries));
}

wrap.append(header, modulesSection);
app.append(wrap);
