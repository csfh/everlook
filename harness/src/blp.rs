//! Reads the game's own texture files (BLP2) into pixels: palette, DXT1, DXT3, DXT5 and plain BGRA, first level only.

use image::RgbaImage;

fn le32(bytes: &[u8], at: usize) -> u32 {
    u32::from_le_bytes([bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]])
}

pub fn decode(bytes: &[u8]) -> Result<RgbaImage, String> {
    if bytes.len() < 148 || &bytes[0..4] != b"BLP2" || le32(bytes, 4) != 1 {
        return Err("not a BLP2 texture".into());
    }
    let encoding = bytes[8];
    let alpha_depth = bytes[9];
    let alpha_kind = bytes[10];
    let width = le32(bytes, 12) as usize;
    let height = le32(bytes, 16) as usize;
    let offset = le32(bytes, 20) as usize;
    let size = le32(bytes, 84) as usize;
    if width == 0 || height == 0 || offset + size > bytes.len() {
        return Err("a texture that runs past its file".into());
    }
    let data = &bytes[offset..offset + size];
    let mut image = RgbaImage::new(width as u32, height as u32);
    match encoding {
        1 => {
            let palette = &bytes[148..148 + 1024];
            let pixels = width * height;
            if data.len() < pixels {
                return Err("a palette texture that is too short".into());
            }
            for i in 0..pixels {
                let entry = &palette[data[i] as usize * 4..data[i] as usize * 4 + 4];
                let alpha = match alpha_depth {
                    0 => 255,
                    1 => {
                        let bit = (data[pixels + i / 8] >> (i % 8)) & 1;
                        bit * 255
                    }
                    4 => {
                        let byte = data[pixels + i / 2];
                        let nibble = if i % 2 == 0 { byte & 15 } else { byte >> 4 };
                        nibble * 17
                    }
                    _ => data[pixels + i],
                };
                image.put_pixel((i % width) as u32, (i / width) as u32, image::Rgba([entry[2], entry[1], entry[0], alpha]));
            }
        }
        2 => {
            let block_bytes = if alpha_kind == 0 { 8 } else { 16 };
            let (blocks_x, blocks_y) = (width.div_ceil(4), height.div_ceil(4));
            if data.len() < blocks_x * blocks_y * block_bytes {
                return Err("a compressed texture that is too short".into());
            }
            for by in 0..blocks_y {
                for bx in 0..blocks_x {
                    let block = &data[(by * blocks_x + bx) * block_bytes..][..block_bytes];
                    let (alpha_part, colour_part) = block.split_at(block_bytes - 8);
                    let colours = colour_block(colour_part, alpha_kind == 0);
                    for py in 0..4 {
                        for px in 0..4 {
                            let (x, y) = (bx * 4 + px, by * 4 + py);
                            if x >= width || y >= height {
                                continue;
                            }
                            let mut pixel = colours[py * 4 + px];
                            match alpha_kind {
                                1 => {
                                    let byte = alpha_part[py * 2 + px / 2];
                                    pixel[3] = (if px % 2 == 0 { byte & 15 } else { byte >> 4 }) * 17;
                                }
                                7 => pixel[3] = dxt5_alpha(alpha_part, py * 4 + px),
                                _ => {}
                            }
                            image.put_pixel(x as u32, y as u32, image::Rgba(pixel));
                        }
                    }
                }
            }
        }
        3 => {
            if data.len() < width * height * 4 {
                return Err("an uncompressed texture that is too short".into());
            }
            for i in 0..width * height {
                let p = &data[i * 4..i * 4 + 4];
                image.put_pixel((i % width) as u32, (i / width) as u32, image::Rgba([p[2], p[1], p[0], p[3]]));
            }
        }
        other => return Err(format!("texture encoding {other} is not one this reader knows")),
    }
    Ok(image)
}

fn expand565(value: u16) -> [u8; 3] {
    let (r, g, b) = ((value >> 11) & 31, (value >> 5) & 63, value & 31);
    [((r << 3) | (r >> 2)) as u8, ((g << 2) | (g >> 4)) as u8, ((b << 3) | (b >> 2)) as u8]
}

/// The sixteen colours of a DXT colour block. With `one_bit_alpha`, a block whose first colour is the smaller one
/// keeps a clear fourth colour.
fn colour_block(block: &[u8], one_bit_alpha: bool) -> [[u8; 4]; 16] {
    let c0 = u16::from_le_bytes([block[0], block[1]]);
    let c1 = u16::from_le_bytes([block[2], block[3]]);
    let (a, b) = (expand565(c0), expand565(c1));
    let mix = |x: u8, y: u8, wx: u32, wy: u32, total: u32| ((x as u32 * wx + y as u32 * wy) / total) as u8;
    let mut table = [[0u8; 4]; 4];
    table[0] = [a[0], a[1], a[2], 255];
    table[1] = [b[0], b[1], b[2], 255];
    if c0 > c1 || !one_bit_alpha {
        table[2] = [mix(a[0], b[0], 2, 1, 3), mix(a[1], b[1], 2, 1, 3), mix(a[2], b[2], 2, 1, 3), 255];
        table[3] = [mix(a[0], b[0], 1, 2, 3), mix(a[1], b[1], 1, 2, 3), mix(a[2], b[2], 1, 2, 3), 255];
    } else {
        table[2] = [mix(a[0], b[0], 1, 1, 2), mix(a[1], b[1], 1, 1, 2), mix(a[2], b[2], 1, 1, 2), 255];
        table[3] = [0, 0, 0, 0];
    }
    let bits = u32::from_le_bytes([block[4], block[5], block[6], block[7]]);
    let mut out = [[0u8; 4]; 16];
    for (i, pixel) in out.iter_mut().enumerate() {
        *pixel = table[((bits >> (2 * i)) & 3) as usize];
    }
    out
}

fn dxt5_alpha(block: &[u8], index: usize) -> u8 {
    let (a0, a1) = (block[0] as u32, block[1] as u32);
    let bits = block[2..8].iter().enumerate().fold(0u64, |v, (i, byte)| v | (*byte as u64) << (8 * i));
    let code = ((bits >> (3 * index)) & 7) as u32;
    let value = match code {
        0 => a0,
        1 => a1,
        c if a0 > a1 => ((8 - c) * a0 + (c - 1) * a1) / 7,
        6 => 0,
        7 => 255,
        c => ((6 - c) * a0 + (c - 1) * a1) / 5,
    };
    value as u8
}
