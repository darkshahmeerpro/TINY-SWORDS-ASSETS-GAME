// Tiny Swords — infinite procedural terrain, chunk by chunk.
//
// The world is a pure function of (seed, tile position), so any chunk can be
// generated independently. Each chunk is computed with a wide apron of extra
// tiles around it; every cleanup pass only propagates a few tiles, so
// neighboring chunks always agree where they meet.

const TILE = 64;
const CHUNK = 32;                 // tiles per chunk side
const APRON = 16;                 // extra tiles computed around each chunk
const G = CHUNK + APRON * 2;      // full working grid side
const CHUNK_PX = CHUNK * TILE;

const SEA = 0.42;                 // continent noise below this is ocean
const LAKE_T = 0.60;              // lake-carving noise threshold
const HILL1 = 0.585;              // first elevation level
const HILL2 = 0.65;               // second elevation level

const TERRAIN_FILES = {
  grass: "assets/terrain/tilemap1.png",     // base yellow-green
  biome: "assets/terrain/tilemap5.png",     // large cold teal biome
  olive: "assets/terrain/tilemap4.png",     // small dry patches
  plateau1: "assets/terrain/tilemap2.png",  // green hills
  plateau2: "assets/terrain/tilemap3.png",  // dark green summits
  water: "assets/terrain/water.png",
  foam: "assets/terrain/foam.png",
  shadow: "assets/terrain/shadow.png",
};

// index = N + 2*E + 4*S + 8*W (bit set when the neighbor is the same terrain)
const FLAT_TILE = [
  [3, 3], [3, 2], [0, 3], [0, 2],
  [3, 0], [3, 1], [0, 0], [0, 1],
  [2, 3], [2, 2], [1, 3], [1, 2],
  [2, 0], [2, 1], [1, 0], [1, 1],
];

// Animated / static decoration sprite definitions.
const PROP_KINDS = {
  tree1: { src: "assets/decor/tree1.png", frame: 256, frames: 6, w: 168, speed: 140, solid: 11, baseInset: 24 },
  tree2: { src: "assets/decor/tree2.png", frame: 256, frames: 6, w: 168, speed: 150, solid: 11, baseInset: 24 },
  tree3: { src: "assets/decor/tree3.png", frame: 192, frames: 8, w: 138, speed: 130, solid: 10, baseInset: 20 },
  tree4: { src: "assets/decor/tree4.png", frame: 192, frames: 8, w: 138, speed: 145, solid: 10, baseInset: 20 },
  bush1: { src: "assets/decor/bush1.png", frame: 128, frames: 8, w: 84, speed: 170 },
  bush2: { src: "assets/decor/bush2.png", frame: 128, frames: 8, w: 84, speed: 180 },
  bush3: { src: "assets/decor/bush3.png", frame: 128, frames: 8, w: 84, speed: 175 },
  bush4: { src: "assets/decor/bush4.png", frame: 128, frames: 8, w: 84, speed: 165 },
  rock1: { src: "assets/decor/rock1.png", frame: 64, frames: 1, w: 56 },
  rock2: { src: "assets/decor/rock2.png", frame: 64, frames: 1, w: 56 },
  rock3: { src: "assets/decor/rock3.png", frame: 64, frames: 1, w: 56 },
  rock4: { src: "assets/decor/rock4.png", frame: 64, frames: 1, w: 56 },
  gold1: { src: "assets/decor/goldstone1.png", frame: 128, frames: 1, w: 88, solid: 14 },
  gold2: { src: "assets/decor/goldstone2.png", frame: 128, frames: 1, w: 88, solid: 14 },
  gold3: { src: "assets/decor/goldstone3.png", frame: 128, frames: 1, w: 88, solid: 14 },
  waterrock1: { src: "assets/decor/waterrock1.png", frame: 64, frames: 16, w: 64, speed: 160 },
  waterrock2: { src: "assets/decor/waterrock2.png", frame: 64, frames: 16, w: 64, speed: 170 },
  waterrock3: { src: "assets/decor/waterrock3.png", frame: 64, frames: 16, w: 64, speed: 150 },
  waterrock4: { src: "assets/decor/waterrock4.png", frame: 64, frames: 16, w: 64, speed: 165 },
  duck: { src: "assets/decor/duck.png", frame: 32, frames: 3, w: 42, speed: 260 },
  house1: { src: "assets/buildings/house1-COLOR.png", frame: 128, frames: 1, w: 128, solidRect: [88, 34], baseInset: 10 },
  house2: { src: "assets/buildings/house2-COLOR.png", frame: 128, frames: 1, w: 128, solidRect: [88, 34], baseInset: 10 },
  house3: { src: "assets/buildings/house3-COLOR.png", frame: 128, frames: 1, w: 128, solidRect: [88, 34], baseInset: 10 },
  tower: { src: "assets/buildings/tower-COLOR.png", frame: 128, frames: 1, w: 118, solidRect: [76, 30], baseInset: 8 },
};

