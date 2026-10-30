// Tiny Swords — gameplay: player, villagers, monsters, combat, saving.

const UNIT_FILES = {};
for (const color of ["blue", "red", "yellow", "purple", "black"]) {
  UNIT_FILES[`pawn-${color}-idle`] = `assets/units/pawn-${color}-idle.png`;
  UNIT_FILES[`pawn-${color}-run`] = `assets/units/pawn-${color}-run.png`;
  UNIT_FILES[`warrior-${color}-idle`] = `assets/units/warrior-${color}-idle.png`;
  UNIT_FILES[`warrior-${color}-run`] = `assets/units/warrior-${color}-run.png`;
  UNIT_FILES[`warrior-${color}-attack`] = `assets/units/warrior-${color}-attack.png`;
}
UNIT_FILES["sheep-idle"] = "assets/decor/sheep-idle.png";
UNIT_FILES["sheep-move"] = "assets/decor/sheep-move.png";

const FRAME = 192;
const ANIM = {
  idle: { frames: 8, speed: 130 },
  run: { frames: 6, speed: 90 },
  attack: { frames: 4, speed: 90 },
};

const canvas = document.querySelector("#game");
const ctx = canvas.getContext("2d");
const settings = Settings.load();
const difficulty = DIFFICULTIES[settings.difficulty] || DIFFICULTIES.normal;

let unitImages = {};
let view = { w: innerWidth, h: innerHeight };
const camera = { x: 0, y: 0 };
const pressed = {};
let paused = false;
let gameTime = 0;

const params = new URLSearchParams(location.search);
const slot = Number(params.get("slot")) || 1;

const player = {
  x: 0, y: 0, vx: 0, vy: 0, radius: 13,
  hp: 100, maxHp: 100, facing: 1,
  state: "idle", attackT: 0, hurtT: 0, deadT: 0,
  spawnX: 0, spawnY: 0,
};

const entities = [];          // villagers, guards, monsters, sheep
const spawnedChunks = new Set();
let message = { text: "", t: 0 };

/* --------------------------------- helpers --------------------------------- */

const dist2 = (a, b) => (a.x - b.x) ** 2 + (a.y - b.y) ** 2;

function showMessage(text, seconds = 2.4) {
  message = { text, t: seconds };
  const el = document.querySelector("#message");
  el.textContent = text;
  el.classList.add("show");
}

function tileOf(px) { return Math.floor(px / TILE); }

function walkable(fromX, fromY, toX, toY) {
  const ta = [tileOf(fromX), tileOf(fromY)];
  const tb = [tileOf(toX), tileOf(toY)];
  if (ta[0] === tb[0] && ta[1] === tb[1]) return true;
  return Terrain.canWalk(ta[0], ta[1], tb[0], tb[1]);
}

function solidPropHit(x, y, radius, chunkList) {
  for (const chunk of chunkList)
    for (const prop of chunk.props) {
      const def = PROP_KINDS[prop.kind];
      if (def.solidRect) {
        const [w, h] = def.solidRect;
        const dx = Math.max(Math.abs(x - prop.x) - w / 2, 0);
        const dy = Math.max(Math.abs(y - (prop.y - h / 2)) - h / 2, 0);
        if (dx * dx + dy * dy < radius * radius) return true;
      } else if (def.solid) {
        const dx = x - prop.x, dy = y - (prop.y - 6);
        const rr = def.solid + radius;
        if (dx * dx + dy * dy < rr * rr) return true;
      }
    }
  return false;
}

function moveActor(actor, dx, dy, chunkList) {
  for (const [mx, my] of [[dx, 0], [0, dy]]) {
    if (!mx && !my) continue;
    const nx = actor.x + mx, ny = actor.y + my;
    if (walkable(actor.x, actor.y, nx, ny) && !solidPropHit(nx, ny, actor.radius, chunkList)) {
      actor.x = nx;
      actor.y = ny;
    }
  }
}

/* --------------------------------- spawning -------------------------------- */

