package api

import (
	"encoding/binary"
	"image"
	"io"
	"os"

	// 注册 jpeg/png 解码器，供 image.DecodeConfig 使用。
	_ "image/jpeg"
	_ "image/png"
)

// imageDims 尽力读出图片宽高：jpeg/png 走标准库，webp 手工解析头，
// HEIC 等读不到时返回 0,0（客户端自行按默认比例占位），绝不因此让上传失败。
func imageDims(path string) (int, int) {
	f, err := os.Open(path)
	if err != nil {
		return 0, 0
	}
	defer f.Close()

	if cfg, _, err := image.DecodeConfig(f); err == nil && cfg.Width > 0 && cfg.Height > 0 {
		return cfg.Width, cfg.Height
	}
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return 0, 0
	}
	head := make([]byte, 64)
	n, _ := io.ReadFull(f, head)
	if w, h, ok := webpDims(head[:n]); ok {
		return w, h
	}
	return 0, 0
}

func webpDims(b []byte) (int, int, bool) {
	if len(b) < 30 || string(b[0:4]) != "RIFF" || string(b[8:12]) != "WEBP" {
		return 0, 0, false
	}
	chunk := string(b[12:16])
	switch chunk {
	case "VP8 ":
		// 3 字节帧标签 + 3 字节起始码，随后 14 位宽、14 位高。
		if len(b) < 30 || b[23] != 0x9d || b[24] != 0x01 || b[25] != 0x2a {
			return 0, 0, false
		}
		w := int(binary.LittleEndian.Uint16(b[26:28]) & 0x3fff)
		h := int(binary.LittleEndian.Uint16(b[28:30]) & 0x3fff)
		return w, h, w > 0 && h > 0
	case "VP8L":
		if len(b) < 25 || b[20] != 0x2f {
			return 0, 0, false
		}
		bits := binary.LittleEndian.Uint32(b[21:25])
		w := int(bits&0x3fff) + 1
		h := int((bits>>14)&0x3fff) + 1
		return w, h, true
	case "VP8X":
		if len(b) < 30 {
			return 0, 0, false
		}
		w := int(uint32(b[24])|uint32(b[25])<<8|uint32(b[26])<<16) + 1
		h := int(uint32(b[27])|uint32(b[28])<<8|uint32(b[29])<<16) + 1
		return w, h, true
	}
	return 0, 0, false
}
