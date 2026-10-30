// Tiny Swords — main menu: save slots, settings, keybinds, animated background.

const settings = Settings.load();

/* ------------------------------- navigation -------------------------------- */

function showScreen(id) {
  document.querySelectorAll(".screen").forEach((s) => s.classList.add("hidden"));
  const screen = document.querySelector(`#${id}`);
  screen.classList.remove("hidden");
  // restart enter animation
  screen.style.animation = "none";
  void screen.offsetWidth;
  screen.style.animation = "";
  if (id === "screen-saves") renderSlots();
}

document.querySelectorAll("[data-goto]").forEach((button) =>
  button.addEventListener("click", () => showScreen(button.dataset.goto))
);

document.querySelector("#quit-btn")?.addEventListener("click", () => {
  // browsers block window.close for tabs the user didn't open via script
  if (history.length > 1) history.back();
  else showScreen("screen-main");
});

/* -------------------------------- save slots ------------------------------- */

function describe(save) {
  if (!save) return null;
  const when = new Date(save.savedAt).toLocaleString();
  const distTiles = Math.round(Math.hypot(save.x || 0, save.y || 0) / 64);
  return `HP ${save.hp ?? 100} · ${distTiles} tiles from camp · ${when}`;
}

function renderSlots() {
  const container = document.querySelector("#slots");
  container.innerHTML = "";
  for (const slot of Saves.slots) {
    const save = Saves.read(slot);
    const row = document.createElement("div");
    row.className = "slot";

    const info = document.createElement("div");
    info.className = "info";
    info.innerHTML = save
      ? `<strong>Save ${slot}</strong><small>${describe(save)}</small>`
      : `<strong>Save ${slot}</strong><small>Empty — start a new adventure</small>`;
    row.appendChild(info);

    if (save) {
      row.appendChild(actionButton("PLAY", "blue", () => { location.href = `index.html?slot=${slot}`; }));
      row.appendChild(actionButton("NEW", "red", () => {
        if (confirm(`Overwrite save ${slot} with a new world?`)) {
          Saves.remove(slot);
          location.href = `index.html?slot=${slot}&new=1`;
        }
      }));
      row.appendChild(actionButton("EXPORT", "blue", () => Saves.export(slot)));
      row.appendChild(actionButton("✕", "red", () => {
        if (confirm(`Delete save ${slot}?`)) { Saves.remove(slot); renderSlots(); }
      }));
    } else {
      row.appendChild(actionButton("NEW GAME", "blue", () => {
        location.href = `index.html?slot=${slot}&new=1`;
      }));
    }
    container.appendChild(row);
  }
}

function actionButton(label, color, onClick) {
  const button = document.createElement("button");
  button.className = `ts-btn small ${color}`;
  button.textContent = label;
  button.addEventListener("click", onClick);
  return button;
}

document.querySelector("#import-file").addEventListener("change", (event) => {
  const file = event.target.files[0];
  if (!file) return;
  file.text().then((text) => {
    try {
      const save = JSON.parse(text);
      if (typeof save.seed !== "number" || typeof save.x !== "number") throw new Error("bad save");
      const slot = Saves.slots.find((s) => !Saves.read(s)) ?? Saves.slots[0];
      Saves.write(slot, save);
      renderSlots();
      alert(`Imported into save ${slot}.`);
    } catch {
      alert("That file is not a valid Tiny Swords save.");
    }
  });
  event.target.value = "";
});

/* --------------------------------- settings -------------------------------- */

function renderDifficulty() {
  const container = document.querySelector("#difficulty-buttons");
  container.innerHTML = "";
  for (const [id, def] of Object.entries(DIFFICULTIES)) {
    const button = actionButton(def.label.toUpperCase(), id === settings.difficulty ? "red" : "blue", () => {
      settings.difficulty = id;
      Settings.save();
      renderDifficulty();
    });
    if (id === settings.difficulty) button.classList.add("active");
    container.appendChild(button);
  }
}

const BIND_LABELS = {
  up: "Move up", down: "Move down", left: "Move left",
  right: "Move right", attack: "Attack", menu: "Pause menu",
};
let listening = null;

function renderKeybinds() {
  const container = document.querySelector("#keybinds");
  container.innerHTML = "";
  for (const [action, label] of Object.entries(BIND_LABELS)) {
    const row = document.createElement("div");
    row.className = "keybind";
    const kbd = document.createElement("kbd");
    kbd.textContent = keyLabel(settings.keys[action]);
    kbd.addEventListener("click", () => {
      document.querySelectorAll(".keybind kbd").forEach((k) => k.classList.remove("listening"));
      listening = action;
      kbd.classList.add("listening");
      kbd.textContent = "PRESS KEY…";
    });
    row.append(Object.assign(document.createElement("span"), { textContent: label }), kbd);
    container.appendChild(row);
  }
}

addEventListener("keydown", (event) => {
  if (!listening) return;
  event.preventDefault();
  const key = event.key.toLowerCase();
  const taken = Object.entries(settings.keys).find(([action, k]) => k === key && action !== listening);
  if (taken) settings.keys[taken[0]] = settings.keys[listening];
  settings.keys[listening] = key;
  Settings.save();
  listening = null;
  renderKeybinds();
});

document.querySelector("#reset-keys").addEventListener("click", () => {
  settings.keys = { ...Settings.defaults.keys };
  Settings.save();
  renderKeybinds();
});

renderDifficulty();
renderKeybinds();

if (location.hash === "#settings" || location.hash === "#saves") {
  showScreen(`screen-${location.hash.slice(1)}`);
}

/* ---------------------------- animated background --------------------------- */

(async function background() {
  const canvas = document.querySelector("#bg");
  const bgCtx = canvas.getContext("2d");

  // solid teal fill while terrain assets load so the menu never looks blank
  function paintFallback() {
    bgCtx.fillStyle = "#47aca6";
    bgCtx.fillRect(0, 0, canvas.width, canvas.height);
  }

  function resize() {
    canvas.width = innerWidth;
    canvas.height = innerHeight;
    bgCtx.imageSmoothingEnabled = false;
    paintFallback();
  }
  addEventListener("resize", resize);
  resize();

  try {
    await Terrain.load(20260719);
  } catch (err) {
    console.warn("Terrain background unavailable", err);
    return;
  }

  let startX = 0, startY = 0;
  for (let step = 0; step < 40; step++) {
    const tx = step * 28 + 12, ty = ((step * 3) % 17) * 20 + 10;
    if (Terrain.levelAt(tx, ty) >= 0 && Terrain.levelAt(tx + 10, ty + 6) >= 0) {
      startX = (tx - 12) * 64;
      startY = (ty - 7) * 64;
      break;
    }
  }

  function frame(time) {
    const camX = Math.round(time * 0.022) + startX;
    const camY = Math.round(time * 0.012) + startY;
    const chunks = Terrain.drawView(bgCtx, camX, camY, canvas.width, canvas.height, time);
    const props = [];
    for (const chunk of chunks)
      for (const prop of chunk.props) {
        if (prop.x < camX - 220 || prop.x > camX + canvas.width + 220 ||
            prop.y < camY - 220 || prop.y > camY + canvas.height + 220) continue;
        props.push(prop);
      }
    props.sort((a, b) => a.y - b.y);
    for (const prop of props) Terrain.drawProp(bgCtx, prop, camX, camY, time);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