function spawnChunkEntities(chunk) {
  const key = `${chunk.cx},${chunk.cy}`;
  if (spawnedChunks.has(key)) return;
  spawnedChunks.add(key);
  const baseX = chunk.cx * CHUNK_PX, baseY = chunk.cy * CHUNK_PX;

  if (chunk.village) {
    const v = chunk.village;
    const pawnCount = 3 + Math.floor(hash2(chunk.cx, chunk.cy, 41) * 3);
    for (let i = 0; i < pawnCount; i++)
      entities.push(makeUnit("pawn", v.color, v.centerX + (hash2(i, chunk.cx, 42) - 0.5) * v.radius * 1.5,
        v.centerY + (hash2(i, chunk.cy, 43) - 0.5) * v.radius * 1.5, {
          home: v, hp: 20, damage: 6, speed: 70, aggro: 150, kind: "villager",
        }));
    const guardCount = 2 + Math.floor(hash2(chunk.cx, chunk.cy, 44) * 2);
    for (let i = 0; i < guardCount; i++)
      entities.push(makeUnit("warrior", v.color, v.centerX + (hash2(i + 9, chunk.cx, 45) - 0.5) * v.radius * 1.8,
        v.centerY + (hash2(i + 9, chunk.cy, 46) - 0.5) * v.radius * 1.8, {
          home: v, hp: 45, damage: 13, speed: 105, aggro: 210, kind: "guard",
        }));
  }

  // sheep flocks on open grass
  if (hash2(chunk.cx, chunk.cy, 47) < 0.3) {
    const spot = findGrassSpot(chunk);
    if (spot) {
      const count = 2 + Math.floor(hash2(chunk.cx, chunk.cy, 48) * 3);
      for (let i = 0; i < count; i++)
        entities.push({
          kind: "sheep", x: spot[0] + (hash2(i, chunk.cx, 49) - 0.5) * 130,
          y: spot[1] + (hash2(i, chunk.cy, 50) - 0.5) * 130,
          radius: 10, hp: 10, speed: 40, facing: 1,
          state: "idle", targetX: 0, targetY: 0, thinkT: hash2(i, chunk.cx, 51) * 3,
          hurtT: 0, phase: hash2(i, chunk.cy, 52) * 9999,
        });
    }
  }

  // monsters: none near spawn, more (and stronger) further out
  const distTiles = Math.hypot(chunk.cx * CHUNK + 16, chunk.cy * CHUNK + 16);
  const danger = Math.min(1, Math.max(0, (distTiles - 45) / 260));
  if (danger > 0 && !chunk.village) {
    const rolls = Math.floor(danger * 5 * difficulty.monsterRate * hash2(chunk.cx, chunk.cy, 53) * 2);
    for (let i = 0; i < rolls; i++) {
      const spot = findGrassSpot(chunk, 60 + i * 7);
      if (!spot) continue;
      const strong = 1 + danger * 1.6;
      const color = hash2(chunk.cx + i, chunk.cy, 54) < 0.72 ? "black" : "purple";
      entities.push(makeUnit("warrior", color, spot[0], spot[1], {
        home: null, hp: Math.round(30 * strong * difficulty.monsterHp),
        damage: Math.round(9 * strong * difficulty.monsterDamage),
        speed: 95 + danger * 30, aggro: 260, kind: "monster",
      }));
    }
  }
}

function findGrassSpot(chunk, salt = 60) {
  for (let attempt = 0; attempt < 10; attempt++) {
    const c = Math.floor(hash2(chunk.cx * 5 + attempt, chunk.cy, salt) * CHUNK);
    const r = Math.floor(hash2(chunk.cx, chunk.cy * 5 + attempt, salt + 1) * CHUNK);
    if (chunk.level[r * CHUNK + c] === 0)
      return [(chunk.cx * CHUNK + c) * TILE + 32, (chunk.cy * CHUNK + r) * TILE + 32];
  }
  return null;
}

function makeUnit(type, color, x, y, options) {
  return {
    type, color, x, y, radius: 12, facing: 1,
    state: "idle", attackT: 0, hurtT: 0, thinkT: Math.random() * 2,
    targetX: x, targetY: y, homeX: x, homeY: y,
    phase: Math.random() * 9999,
    ...options,
  };
}

/* ---------------------------------- combat --------------------------------- */