const VILLAGE_COLORS = ["blue", "red", "yellow", "purple", "black"];

const Terrain = {
  seed: 1,
  images: null,
  propImages: {},
  chunks: new Map(),
  waterPattern: null,

  async load(seed) {
    this.seed = seed >>> 0;
    this.images = await loadImages(TERRAIN_FILES);
    const propFiles = {};
    for (const [kind, def] of Object.entries(PROP_KINDS)) {
      if (def.src.includes("COLOR")) {
        for (const color of VILLAGE_COLORS)
          propFiles[`${kind}-${color}`] = def.src.replace("COLOR", color);
      } else {
        propFiles[kind] = def.src;
      }
    }
    this.propImages = await loadImages(propFiles);
  },

  setSeed(seed) {
    this.seed = seed >>> 0;
    this.chunks.clear();
  },
};

/* ---------------------------------- noise ---------------------------------- */

function hash2(x, y, salt) {
  let n = (x * 374761393 + y * 668265263 + (Terrain.seed + salt) * 69069) | 0;
  n = Math.imul(n ^ (n >>> 13), 1274126177);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967295;
}

function smoothstep(t) { return t * t * (3 - 2 * t); }

function valueNoise(x, y, salt) {
  const xi = Math.floor(x), yi = Math.floor(y);
  const tx = smoothstep(x - xi), ty = smoothstep(y - yi);
  const a = hash2(xi, yi, salt), b = hash2(xi + 1, yi, salt);
  const c = hash2(xi, yi + 1, salt), d = hash2(xi + 1, yi + 1, salt);
  return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty;
}

function fbm(x, y, salt) {
  let value = 0, amplitude = 0.5, frequency = 1, total = 0;
  for (let octave = 0; octave < 5; octave++) {
    value += valueNoise(x * frequency, y * frequency, salt + octave * 101) * amplitude;
    total += amplitude;
    amplitude *= 0.55;
    frequency *= 2;
  }
  return value / total;
}

// One domain warp shared by every terrain channel.
function warp(x, y) {
  const wx = (fbm(x * 0.045, y * 0.045, 900) - 0.5) * 42;
  const wy = (fbm(x * 0.045, y * 0.045, 1700) - 0.5) * 42;
  return [x + wx, y + wy];
}

/* ------------------------- mask utilities (G x G grid) --------------------- */

const idx = (c, r) => r * G + c;
const inGrid = (c, r) => c >= 0 && r >= 0 && c < G && r < G;
const at = (mask, c, r) => (inGrid(c, r) ? mask[idx(c, r)] : 0);

function neighborMask(mask, c, r) {
  return (at(mask, c, r - 1) ? 1 : 0) | (at(mask, c + 1, r) ? 2 : 0) |
         (at(mask, c, r + 1) ? 4 : 0) | (at(mask, c - 1, r) ? 8 : 0);
}

