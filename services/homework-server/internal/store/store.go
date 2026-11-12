package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	_ "modernc.org/sqlite"
)

// ErrNotFound 表示记录不存在，API 层据此返回 not_found。
var ErrNotFound = errors.New("not found")

const schema = `
CREATE TABLE IF NOT EXISTS batch (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  date       TEXT NOT NULL,
  note       TEXT,
  status     TEXT NOT NULL DEFAULT 'pending',
  error      TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_batch_date ON batch(date);
CREATE INDEX IF NOT EXISTS idx_batch_created ON batch(created_at DESC);
CREATE TABLE IF NOT EXISTS image (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  batch_id INTEGER NOT NULL REFERENCES batch(id) ON DELETE CASCADE,
  path     TEXT NOT NULL,
  sha256   TEXT NOT NULL,
  width    INTEGER NOT NULL DEFAULT 0,
  height   INTEGER NOT NULL DEFAULT 0,
  ocr_raw  TEXT,
  ocr_at   TEXT
);
CREATE INDEX IF NOT EXISTS idx_image_batch ON image(batch_id);
CREATE INDEX IF NOT EXISTS idx_image_sha ON image(sha256);
CREATE TABLE IF NOT EXISTS item (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  batch_id INTEGER NOT NULL REFERENCES batch(id) ON DELETE CASCADE,
  image_id INTEGER REFERENCES image(id) ON DELETE SET NULL,
  subject  TEXT NOT NULL,
  content  TEXT NOT NULL,
  sort     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_item_batch ON item(batch_id);
CREATE TABLE IF NOT EXISTS checkin (
  item_key TEXT PRIMARY KEY,
  done     INTEGER NOT NULL DEFAULT 0,
  done_at  TEXT
);
`

// Store 封装 SQLite。连接数固定为 1：
// 本服务写少读多、数据量小，串行化可以彻底避免 SQLITE_BUSY。
type Store struct {
	db  *sql.DB
	dir string
}

// Open 打开（必要时创建）数据目录下的 hw.db，开启 WAL 与 foreign_keys。
func Open(dataDir string) (*Store, error) {
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return nil, fmt.Errorf("创建数据目录失败: %w", err)
	}
	if err := os.MkdirAll(filepath.Join(dataDir, "tmp"), 0o755); err != nil {
		return nil, fmt.Errorf("创建临时目录失败: %w", err)
	}
	dbPath := filepath.Join(dataDir, "hw.db")
	dsn := "file:" + dbPath + "?_pragma=busy_timeout(10000)&_pragma=journal_mode(WAL)&_pragma=foreign_keys(1)&_pragma=synchronous(NORMAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("打开数据库失败: %w", err)
	}
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)

	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("初始化表结构失败: %w", err)
	}
	if err := db.Ping(); err != nil {
		db.Close()
		return nil, fmt.Errorf("数据库不可用: %w", err)
	}
	s := &Store{db: db, dir: dataDir}
	if err := s.checkIntegrity(); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

func (s *Store) checkIntegrity() error {
	var mode string
	if err := s.db.QueryRow("PRAGMA journal_mode").Scan(&mode); err != nil {
		return fmt.Errorf("读取 journal_mode 失败: %w", err)
	}
	if !strings.EqualFold(mode, "wal") {
		return fmt.Errorf("journal_mode 未生效，当前为 %s", mode)
	}
	return nil
}

// Close 关闭数据库。
func (s *Store) Close() error { return s.db.Close() }

// Dir 返回数据目录。
func (s *Store) Dir() string { return s.dir }

// Ping 供 /api/health 使用。
func (s *Store) Ping(ctx context.Context) error { return s.db.PingContext(ctx) }

// CreateBatch 新建批次并写入图片元数据，返回批次 id。
// 图片相对路径由这里生成，保证命名规则只有一处。
func (s *Store) CreateBatch(ctx context.Context, date, note string, metas []ImageMeta) (int64, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	res, err := tx.ExecContext(ctx,
		`INSERT INTO batch(date, note, status, created_at) VALUES(?,?,?,?)`,
		date, nullString(note), StatusPending, FormatTime(Now()))
	if err != nil {
		return 0, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return 0, err
	}
	for i, m := range metas {
		p := fmt.Sprintf("%s/%d_%d.%s", date, id, i+1, m.Ext)
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO image(batch_id, path, sha256, width, height) VALUES(?,?,?,?,?)`,
			id, p, m.SHA256, m.Width, m.Height); err != nil {
			return 0, err
		}
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return id, nil
}

// FindBatchByImages 查找图片 sha256 集合与给定集合完全一致的已有批次（软去重）。
// 顺序无关；只有"同一批图"才算重复。
func (s *Store) FindBatchByImages(ctx context.Context, shas []string) (int64, bool, error) {
	if len(shas) == 0 {
		return 0, false, nil
	}
	args := make([]any, 0, len(shas)+2)
	seen := make(map[string]bool, len(shas))
	uniq := make([]string, 0, len(shas))
	for _, v := range shas {
		if !seen[v] {
			seen[v] = true
			uniq = append(uniq, v)
		}
	}
	placeholders := make([]string, len(uniq))
	for i, v := range uniq {
		placeholders[i] = "?"
		args = append(args, v)
	}
	args = append(args, len(uniq), len(shas))
	// 批次图片总数与本次一致，且不同 sha 数也一致，才算"同一批图"。
	q := `SELECT i.batch_id FROM image i WHERE i.sha256 IN (` + strings.Join(placeholders, ",") + `)
	      GROUP BY i.batch_id
	      HAVING COUNT(DISTINCT i.sha256) = ?
	         AND (SELECT COUNT(*) FROM image x WHERE x.batch_id = i.batch_id) = ?
	      ORDER BY i.batch_id LIMIT 1`
	var id int64
	err := s.db.QueryRowContext(ctx, q, args...).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, err
	}
	return id, true, nil
}

// GetBatch 读取批次详情，含图片与条目。
func (s *Store) GetBatch(ctx context.Context, id int64) (*Batch, error) {
	b := &Batch{}
	var note, errText sql.NullString
	err := s.db.QueryRowContext(ctx,
		`SELECT id, date, note, status, error, created_at FROM batch WHERE id = ?`, id).
		Scan(&b.ID, &b.Date, &note, &b.Status, &errText, &b.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	b.Note = note.String
	b.Error = errText.String

	imgs, err := s.images(ctx, id)
	if err != nil {
		return nil, err
	}
	b.Images = imgs
	items, err := s.items(ctx, id)
	if err != nil {
		return nil, err
	}
	b.Items = items
	return b, nil
}

// BatchExists 轻量判断批次是否存在。
func (s *Store) BatchExists(ctx context.Context, id int64) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM batch WHERE id = ?`, id).Scan(&n)
	return n > 0, err
}

