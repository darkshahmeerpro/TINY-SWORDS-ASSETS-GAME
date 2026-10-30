// Settings, save slots and asset loading shared by the menu and the game.

const Settings = {
  defaults: {
    keys: { up: "w", down: "s", left: "a", right: "d", attack: " ", menu: "escape" },
    difficulty: "normal",
  },
  data: null,
  load() {
    try {
      this.data = { ...this.defaults, ...JSON.parse(localStorage.getItem("ts_settings")) };
      this.data.keys = { ...this.defaults.keys, ...this.data.keys };
    } catch {
      this.data = JSON.parse(JSON.stringify(this.defaults));
    }
    return this.data;
  },
  save() { localStorage.setItem("ts_settings", JSON.stringify(this.data)); },
};

const Saves = {
  slots: [1, 2, 3],
  key(slot) { return `ts_save_${slot}`; },
  read(slot) {
    try { return JSON.parse(localStorage.getItem(this.key(slot))); } catch { return null; }
  },
  write(slot, data) {
    localStorage.setItem(this.key(slot), JSON.stringify({ ...data, savedAt: Date.now() }));
  },
  remove(slot) { localStorage.removeItem(this.key(slot)); },
  latestSlot() {
    let best = null, bestTime = -1;
    for (const slot of this.slots) {
      const save = this.read(slot);
      if (save && save.savedAt > bestTime) { best = slot; bestTime = save.savedAt; }
    }
    return best;
  },
  export(slot) {
    const save = this.read(slot);
    if (!save) return;
    const blob = new Blob([JSON.stringify(save, null, 2)], { type: "application/json" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `tiny-swords-save-${slot}.json`;
    link.click();
    URL.revokeObjectURL(link.href);
  },
};

const DIFFICULTIES = {
  easy: { label: "Easy", monsterRate: 0.6, monsterDamage: 0.55, monsterHp: 0.75 },
  normal: { label: "Normal", monsterRate: 1, monsterDamage: 1, monsterHp: 1 },
  hard: { label: "Hard", monsterRate: 1.5, monsterDamage: 1.7, monsterHp: 1.4 },
};

function loadImages(files) {
  const images = {};
  return Promise.all(
    Object.entries(files).map(([name, src]) => new Promise((resolve, reject) => {
      images[name] = new Image();
      images[name].onload = resolve;
      images[name].onerror = () => reject(new Error(`Failed to load ${src}`));
      images[name].src = src;
    }))
  ).then(() => images);
}

function keyLabel(key) {
  if (key === " ") return "SPACE";
  if (key === "escape") return "ESC";
  if (key.startsWith("arrow")) return key.slice(5).toUpperCase() + " ARROW";
  return key.toUpperCase();
}