function count8(mask, c, r) {
  let total = 0;
  for (let dy = -1; dy <= 1; dy++)
    for (let dx = -1; dx <= 1; dx++)
      if (dx || dy) total += at(mask, c + dx, r + dy);
  return total;
}

function smoothMask(mask, iterations) {
  let current = mask;
  for (let i = 0; i < iterations; i++) {
    const next = new Uint8Array(G * G);
    for (let r = 0; r < G; r++)
      for (let c = 0; c < G; c++) {
        const around = count8(current, c, r) + current[idx(c, r)];
        next[idx(c, r)] = around >= 5 ? 1 : 0;
      }
    current = next;
  }
  return current;
}

// Fill one-tile notches and shave one-tile spurs so autotiled edges stay chunky.
function regularize(mask, allowed, iterations) {
  for (let i = 0; i < iterations; i++) {
    for (let r = 0; r < G; r++)
      for (let c = 0; c < G; c++) {
        const cardinals = (at(mask, c, r - 1) ? 1 : 0) + (at(mask, c + 1, r) ? 1 : 0) +
                          (at(mask, c, r + 1) ? 1 : 0) + (at(mask, c - 1, r) ? 1 : 0);
        if (!mask[idx(c, r)] && cardinals >= 3 && (!allowed || allowed[idx(c, r)]))
          mask[idx(c, r)] = 1;
        else if (mask[idx(c, r)] && cardinals <= 1) mask[idx(c, r)] = 0;
      }
  }
}

// The tileset has no tiles for diagonal-only contact, so break checkerboards.
function fixCheckerboards(mask, allowed) {
  for (let r = 0; r < G - 1; r++)
    for (let c = 0; c < G - 1; c++) {
      const a = mask[idx(c, r)], b = mask[idx(c + 1, r)];
      const d = mask[idx(c, r + 1)], e = mask[idx(c + 1, r + 1)];
      if (a && e && !b && !d) {
        if (!allowed || allowed[idx(c + 1, r)]) mask[idx(c + 1, r)] = 1;
        else mask[idx(c, r)] = 0;
      } else if (b && d && !a && !e) {
        if (!allowed || allowed[idx(c, r)]) mask[idx(c, r)] = 1;
        else mask[idx(c + 1, r)] = 0;
      }
    }
}

function erode(mask) {
  const out = new Uint8Array(G * G);
  for (let r = 0; r < G; r++)
    for (let c = 0; c < G; c++)
      out[idx(c, r)] = mask[idx(c, r)] && count8(mask, c, r) === 8 ? 1 : 0;
  return out;
}

// Plateaus have no 1-tile-high horizontal pieces in the tileset: peel those off.
function removeThinRows(mask) {
  for (let i = 0; i < 4; i++) {
    let changed = false;
    for (let r = 0; r < G; r++)
      for (let c = 0; c < G; c++)
        if (mask[idx(c, r)] && !at(mask, c, r - 1) && !at(mask, c, r + 1)) {
          mask[idx(c, r)] = 0;
          changed = true;
        }
    if (!changed) break;
  }
}

function overlayMask(land, warped, frequency, threshold, salt) {
  const mask = new Uint8Array(G * G);
  for (let i = 0; i < mask.length; i++)
    mask[i] =
      land[i] && fbm(warped[i * 2] * frequency, warped[i * 2 + 1] * frequency, salt) > threshold ? 1 : 0;
  regularize(mask, land, 2);
  for (let i = 0; i < mask.length; i++) mask[i] = mask[i] && land[i] ? 1 : 0;
  fixCheckerboards(mask, land);
  return mask;
}