func (s *Store) images(ctx context.Context, batchID int64) ([]Image, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, batch_id, path, sha256, width, height, COALESCE(ocr_raw,''), COALESCE(ocr_at,'')
		 FROM image WHERE batch_id = ? ORDER BY id`, batchID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Image{}
	for rows.Next() {
		var im Image
		if err := rows.Scan(&im.ID, &im.BatchID, &im.Path, &im.SHA256, &im.Width, &im.Height, &im.OCRRaw, &im.OCRAt); err != nil {
			return nil, err
		}
		out = append(out, im)
	}
	return out, rows.Err()
}

func (s *Store) items(ctx context.Context, batchID int64) ([]Item, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, batch_id, COALESCE(image_id,0), subject, content, sort
		 FROM item WHERE batch_id = ? ORDER BY sort, id`, batchID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Item{}
	keys := []string{}
	for rows.Next() {
		var it Item
		if err := rows.Scan(&it.ID, &it.BatchID, &it.ImageID, &it.Subject, &it.Content, &it.Sort); err != nil {
			return nil, err
		}
		out = append(out, it)
		keys = append(keys, CheckinKey(it.Subject, it.Content))
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// 连接数只有 1，必须先释放 rows 再查 checkin，否则会自我等待。
	rows.Close()
	if len(out) == 0 {
		return out, nil
	}
	marks, err := s.checkins(ctx, keys)
	if err != nil {
		return nil, err
	}
	for i := range out {
		if m, ok := marks[CheckinKey(out[i].Subject, out[i].Content)]; ok {
			out[i].Done = m.Done
			out[i].DoneAt = m.DoneAt
		}
	}
	return out, nil
}

type checkinMark struct {
	Done   bool
	DoneAt string
}

func (s *Store) checkins(ctx context.Context, keys []string) (map[string]checkinMark, error) {
	marks := map[string]checkinMark{}
	if len(keys) == 0 {
		return marks, nil
	}
	ph := make([]string, len(keys))
	args := make([]any, len(keys))
	for i, k := range keys {
		ph[i] = "?"
		args[i] = k
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT item_key, done, COALESCE(done_at,'') FROM checkin WHERE item_key IN (`+strings.Join(ph, ",")+`)`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var k, at string
		var done int
		if err := rows.Scan(&k, &done, &at); err != nil {
			return nil, err
		}
		marks[k] = checkinMark{Done: done != 0, DoneAt: at}
	}
	return marks, rows.Err()
}

// BatchSummary 是批次摘要（列表页用），不展开图片与条目明细。
type BatchSummary struct {
	Batch
	ImageCount int
	ItemCount  int
}

// ListBatches 按创建时间倒序返回批次摘要；date 非空时只取该天。
func (s *Store) ListBatches(ctx context.Context, limit int, date string) ([]BatchSummary, error) {
	if limit <= 0 {
		limit = 6
	}
	q := `SELECT b.id, b.date, COALESCE(b.note,''), b.status, COALESCE(b.error,''), b.created_at,
	             (SELECT COUNT(*) FROM image i WHERE i.batch_id = b.id),
	             (SELECT COUNT(*) FROM item it WHERE it.batch_id = b.id)
	      FROM batch b`
	args := []any{}
	if date != "" {
		q += ` WHERE b.date = ?`
		args = append(args, date)
	}
	q += ` ORDER BY b.created_at DESC, b.id DESC LIMIT ?`
	args = append(args, limit)

	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []BatchSummary{}
	for rows.Next() {
		var sum BatchSummary
		if err := rows.Scan(&sum.ID, &sum.Date, &sum.Note, &sum.Status, &sum.Error, &sum.CreatedAt,
			&sum.ImageCount, &sum.ItemCount); err != nil {
			return nil, err
		}
		sum.Images = []Image{}
		sum.Items = []Item{}
		out = append(out, sum)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}
