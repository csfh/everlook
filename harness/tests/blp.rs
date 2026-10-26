use everlook_harness::blp::decode;

fn texture(encoding: u8, alpha_kind: u8, width: u32, height: u32, data: &[u8]) -> Vec<u8> {
    let mut file = b"BLP2".to_vec();
    file.extend_from_slice(&1u32.to_le_bytes());
    file.extend_from_slice(&[encoding, 0, alpha_kind, 0]);
    file.extend_from_slice(&width.to_le_bytes());
    file.extend_from_slice(&height.to_le_bytes());
    let mut offsets = [0u32; 16];
    let mut sizes = [0u32; 16];
    offsets[0] = 148 + 1024;
    sizes[0] = data.len() as u32;
    for offset in offsets {
        file.extend_from_slice(&offset.to_le_bytes());
    }
    for size in sizes {
        file.extend_from_slice(&size.to_le_bytes());
    }
    let mut palette = vec![0u8; 1024];
    palette[4..8].copy_from_slice(&[10, 20, 30, 255]);
    file.extend_from_slice(&palette);
    file.extend_from_slice(data);
    file
}

#[test]
fn a_palette_texture_reads_blue_green_red_order() {
    let image = decode(&texture(1, 0, 2, 1, &[1, 0])).unwrap();
    assert_eq!(image.get_pixel(0, 0).0, [30, 20, 10, 255]);
}

#[test]
fn a_dxt1_block_with_one_colour_fills_every_pixel() {
    // Both colours pure red in 5-6-5, every index zero.
    let block = [0x00, 0xf8, 0x00, 0xf8, 0, 0, 0, 0];
    let image = decode(&texture(2, 0, 4, 4, &block)).unwrap();
    assert_eq!(image.get_pixel(3, 3).0, [255, 0, 0, 255]);
}

#[test]
fn a_dxt5_block_carries_its_own_alpha() {
    let mut block = vec![255, 0, 0, 0, 0, 0, 0, 0];
    block.extend_from_slice(&[0x00, 0xf8, 0x00, 0xf8, 0, 0, 0, 0]);
    let image = decode(&texture(2, 7, 4, 4, &block)).unwrap();
    assert_eq!(image.get_pixel(0, 0).0, [255, 0, 0, 255]);
}

#[test]
fn a_file_that_is_not_a_texture_is_refused() {
    assert!(decode(b"not a texture").is_err());
}