function plateauMask(heights, allowed, threshold) {
  let mask = new Uint8Array(G * G);
  for (let i = 0; i < mask.length; i++)
    mask[i] = allowed[i] && heights[i] > threshold ? 1 : 0;
  mask = smoothMask(mask, 1);
  for (let i = 0; i < mask.length; i++) mask[i] = mask[i] && allowed[i] ? 1 : 0;
  regularize(mask, allowed, 2);
  fixCheckerboards(mask, allowed);
  removeThinRows(mask);
  return mask;
}

// Scattered lone tiles just outside an overlay's border blend the two biomes.
function sprinkleCells(mask, land, gx0, gy0, salt) {
  const cells = [];
  for (let r = 1; r < G - 1; r++)
    for (let c = 1; c < G - 1; c++) {
      if (mask[idx(c, r)] || !land[idx(c, r)]) continue;
      let near = 0;
      for (let dy = -2; dy <= 2; dy++)
        for (let dx = -2; dx <= 2; dx++)
          if (at(mask, c + dx, r + dy)) near = 1;
      if (!near) continue;
      // Skip cells cardinal-adjacent to the mask so we never touch its autotile edge.
      if (neighborMask(mask, c, r)) continue;
      if (hash2(gx0 + c, gy0 + r, salt) < 0.3) cells.push(idx(c, r));
    }
  return cells;
}

/* ---------------------------- ramp (stairs) finding ------------------------- */

// A ramp is a 2-wide grassy opening in a south cliff edge, built from the
// tileset's wedge tiles. Placement is a pure function of global position.
function findRamps(mask, gx0, gy0, salt) {
  const ramps = new Uint8Array(G * G); // 1 = left ramp column, 2 = right
  const southEdge = (c, r) => at(mask, c, r) && !at(mask, c, r + 1) && at(mask, c, r - 1);
  for (let r = 1; r < G - 2; r++)
    for (let c = 1; c < G - 2; c++) {
      if (!southEdge(c, r) || !southEdge(c + 1, r)) continue;
      const here = hash2(gx0 + c, gy0 + r, salt) < 0.3;
      const left = southEdge(c - 1, r) && hash2(gx0 + c - 1, gy0 + r, salt) < 0.3;
      if (here && !left && !at(ramps, c - 1, r) && !at(ramps, c, r)) {
        ramps[idx(c, r)] = 1;
        ramps[idx(c + 1, r)] = 2;
      }
    }
  return ramps;
}

/* ------------------------------ chunk generation --------------------------- */

