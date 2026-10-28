import modules from "virtual:everlook-modules";

const core = modules.find((entry) => entry.folder === "Everlook");
const island = modules.filter((entry) => entry.island);
const rest = modules.filter((entry) => entry.folder !== "Everlook" && !entry.island);

function list(entries, className) {
  const ul = document.createElement("ul");
  ul.className = className ? `modules ${className}` : "modules";
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

function section(title, note, entries, className) {
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
  block.append(list(entries, className));
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
version.textContent = core && core.version ? `Version ${core.version}` : "Quality-of-life addon";
const lede = document.createElement("p");
lede.className = "lede";
lede.textContent = "Everlook is a quality-of-life addon for World of Warcraft. It tweaks the default interface. Each module starts off, and you turn on the ones you want from the Everlook settings page.";
const downloads = document.createElement("p");
downloads.className = "downloads";
const latest = document.createElement("a");
latest.href = "https://github.com/csfh/everlook/releases/latest";
latest.textContent = "Latest release";
const all = document.createElement("a");
all.className = "quiet";
all.href = "https://github.com/csfh/everlook/releases";
all.textContent = "All releases";
downloads.append(latest, all);
header.append(title, version, lede, downloads);

const modulesSection = document.createElement("div");
modulesSection.id = "modules";
modulesSection.append(
  section("Modules", "Optional addons that depend on Everlook. They start disabled.", rest),
  section("Island", "The island and the modules that add to it.", island, "island"),
);

wrap.append(header, modulesSection);
app.append(wrap);
