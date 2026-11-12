package store

import (
	"context"
	"path/filepath"
	"testing"
)

func newTestStore(t *testing.T) *Store {
	t.Helper()
	st, err := Open(t.TempDir())
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() { st.Close() })
	return st
}

func TestOpenCreatesWAL(t *testing.T) {
	st := newTestStore(t)
	var mode string
	if err := st.db.QueryRow("PRAGMA journal_mode").Scan(&mode); err != nil {
		t.Fatal(err)
	}
	if mode != "wal" {
		t.Fatalf("journal_mode = %q, want wal", mode)
	}
	var fk int
	if err := st.db.QueryRow("PRAGMA foreign_keys").Scan(&fk); err != nil {
		t.Fatal(err)
	}
	if fk != 1 {
		t.Fatalf("foreign_keys = %d, want 1", fk)
	}
	if filepath.Base(st.Dir()) == "" {
		t.Fatal("数据目录为空")
	}
}

func TestCreateBatchAndPaths(t *testing.T) {
	ctx := context.Background()
	st := newTestStore(t)
	id, err := st.CreateBatch(ctx, "2026-11-12", "老师备注", []ImageMeta{
		{Ext: "jpg", SHA256: "aa", Width: 100, Height: 200},
		{Ext: "png", SHA256: "bb", Width: 10, Height: 20},
	})
	if err != nil {
		t.Fatal(err)
	}
	b, err := st.GetBatch(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	if b.Status != StatusPending || b.Note != "老师备注" {
		t.Fatalf("unexpected batch: %+v", b)
	}
	if len(b.Images) != 2 {
		t.Fatalf("images = %d", len(b.Images))
	}
	if b.Images[0].Path != "2026-11-12/1_1.jpg" || b.Images[1].Path != "2026-11-12/1_2.png" {
		t.Fatalf("paths: %q %q", b.Images[0].Path, b.Images[1].Path)
	}
	if b.Images[0].Width != 100 || b.Images[0].Height != 200 {
		t.Fatalf("dims not saved: %+v", b.Images[0])
	}
	if b.CreatedAt == "" || b.CreatedAt[19:] != "+08:00" {
		t.Fatalf("created_at 不是 +08:00: %q", b.CreatedAt)
	}
}

func TestFindBatchByImages(t *testing.T) {
	ctx := context.Background()
	st := newTestStore(t)
	id, err := st.CreateBatch(ctx, "2026-11-12", "", []ImageMeta{
		{Ext: "jpg", SHA256: "s1"},
		{Ext: "jpg", SHA256: "s2"},
	})
	if err != nil {
		t.Fatal(err)
	}

	if got, ok, err := st.FindBatchByImages(ctx, []string{"s2", "s1"}); err != nil || !ok || got != id {
		t.Fatalf("顺序无关的重复应命中: got=%d ok=%v err=%v", got, ok, err)
	}
	if _, ok, err := st.FindBatchByImages(ctx, []string{"s1"}); err != nil || ok {
		t.Fatalf("子集不算重复: ok=%v err=%v", ok, err)
	}
	if _, ok, err := st.FindBatchByImages(ctx, []string{"s1", "s3"}); err != nil || ok {
		t.Fatalf("不同内容不算重复: ok=%v err=%v", ok, err)
	}
	if _, ok, err := st.FindBatchByImages(ctx, nil); err != nil || ok {
		t.Fatalf("空输入: ok=%v err=%v", ok, err)
	}

	// 同一次上传里重复选同一张图，后续再传同样两张也要能命中。
	dupID, err := st.CreateBatch(ctx, "2026-11-12", "", []ImageMeta{
		{Ext: "jpg", SHA256: "same"},
		{Ext: "jpg", SHA256: "same"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if got, ok, err := st.FindBatchByImages(ctx, []string{"same", "same"}); err != nil || !ok || got != dupID {
		t.Fatalf("重复 sha 场景: got=%d ok=%v err=%v", got, ok, err)
	}
}

func TestRerunKeepsCheckin(t *testing.T) {
	ctx := context.Background()
	st := newTestStore(t)
	id, err := st.CreateBatch(ctx, "2026-11-12", "", []ImageMeta{{Ext: "jpg", SHA256: "s1"}})
	if err != nil {
		t.Fatal(err)
	}
	b, _ := st.GetBatch(ctx, id)
	imgID := b.Images[0].ID
	if err := st.ReplaceItems(ctx, id, []NewItem{
		{ImageID: imgID, Subject: "语文", Content: "朗读课文三遍", Sort: 0},
		{Subject: "数学", Content: "练习册 P18", Sort: 0},
	}); err != nil {
		t.Fatal(err)
	}
	if err := st.SetCheckin(ctx, "数学", "练习册 P18", true); err != nil {
		t.Fatal(err)
	}

	b, _ = st.GetBatch(ctx, id)
	if len(b.Items) != 2 {
		t.Fatalf("items = %d", len(b.Items))
	}
	var mathDone bool
	for _, it := range b.Items {
		if it.Subject == "数学" {
			mathDone = it.Done
			if it.DoneAt == "" {
				t.Fatal("done_at 应存在")
			}
		}
		if it.ImageID != 0 && it.ImageID != imgID {
			t.Fatalf("image_id = %d", it.ImageID)
		}
	}
	if !mathDone {
		t.Fatal("checkin 应生效")
	}

	// 模拟 rerun：清空重建（内容相同），checkin 必须还在。
	if err := st.ReplaceItems(ctx, id, []NewItem{
		{ImageID: imgID, Subject: "数学", Content: "练习册 P18", Sort: 0},
		{ImageID: imgID, Subject: "语文", Content: "朗读课文三遍", Sort: 0},
	}); err != nil {
		t.Fatal(err)
	}
	b, _ = st.GetBatch(ctx, id)
	for _, it := range b.Items {
		if it.Subject == "数学" && !it.Done {
			t.Fatal("rerun 后打勾状态丢失")
		}
	}
}

func TestDeleteBatchCascades(t *testing.T) {
	ctx := context.Background()
	st := newTestStore(t)
	id, _ := st.CreateBatch(ctx, "2026-11-12", "", []ImageMeta{{Ext: "jpg", SHA256: "s1"}})
	b, _ := st.GetBatch(ctx, id)
	if err := st.ReplaceItems(ctx, id, []NewItem{{Subject: "语文", Content: "x"}}); err != nil {
		t.Fatal(err)
	}
	paths, err := st.DeleteBatch(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	if len(paths) != 1 || paths[0] != b.Images[0].Path {
		t.Fatalf("paths = %v", paths)
	}
	if _, err := st.GetBatch(ctx, id); err != ErrNotFound {
		t.Fatalf("删除后应 404, got %v", err)
	}
	if _, err := st.DeleteBatch(ctx, id); err != ErrNotFound {
		t.Fatalf("重复删除应 404, got %v", err)
	}
	var n int
	if err := st.db.QueryRow(`SELECT COUNT(*) FROM item`).Scan(&n); err != nil || n != 0 {
		t.Fatalf("item 未级联删除: n=%d err=%v", n, err)
	}
}

func TestDayMarksAndReset(t *testing.T) {
	ctx := context.Background()
	st := newTestStore(t)
	id1, _ := st.CreateBatch(ctx, "2026-11-10", "", []ImageMeta{{Ext: "jpg", SHA256: "a"}})
	id2, _ := st.CreateBatch(ctx, "2026-11-12", "", []ImageMeta{{Ext: "jpg", SHA256: "b"}})
	if err := st.ReplaceItems(ctx, id2, []NewItem{{Subject: "语文", Content: "x"}, {Subject: "数学", Content: "y"}}); err != nil {
		t.Fatal(err)
	}

	marks, err := st.DayMarks(ctx, "2026-11-09", "2026-11-13")
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]DayMark{}
	for _, m := range marks {
		got[m.Date] = m
	}
	if len(got) != 2 {
		t.Fatalf("days = %d, marks=%v", len(got), got)
	}
	if !got["2026-11-10"].Has || got["2026-11-10"].ItemCount != 0 {
		t.Fatalf("2026-11-10: %+v", got["2026-11-10"])
	}
	if !got["2026-11-12"].Has || got["2026-11-12"].ItemCount != 2 {
		t.Fatalf("2026-11-12: %+v", got["2026-11-12"])
	}

	if err := st.UpdateStatus(ctx, id1, StatusOCR, ""); err != nil {
		t.Fatal(err)
	}
	ids, err := st.ResetInFlight(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(ids) != 2 {
		t.Fatalf("恢复的批次 = %v", ids)
	}
	b, _ := st.GetBatch(ctx, id1)
	if b.Status != StatusPending {
		t.Fatalf("status = %s", b.Status)
	}
}

func TestDateHelpers(t *testing.T) {
	if !ValidDate("2026-11-12") {
		t.Fatal("合法日期被判错")
	}
	for _, bad := range []string{"2026-13-01", "2026-02-30", "20261112", "2026-1-2", ""} {
		if ValidDate(bad) {
			t.Fatalf("%q 应为非法日期", bad)
		}
	}
	n, err := DaysAgo("2026-11-11", "2026-11-12")
	if err != nil || n != 1 {
		t.Fatalf("DaysAgo = %d err=%v", n, err)
	}
	n, _ = DaysAgo("2026-11-14", "2026-11-12")
	if n != -2 {
		t.Fatalf("未来日期应为负数, got %d", n)
	}
}