function buildChunk(cx, cy) {
  const gx0 = cx * CHUNK - APRON;
  const gy0 = cy * CHUNK - APRON;
  const images = Terrain.images;

  const heights = new Float32Array(G * G);
  const warped = new Float32Array(G * G * 2);
  let land = new Uint8Array(G * G);
  for (let r = 0; r < G; r++)
    for (let c = 0; c < G; c++) {
      const [wx, wy] = warp(gx0 + c, gy0 + r);
      warped[idx(c, r) * 2] = wx;
      warped[idx(c, r) * 2 + 1] = wy;
      const continent = fbm(wx * 0.016, wy * 0.016, 0);
      const relief = fbm(wx * 0.07, wy * 0.07, 300);
      const lake = fbm(wx * 0.045, wy * 0.045, 4400);
      heights[idx(c, r)] = relief * 0.85 + continent * 0.15;
      land[idx(c, r)] = continent > SEA && lake < LAKE_T ? 1 : 0;
    }

  land = smoothMask(land, 1);
  regularize(land, null, 2);
  fixCheckerboards(land, null);

  const plate1 = plateauMask(heights, erode(erode(land)), HILL1);
  const plate2 = plateauMask(heights, erode(plate1), HILL2);
  const biome = overlayMask(land, warped, 0.014, 0.56, 7100);
  const olive = overlayMask(land, warped, 0.06, 0.585, 4200);
  const biomeDots = sprinkleCells(biome, land, gx0, gy0, 8300);
  const oliveDots = sprinkleCells(olive, land, gx0, gy0, 8400);
  const ramps1 = findRamps(plate1, gx0, gy0, 5100);
  const ramps2 = findRamps(plate2, gx0, gy0, 5200);

  // ---- passability levels for the whole working grid ----
  // 0/1/2 walkable elevation, -1 water, -2 cliff wall (solid)
  const levels = new Int8Array(G * G).fill(-1);
  for (let i = 0; i < G * G; i++) {
    if (land[i]) levels[i] = 0;
    if (plate1[i]) levels[i] = 1;
    if (plate2[i]) levels[i] = 2;
  }
  const rampFlag = new Uint8Array(G * G);
  for (const [mask, ramps] of [[plate1, ramps1], [plate2, ramps2]])
    for (let r = 0; r < G - 1; r++)
      for (let c = 0; c < G; c++) {
        if (!mask[idx(c, r)] || at(mask, c, r + 1)) continue;
        if (ramps[idx(c, r)]) {
          rampFlag[idx(c, r)] = 1;
          rampFlag[idx(c, r + 1)] = 1;
        } else if (levels[idx(c, r + 1)] >= -1) {
          levels[idx(c, r + 1)] = -2; // wall
        }
      }

  const village = findVillage(cx, cy, levels, gx0, gy0);
  const props = placeProps(levels, land, plate1, plate2, biome, village, gx0, gy0);
  if (village) {
    for (const house of village.houses) props.push(house);
    props.sort((a, b) => a.y - b.y);
    // village tiles are flattened walkable already (level 0 by construction)
  }

  // ---- bake terrain canvas ----
  const layerCanvas = document.createElement("canvas");
  layerCanvas.width = CHUNK_PX;
  layerCanvas.height = CHUNK_PX;
  const layer = layerCanvas.getContext("2d");
  layer.imageSmoothingEnabled = false;
  layer.translate(-APRON * TILE, -APRON * TILE);

  for (let r = 0; r < G; r++)
    for (let c = 0; c < G; c++)
      if (land[idx(c, r)]) drawFlatTile(layer, images.grass, land, c, r);
  for (let r = 0; r < G; r++)
    for (let c = 0; c < G; c++)
      if (biome[idx(c, r)]) drawFlatTile(layer, images.biome, biome, c, r);
  for (const cell of biomeDots)
    layer.drawImage(images.biome, 3 * TILE, 3 * TILE, TILE, TILE, (cell % G) * TILE, Math.floor(cell / G) * TILE, TILE, TILE);
  for (let r = 0; r < G; r++)
    for (let c = 0; c < G; c++)
      if (olive[idx(c, r)] && !biome[idx(c, r)]) drawFlatTile(layer, images.olive, olive, c, r);
  for (const cell of oliveDots)
    if (!biome[cell])
      layer.drawImage(images.olive, 3 * TILE, 3 * TILE, TILE, TILE, (cell % G) * TILE, Math.floor(cell / G) * TILE, TILE, TILE);

  drawPlateauLevel(layer, images.plateau1, plate1, ramps1);
  drawPlateauLevel(layer, images.plateau2, plate2, ramps2);

  // ---- interior slices ----
  const level = new Int8Array(CHUNK * CHUNK);
  const ramp = new Uint8Array(CHUNK * CHUNK);
  for (let r = 0; r < CHUNK; r++)
    for (let c = 0; c < CHUNK; c++) {
      level[r * CHUNK + c] = levels[idx(c + APRON, r + APRON)];
      ramp[r * CHUNK + c] = rampFlag[idx(c + APRON, r + APRON)];
    }

  const coast = [];
  for (let r = APRON; r < APRON + CHUNK; r++)
    for (let c = APRON; c < APRON + CHUNK; c++)
      if (land[idx(c, r)] && count8(land, c, r) < 8) coast.push([gx0 + c, gy0 + r]);

  return { canvas: layerCanvas, coast, level, ramp, props, village, cx, cy };
}

/* ------------------------------ villages ----------------------------------- */