function playerAttack(chunkList) {
  if (player.attackT > 0 || player.deadT > 0) return;
  player.attackT = 0.38;
  player.state = "attack";
  const reachX = player.x + player.facing * 34;
  for (const entity of entities) {
    if (entity.hp <= 0) continue;
    const dx = entity.x - reachX, dy = entity.y - player.y;
    if (dx * dx + dy * dy < 55 * 55) {
      entity.hp -= 15;
      entity.hurtT = 0.2;
      if (entity.kind === "villager" || entity.kind === "guard") entity.provoked = true;
      const knock = 30;
      const nx = entity.x + Math.sign(entity.x - player.x || 1) * knock;
      if (walkable(entity.x, entity.y, nx, entity.y)) entity.x = nx;
      if (entity.hp <= 0 && entity.kind === "monster") showMessage("Monster slain");
    }
  }
}

function hurtPlayer(amount) {
  if (player.hurtT > 0 || player.deadT > 0) return;
  player.hp = Math.max(0, player.hp - amount);
  player.hurtT = 0.7;
  if (player.hp <= 0) {
    player.deadT = 2;
    showMessage("You fall... and awaken at your camp", 3);
  }
}

/* --------------------------------- entities -------------------------------- */

function updateEntity(entity, dt, chunkList) {
  if (entity.hp <= 0) { entity.fade = (entity.fade ?? 1) - dt * 2; return; }
  entity.hurtT = Math.max(0, entity.hurtT - dt);
  entity.attackT = Math.max(0, entity.attackT - dt);
  entity.thinkT -= dt;

  if (entity.kind === "sheep") {
    if (entity.thinkT <= 0) {
      entity.thinkT = 2 + Math.random() * 4;
      entity.state = Math.random() < 0.55 ? "idle" : "move";
      const angle = Math.random() * Math.PI * 2;
      entity.targetX = entity.x + Math.cos(angle) * 90;
      entity.targetY = entity.y + Math.sin(angle) * 90;
    }
    if (entity.state === "move") stepToward(entity, entity.targetX, entity.targetY, entity.speed, dt, chunkList);
    return;
  }

  const playerDist = Math.sqrt(dist2(entity, player));
  const anchorX = entity.home ? entity.home.centerX : entity.homeX;
  const anchorY = entity.home ? entity.home.centerY : entity.homeY;
  const anchorRange = entity.home ? entity.home.radius * 2.4 : 480;
  const chasing =
    player.deadT <= 0 &&
    (playerDist < entity.aggro || (entity.provoked && playerDist < entity.aggro * 2.4)) &&
    Math.hypot(player.x - anchorX, player.y - anchorY) < anchorRange + 240;

  if (chasing) {
    if (playerDist > 34) {
      entity.state = "run";
      stepToward(entity, player.x, player.y, entity.speed, dt, chunkList);
    } else if (entity.attackT <= 0) {
      entity.attackT = 0.9;
      entity.swingT = 0.35;
      hurtPlayer(entity.damage);
    }
    if (entity.swingT > 0) { entity.swingT -= dt; entity.state = "attack"; }
    entity.facing = player.x >= entity.x ? 1 : -1;
    return;
  }

  // roam around home
  if (entity.thinkT <= 0) {
    entity.thinkT = 2.5 + Math.random() * 4;
    if (Math.random() < 0.6) {
      const angle = Math.random() * Math.PI * 2;
      const range = entity.home ? entity.home.radius * 1.25 : 170;
      entity.targetX = anchorX + Math.cos(angle) * range * Math.random();
      entity.targetY = anchorY + Math.sin(angle) * range * Math.random();
      entity.state = "run";
    } else {
      entity.state = "idle";
    }
  }
  if (entity.state === "run") {
    if (Math.hypot(entity.targetX - entity.x, entity.targetY - entity.y) < 8) entity.state = "idle";
    else stepToward(entity, entity.targetX, entity.targetY, entity.speed * 0.55, dt, chunkList);
  }
}

function stepToward(entity, tx, ty, speed, dt, chunkList) {
  const angle = Math.atan2(ty - entity.y, tx - entity.x);
  const dx = Math.cos(angle) * speed * dt;
  const dy = Math.sin(angle) * speed * dt;
  const beforeX = entity.x, beforeY = entity.y;
  moveActor(entity, dx, dy, chunkList);
  if (Math.abs(entity.x - beforeX) < Math.abs(dx) * 0.2 && Math.abs(entity.y - beforeY) < Math.abs(dy) * 0.2)
    entity.thinkT = Math.min(entity.thinkT, 0.3); // stuck: rethink soon
  if (dx) entity.facing = Math.sign(dx);
}

