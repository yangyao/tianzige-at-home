package api

import (
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
)

func TestWebpDims(t *testing.T) {
	// VP8X：canvas 宽高各 3 字节（存的是值减一）
	b := make([]byte, 30)
	copy(b[0:4], "RIFF")
	copy(b[8:12], "WEBP")
	copy(b[12:16], "VP8X")
	binary.LittleEndian.PutUint32(b[16:20], 10)
	putU24 := func(off int, v int) {
		b[off] = byte(v)
		b[off+1] = byte(v >> 8)
		b[off+2] = byte(v >> 16)
	}
	putU24(24, 639) // 640 宽
	putU24(27, 359) // 360 高
	if w, h, ok := webpDims(b); !ok || w != 640 || h != 360 {
		t.Fatalf("VP8X = %d x %d ok=%v", w, h, ok)
	}

	// VP8L
	l := make([]byte, 30)
	copy(l[0:4], "RIFF")
	copy(l[8:12], "WEBP")
	copy(l[12:16], "VP8L")
	l[20] = 0x2f
	bits := uint32(99) | uint32(49)<<14
	binary.LittleEndian.PutUint32(l[21:25], bits)
	if w, h, ok := webpDims(l); !ok || w != 100 || h != 50 {
		t.Fatalf("VP8L = %d x %d ok=%v", w, h, ok)
	}

	if _, _, ok := webpDims([]byte("not a webp")); ok {
		t.Fatal("非 webp 不应解析成功")
	}
}

func TestImageDimsUnsupportedReturnsZero(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "x.heic")
	if err := os.WriteFile(p, []byte("ftypheic-not-really"), 0o644); err != nil {
		t.Fatal(err)
	}
	if w, h := imageDims(p); w != 0 || h != 0 {
		t.Fatalf("HEIC 应返回 0,0，got %d,%d", w, h)
	}
	if w, h := imageDims(filepath.Join(dir, "missing.png")); w != 0 || h != 0 {
		t.Fatalf("缺失文件应返回 0,0，got %d,%d", w, h)
	}
}

func TestDetectExt(t *testing.T) {
	heic := make([]byte, 16)
	copy(heic[4:8], "ftyp")
	copy(heic[8:12], "heic")
	if ext, ok := detectExt(heic, "IMG_0001.HEIC"); !ok || ext != "heic" {
		t.Fatalf("heic 探测失败: %q %v", ext, ok)
	}
	if ext, ok := detectExt([]byte("plain text"), "a.jpg"); !ok || ext != "jpg" {
		t.Fatalf("按扩展名兜底失败: %q %v", ext, ok)
	}
	if _, ok := detectExt([]byte("plain text"), "a.txt"); ok {
		t.Fatal("txt 应被拒绝")
	}
}