function findVillage(cx, cy, levels, gx0, gy0) {
  if (hash2(cx, cy, 9001) > 0.3) return null;
  const SIZE = 13; // tiles
  for (let attempt = 0; attempt < 6; attempt++) {
    const c0 = APRON + 2 + Math.floor(hash2(cx * 7 + attempt, cy * 13, 9100 + attempt) * (CHUNK - SIZE - 4));
    const r0 = APRON + 2 + Math.floor(hash2(cx * 3, cy * 11 + attempt, 9200 + attempt) * (CHUNK - SIZE - 4));
    let flat = true;
    for (let r = r0; r < r0 + SIZE && flat; r++)
      for (let c = c0; c < c0 + SIZE && flat; c++)
        if (levels[idx(c, r)] !== 0) flat = false;
    if (!flat) continue;

    const color = VILLAGE_COLORS[Math.floor(hash2(cx, cy, 9300) * VILLAGE_COLORS.length)];
    const centerX = (gx0 + c0 + SIZE / 2) * TILE;
    const centerY = (gy0 + r0 + SIZE / 2) * TILE;
    const houses = [];
    houses.push(makeBuilding("tower", color, centerX, centerY + 20));
    const count = 4 + Math.floor(hash2(cx, cy, 9400) * 3);
    for (let i = 0; i < count; i++) {
      const angle = (i / count) * Math.PI * 2 + hash2(cx + i, cy, 9500) * 0.5;
      const dist = (3.4 + hash2(cx, cy + i, 9600) * 1.4) * TILE;
      const variant = `house${1 + Math.floor(hash2(cx + i, cy + i, 9700) * 3)}`;
      houses.push(makeBuilding(variant, color, centerX + Math.cos(angle) * dist, centerY + Math.sin(angle) * dist * 0.82));
    }
    return {
      color, centerX, centerY,
      radius: (SIZE / 2) * TILE,
      bounds: [gx0 + c0, gy0 + r0, SIZE],
      houses,
    };
  }
  return null;
}

function makeBuilding(kind, color, x, y) {
  const def = PROP_KINDS[kind];
  return {
    kind, imageKey: `${kind}-${color}`, x: Math.round(x), y: Math.round(y),
    solidRect: def.solidRect, phase: 0,
  };
}

/* ------------------------------ decorations -------------------------------- */

function placeProps(levels, land, plate1, plate2, biome, village, gx0, gy0) {
  const props = [];
  for (let r = APRON; r < APRON + CHUNK; r++)
    for (let c = APRON; c < APRON + CHUNK; c++) {
      const gx = gx0 + c, gy = gy0 + r;
      const level = levels[idx(c, r)];
      const roll = hash2(gx, gy, 6000);
      const jx = (hash2(gx, gy, 6001) - 0.5) * TILE * 0.8;
      const jy = (hash2(gx, gy, 6002) - 0.5) * TILE * 0.8;
      const px = gx * TILE + TILE / 2 + jx;
      const py = gy * TILE + TILE / 2 + jy;

      if (village) {
        const [vc, vr, size] = village.bounds;
        if (gx >= vc - 2 && gx < vc + size + 2 && gy >= vr - 2 && gy < vr + size + 2) continue;
      }

      if (level === -1) { // deep water decorations, away from the coast
        if (count8(land, c, r) === 0) {
          if (roll < 0.011) props.push(makeProp(`waterrock${1 + (gx & 3)}`, px, py, gx, gy));
          else if (roll > 0.9992) props.push(makeProp("duck", px, py, gx, gy));
        }
        continue;
      }
      if (level < 0) continue;

      // no props on cliff-edge tiles so walls and ramps stay readable
      const mask = level === 2 ? plate2 : level === 1 ? plate1 : land;
      if (count8(mask, c, r) < 8) continue;

      const inBiome = biome[idx(c, r)];
      const treeChance = inBiome ? 0.16 : 0.05;
      if (roll < treeChance) {
        const variant = inBiome ? 1 + (hash2(gx, gy, 6003) < 0.7 ? 0 : 1) : 3 + (gx & 1);
        props.push(makeProp(`tree${variant}`, px, py, gx, gy));
      } else if (roll < treeChance + 0.02) {
        props.push(makeProp(`bush${1 + ((gx + gy) & 3)}`, px, py, gx, gy));
      } else if (roll < treeChance + 0.032) {
        props.push(makeProp(`rock${1 + ((gx * 7 + gy) & 3)}`, px, py, gx, gy));
      } else if (level >= 1 && roll < treeChance + 0.047) {
        props.push(makeProp(`gold${1 + ((gx + gy * 3) % 3)}`, px, py, gx, gy));
      }
    }
  props.sort((a, b) => a.y - b.y);
  return props;
}