/* ---------------------------------- update --------------------------------- */

function update(dt, chunkList) {
  gameTime += dt;

  // --- player movement (velocity smoothing) ---
  const keys = settings.keys;
  let ix = (pressed[keys.right] || pressed.arrowright ? 1 : 0) - (pressed[keys.left] || pressed.arrowleft ? 1 : 0);
  let iy = (pressed[keys.down] || pressed.arrowdown ? 1 : 0) - (pressed[keys.up] || pressed.arrowup ? 1 : 0);
  const mag = Math.hypot(ix, iy) || 1;
  ix /= mag; iy /= mag;
  if (player.deadT > 0 || player.attackT > 0.22) { ix = 0; iy = 0; }

  const accel = 1400, maxSpeed = 215;
  player.vx += (ix * maxSpeed - player.vx) * Math.min(1, dt * accel / maxSpeed);
  player.vy += (iy * maxSpeed - player.vy) * Math.min(1, dt * accel / maxSpeed);
  if (Math.hypot(player.vx, player.vy) > 4) {
    moveActor(player, player.vx * dt, player.vy * dt, chunkList);
    if (ix) player.facing = Math.sign(ix);
  }

  player.attackT = Math.max(0, player.attackT - dt);
  player.hurtT = Math.max(0, player.hurtT - dt);
  if (player.deadT > 0) {
    player.deadT -= dt;
    if (player.deadT <= 0) {
      player.hp = player.maxHp;
      player.x = player.spawnX;
      player.y = player.spawnY;
      player.vx = player.vy = 0;
    }
  }
  player.state = player.attackT > 0 ? "attack" : Math.hypot(player.vx, player.vy) > 20 ? "run" : "idle";

  // camera follows smoothly
  camera.x += (player.x - view.w / 2 - camera.x) * Math.min(1, dt * 5);
  camera.y += (player.y - view.h / 2 - camera.y) * Math.min(1, dt * 5);

  // --- entities near the view ---
  for (let i = entities.length - 1; i >= 0; i--) {
    const entity = entities[i];
    if (entity.fade !== undefined && entity.fade <= 0) { entities.splice(i, 1); continue; }
    if (Math.abs(entity.x - player.x) > 1900 || Math.abs(entity.y - player.y) > 1400) continue;
    updateEntity(entity, dt, chunkList);
  }

  if (message.t > 0 && (message.t -= dt) <= 0)
    document.querySelector("#message").classList.remove("show");

  updateHud();
}

function updateHud() {
  document.querySelector("#health-fill").style.width = `${(player.hp / player.maxHp) * 100}%`;
  document.querySelector("#health-text").textContent = `${Math.ceil(player.hp)}`;
  if (params.has("debug"))
    document.title = `x=${Math.round(player.x)} y=${Math.round(player.y)} hp=${player.hp}`;
  const distTiles = Math.round(Math.hypot(player.x, player.y) / TILE);
  const dangerEl = document.querySelector("#danger");
  const label = distTiles < 45 ? "SAFE MEADOWS" : distTiles < 130 ? "WILD FRONTIER" : distTiles < 250 ? "DARK LANDS" : "THE DEEP DARK";
  if (dangerEl.textContent !== label) dangerEl.textContent = label;
}

/* ---------------------------------- drawing -------------------------------- */

