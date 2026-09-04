// 生成应用图标 PNG（纯 Node，无第三方依赖）
// 用法: node gen_icons.js <输出目录>
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    }
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([len, typeBuf, data, crcBuf]);
}

// rgba: Uint8Array length w*h*4
function encodePng(w, h, rgba) {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;  // bit depth
  ihdr[9] = 6;  // color type RGBA
  const raw = Buffer.alloc(h * (1 + w * 4));
  for (let y = 0; y < h; y++) {
    raw[y * (1 + w * 4)] = 0; // filter none
    for (let x = 0; x < w; x++) {
      const src = (y * w + x) * 4;
      const dst = y * (1 + w * 4) + 1 + x * 4;
      raw[dst] = rgba[src];
      raw[dst + 1] = rgba[src + 1];
      raw[dst + 2] = rgba[src + 2];
      raw[dst + 3] = rgba[src + 3];
    }
  }
  const idat = zlib.deflateSync(raw, { level: 9 });
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
}

function hex(c) {
  return [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)];
}

// 画布：蓝色底 + 白色圆环 + 中心圆点（阅读为“动态令牌”符号）
function draw(size, withBackground) {
  const rgba = new Uint8Array(size * size * 4);
  const bg = hex('#0B57D0');
  const cx = size / 2;
  const cy = size / 2;
  const rOuter = size * 0.30;
  const rInner = size * 0.215;
  const rDot = size * 0.085;
  // 圆角矩形半径（图标容器视觉圆角）
  const cornerR = size * 0.18;
  const maxDist = cornerR * (1 - Math.SQRT1_2);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const i = (y * size + x) * 4;
      const dx = x - cx;
      const dy = y - cy;
      const dist = Math.sqrt(dx * dx + dy * dy);
      // 抗锯齿覆盖率
      const covRing = Math.min(Math.max(rOuter - dist, 0), 1) * Math.min(Math.max(dist - rInner, 0), 1);
      const covDot = Math.min(Math.max(rDot - dist, 0), 1);
      const cov = Math.max(covRing, covDot);
      let bgCov = 0;
      if (withBackground) {
        // 圆角矩形内 = 1
        const nx = Math.min(Math.max(x, cornerR), size - cornerR);
        const ny = Math.min(Math.max(y, cornerR), size - cornerR);
        const ddx = x - nx;
        const ddy = y - ny;
        const dd = Math.sqrt(ddx * ddx + ddy * ddy);
        bgCov = Math.min(Math.max(cornerR - dd, 0), 1);
        if (x >= maxDist && x <= size - maxDist) bgCov = 1;
        if (y >= maxDist && y <= size - maxDist) bgCov = 1;
      }
      const alpha = Math.max(cov, bgCov);
      if (alpha <= 0) {
        rgba[i + 3] = 0;
        continue;
      }
      // 白色符号优先，否则蓝色底
      const useWhite = cov > 0.5 ? 1 : 0;
      const base = useWhite ? [255, 255, 255] : bg;
      rgba[i] = base[0];
      rgba[i + 1] = base[1];
      rgba[i + 2] = base[2];
      rgba[i + 3] = Math.round(alpha * 255);
    }
  }
  return rgba;
}

const outRoot = process.argv[2];
if (!outRoot) {
  console.error('usage: node gen_icons.js <projectRoot>');
  process.exit(1);
}

const files = [
  // [路径, 尺寸, 是否带背景]
  [path.join(outRoot, 'AppScope/resources/base/media/app_icon.png'), 216, true],
  [path.join(outRoot, 'entry/src/main/resources/base/media/background.png'), 1024, false],
  [path.join(outRoot, 'entry/src/main/resources/base/media/foreground.png'), 1024, false],
  [path.join(outRoot, 'entry/src/main/resources/base/media/startIcon.png'), 512, false]
];

for (const [file, size] of files) {
  const withBg = file.includes('app_icon');
  let rgba;
  if (file.includes('background.png')) {
    // 纯色背景
    rgba = new Uint8Array(size * size * 4);
    const bg = hex('#0B57D0');
    for (let i = 0; i < size * size; i++) {
      rgba[i * 4] = bg[0];
      rgba[i * 4 + 1] = bg[1];
      rgba[i * 4 + 2] = bg[2];
      rgba[i * 4 + 3] = 255;
    }
  } else {
    rgba = draw(size, withBg);
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, encodePng(size, size, rgba));
  console.log('written', file, `${size}x${size}`);
}