function makeProp(kind, x, y, gx, gy) {
  return { kind, imageKey: kind, x: Math.round(x), y: Math.round(y), phase: hash2(gx, gy, 6500) * 10000 };
}

/* --------------------------------- drawing --------------------------------- */

function drawFlatTile(layer, image, mask, c, r) {
  const [tc, tr] = FLAT_TILE[neighborMask(mask, c, r)];
  layer.drawImage(image, tc * TILE, tr * TILE, TILE, TILE, c * TILE, r * TILE, TILE, TILE);
}

function plateauColumn(mask, c, r) {
  const west = at(mask, c - 1, r), east = at(mask, c + 1, r);
  return west && east ? 6 : west ? 7 : east ? 5 : 8;
}

function drawPlateauTile(layer, image, mask, c, r) {
  const north = at(mask, c, r - 1), south = at(mask, c, r + 1);
  let row;
  if (!north && !south) row = 3;
  else if (!north) row = 0;
  else if (!south) row = 2;
  else row = 1;
  layer.drawImage(image, plateauColumn(mask, c, r) * TILE, row * TILE, TILE, TILE, c * TILE, r * TILE, TILE, TILE);
}

function drawPlateauLevel(layer, image, mask, ramps) {
  const images = Terrain.images;
  layer.save();
  layer.globalAlpha = 0.6;
  for (let r = 0; r < G; r++)
    for (let c = 0; c < G; c++)
      if (mask[idx(c, r)] && !at(mask, c, r + 1))
        layer.drawImage(images.shadow, c * TILE - TILE, r * TILE - TILE / 2, 192, 192);
  layer.restore();

  for (let r = 0; r < G; r++)
    for (let c = 0; c < G; c++)
      if (mask[idx(c, r)] && !at(mask, c, r + 1) && !ramps[idx(c, r)])
        layer.drawImage(image, plateauColumn(mask, c, r) * TILE, 5 * TILE, TILE, TILE,
          c * TILE, (r + 1) * TILE, TILE, TILE);

  for (let r = 0; r < G; r++)
    for (let c = 0; c < G; c++)
      if (mask[idx(c, r)] && !ramps[idx(c, r)]) drawPlateauTile(layer, image, mask, c, r);

  // ramps: full grass on the edge tile, wedges spilling over the cliff below
  for (let r = 0; r < G; r++)
    for (let c = 0; c < G; c++) {
      const side = ramps[idx(c, r)];
      if (!side) continue;
      layer.drawImage(image, 6 * TILE, 1 * TILE, TILE, TILE, c * TILE, r * TILE, TILE, TILE);
      const wedgeCol = side === 1 ? 0 : 3;
      layer.drawImage(image, wedgeCol * TILE, 4 * TILE, TILE, TILE, c * TILE, r * TILE, TILE, TILE);
      layer.drawImage(image, wedgeCol * TILE, 5 * TILE, TILE, TILE, c * TILE, (r + 1) * TILE, TILE, TILE);
    }
}

/* --------------------------------- queries --------------------------------- */