function drawUnit(entity, time) {
  const isPlayer = entity === player;
  const type = isPlayer ? "warrior" : entity.type;
  const color = isPlayer ? "blue" : entity.color;
  const state = entity.state === "attack" && (isPlayer || entity.type === "warrior") ? "attack"
    : entity.state === "run" ? "run" : "idle";
  const sheet = unitImages[`${type}-${color}-${state === "attack" ? "attack" : state === "run" ? "run" : "idle"}`]
    || unitImages[`${type}-${color}-idle`];
  const anim = ANIM[state] || ANIM.idle;
  const frame = Math.floor((time + (entity.phase || 0)) / anim.speed) % anim.frames;

  const x = entity.x - camera.x, y = entity.y - camera.y;
  ctx.save();
  ctx.globalAlpha = (entity.fade ?? 1) * (entity.hurtT > 0 && Math.floor(time / 70) % 2 ? 0.4 : 1);
  // shadow
  ctx.fillStyle = "rgba(23,61,40,.25)";
  ctx.beginPath();
  ctx.ellipse(x, y + 4, 16, 6, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.translate(x, y);
  if (entity.facing < 0) ctx.scale(-1, 1);
  ctx.drawImage(sheet, frame * FRAME, 0, FRAME, FRAME, -56, -86, 112, 112);
  ctx.restore();

  if (!isPlayer && entity.kind !== "sheep" && entity.hp > 0 && entity.maxHpShown !== false) {
    const maxHp = entity.kind === "monster" ? 30 * (1 + 1.6) : entity.kind === "guard" ? 45 : 20;
    const frac = Math.min(1, entity.hp / maxHp);
    if (frac < 1) {
      ctx.fillStyle = "#22282b";
      ctx.fillRect(x - 17, y - 78, 34, 5);
      ctx.fillStyle = entity.kind === "monster" ? "#c33b47" : "#e0a33c";
      ctx.fillRect(x - 16, y - 77, 32 * frac, 3);
    }
  }
}

function drawSheep(entity, time) {
  const sheet = unitImages[entity.state === "move" ? "sheep-move" : "sheep-idle"];
  const frames = entity.state === "move" ? 4 : 6;
  const frame = Math.floor((time + entity.phase) / 150) % frames;
  const x = entity.x - camera.x, y = entity.y - camera.y;
  ctx.save();
  ctx.globalAlpha = entity.fade ?? 1;
  ctx.fillStyle = "rgba(23,61,40,.25)";
  ctx.beginPath();
  ctx.ellipse(x, y + 3, 13, 5, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.translate(x, y);
  if (entity.facing < 0) ctx.scale(-1, 1);
  ctx.drawImage(sheet, frame * 128, 0, 128, 128, -40, -62, 80, 80);
  ctx.restore();
}

function draw(time, chunkList) {
  Terrain.drawView(ctx, Math.round(camera.x), Math.round(camera.y), view.w, view.h, time);

  // collect visible drawables: props + entities + player, sort by baseline
  const drawables = [];
  const margin = 220;
  for (const chunk of chunkList)
    for (const prop of chunk.props) {
      if (prop.x < camera.x - margin || prop.x > camera.x + view.w + margin ||
          prop.y < camera.y - margin || prop.y > camera.y + view.h + margin) continue;
      drawables.push(prop);
    }
  for (const entity of entities) {
    if (entity.x < camera.x - margin || entity.x > camera.x + view.w + margin ||
        entity.y < camera.y - margin || entity.y > camera.y + view.h + margin) continue;
    drawables.push(entity);
  }
  drawables.push(player);
  drawables.sort((a, b) => a.y - b.y);

  for (const item of drawables) {
    if (item === player || item.type) drawUnit(item, time);
    else if (item.kind === "sheep") drawSheep(item, time);
    else Terrain.drawProp(ctx, item, camera.x, camera.y, time);
  }
}

/* --------------------------------- main loop ------------------------------- */

let lastTime = 0;
function frame(time) {
  const dt = Math.min((time - lastTime) / 1000 || 0, 0.05);
  lastTime = time;
  const chunkList = Terrain.visibleChunks(camera.x - 300, camera.y - 300, view.w + 600, view.h + 600);
  for (const chunk of chunkList) spawnChunkEntities(chunk);
  if (!paused) update(dt, chunkList);
  draw(time, chunkList);
  requestAnimationFrame(frame);
}

/* ---------------------------------- saving --------------------------------- */

function saveGame() {
  Saves.write(slot, {
    seed: Terrain.seed,
    x: Math.round(player.x), y: Math.round(player.y),
    hp: Math.round(player.hp),
    spawnX: player.spawnX, spawnY: player.spawnY,
  });
}

setInterval(() => { if (!paused && player.deadT <= 0) saveGame(); }, 8000);
addEventListener("beforeunload", saveGame);

/* --------------------------------- pause menu ------------------------------ */

function setPaused(value) {
  paused = value;
  document.querySelector("#pause").classList.toggle("hidden", !paused);
  if (paused) saveGame();
}
document.querySelector("#resume").addEventListener("click", () => setPaused(false));
document.querySelector("#save-quit").addEventListener("click", () => {
  saveGame();
  location.href = "menu.html";
});

/* ---------------------------------- input ---------------------------------- */

addEventListener("keydown", (event) => {
  const key = event.key.toLowerCase();
  pressed[key] = true;
  if (event.key.startsWith("Arrow") || key === " ") event.preventDefault();
  if (key === settings.keys.attack) {
    const chunkList = Terrain.visibleChunks(camera.x, camera.y, view.w, view.h);
    if (!paused) playerAttack(chunkList);
  }
  if (key === settings.keys.menu) setPaused(!paused);
});
addEventListener("keyup", (event) => { pressed[event.key.toLowerCase()] = false; });

function resize() {
  const dpr = devicePixelRatio >= 2 ? 2 : 1;
  view = { w: innerWidth, h: innerHeight };
  canvas.width = view.w * dpr;
  canvas.height = view.h * dpr;
  canvas.style.width = `${view.w}px`;
  canvas.style.height = `${view.h}px`;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.imageSmoothingEnabled = false;
}
addEventListener("resize", resize);

/* ----------------------------------- boot ---------------------------------- */

function findSpawn() {
  // walk outward until we find open grass
  for (let radius = 0; radius < 60; radius++)
    for (let attempt = 0; attempt < 14; attempt++) {
      const angle = (attempt / 14) * Math.PI * 2;
      const tx = Math.round(Math.cos(angle) * radius * 2);
      const ty = Math.round(Math.sin(angle) * radius * 2);
      if (Terrain.levelAt(tx, ty) === 0)
        return [tx * TILE + 32, ty * TILE + 32];
    }
  return [32, 32];
}

(async function boot() {
  const save = Saves.read(slot);
  const isNew = params.get("new") === "1" || !save;
  const seed = isNew
    ? (params.get("seed") ? Number(params.get("seed")) >>> 0 : (Math.random() * 1e9) >>> 0)
    : save.seed;

  await Terrain.load(seed);
  unitImages = await loadImages(UNIT_FILES);

  if (isNew) {
    const [sx, sy] = findSpawn();
    player.x = player.spawnX = sx;
    player.y = player.spawnY = sy;
    player.hp = player.maxHp;
    saveGame();
    showMessage("A new adventure begins", 3);
  } else {
    player.x = save.x; player.y = save.y;
    player.hp = save.hp || player.maxHp;
    player.spawnX = save.spawnX ?? save.x;
    player.spawnY = save.spawnY ?? save.y;
    showMessage("Welcome back, adventurer", 3);
  }
  if (params.has("px")) { player.x = Number(params.get("px")); player.y = Number(params.get("py")); }
  if (params.has("find")) {
    const want = params.get("find");
    outer:
    for (let radius = 0; radius < 14; radius++)
      for (let cy = -radius; cy <= radius; cy++)
        for (let cx = -radius; cx <= radius; cx++) {
          if (Math.max(Math.abs(cx), Math.abs(cy)) !== radius) continue;
          const chunk = Terrain.chunk(cx, cy);
          if (want === "village" && chunk.village) {
            player.x = chunk.village.centerX + 100;
            player.y = chunk.village.centerY + 180;
            break outer;
          }
          if (want === "ramp" && chunk.ramp.some((v) => v)) {
            const index = chunk.ramp.findIndex((v) => v);
            player.x = (cx * CHUNK + (index % CHUNK)) * TILE + 32;
            player.y = (cy * CHUNK + Math.floor(index / CHUNK)) * TILE + 96;
            break outer;
          }
        }
  }
  camera.x = player.x - view.w / 2;
  camera.y = player.y - view.h / 2;

  document.querySelector("#loading").classList.add("hidden");
  resize();
  if (params.has("auto")) {
    const [key, ms] = params.get("auto").split(":");
    pressed[key] = true;
    setTimeout(() => { pressed[key] = false; }, Number(ms) || 3000);
  }
  requestAnimationFrame(frame);
})();