Terrain.chunk = function (cx, cy) {
  const key = `${cx},${cy}`;
  let chunk = this.chunks.get(key);
  if (!chunk) {
    chunk = buildChunk(cx, cy);
    this.chunks.set(key, chunk);
    if (this.chunks.size > 100) this.chunks.delete(this.chunks.keys().next().value);
  }
  return chunk;
};

Terrain.levelAt = function (tx, ty) {
  const cx = Math.floor(tx / CHUNK), cy = Math.floor(ty / CHUNK);
  const chunk = this.chunk(cx, cy);
  return chunk.level[(ty - cy * CHUNK) * CHUNK + (tx - cx * CHUNK)];
};

Terrain.rampAt = function (tx, ty) {
  const cx = Math.floor(tx / CHUNK), cy = Math.floor(ty / CHUNK);
  const chunk = this.chunk(cx, cy);
  return chunk.ramp[(ty - cy * CHUNK) * CHUNK + (tx - cx * CHUNK)];
};

// Can something walk from tile a to adjacent tile b?
Terrain.canWalk = function (ax, ay, bx, by) {
  const la = this.levelAt(ax, ay), lb = this.levelAt(bx, by);
  if (lb < 0) return false;
  if (la === lb) return true;
  if (Math.abs(la - lb) === 1) return this.rampAt(ax, ay) || this.rampAt(bx, by);
  return false;
};

Terrain.visibleChunks = function (camX, camY, viewW, viewH) {
  const cx0 = Math.floor(camX / CHUNK_PX), cy0 = Math.floor(camY / CHUNK_PX);
  const cx1 = Math.floor((camX + viewW) / CHUNK_PX);
  const cy1 = Math.floor((camY + viewH) / CHUNK_PX);
  const list = [];
  for (let cy = cy0; cy <= cy1; cy++)
    for (let cx = cx0; cx <= cx1; cx++) list.push(this.chunk(cx, cy));
  return list;
};

// Draws water, foam and terrain. Props/entities are drawn by the caller.
Terrain.drawView = function (ctx, camX, camY, viewW, viewH, time) {
  if (!this.waterPattern) this.waterPattern = ctx.createPattern(this.images.water, "repeat");
  ctx.save();
  ctx.translate(-((camX % TILE) + TILE) % TILE, -((camY % TILE) + TILE) % TILE);
  ctx.fillStyle = this.waterPattern;
  ctx.fillRect(0, 0, viewW + TILE, viewH + TILE);
  ctx.restore();

  const visible = this.visibleChunks(camX, camY, viewW, viewH);
  const foamFrames = this.images.foam.width / 192;
  const foamFrame = Math.floor(time / 110) % foamFrames;
  for (const chunk of visible)
    for (const [gx, gy] of chunk.coast) {
      const x = gx * TILE - TILE - camX, y = gy * TILE - TILE - camY;
      if (x > -192 && y > -192 && x < viewW && y < viewH)
        ctx.drawImage(this.images.foam, foamFrame * 192, 0, 192, 192, x, y, 192, 192);
    }
  for (const chunk of visible)
    ctx.drawImage(chunk.canvas, chunk.cx * CHUNK_PX - camX, chunk.cy * CHUNK_PX - camY);
  return visible;
};

Terrain.drawProp = function (ctx, prop, camX, camY, time) {
  const def = PROP_KINDS[prop.kind];
  const image = this.propImages[prop.imageKey];
  const frames = def.frames || 1;
  const frame = frames > 1 ? Math.floor((time + prop.phase) / def.speed) % frames : 0;
  const frameH = image.height;
  const drawW = def.w;
  const drawH = frameH * (drawW / def.frame);
  ctx.drawImage(image, frame * def.frame, 0, def.frame, frameH,
    prop.x - camX - drawW / 2, prop.y - camY - drawH + (def.baseInset || 6), drawW, drawH);
};
