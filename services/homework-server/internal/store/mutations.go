package store

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"strings"
)

// BatchesByDate 返回某天全部批次（含图片与条目），按创建时间升序。
func (s *Store) BatchesByDate(ctx context.Context, date string) ([]Batch, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id FROM batch WHERE date = ? ORDER BY created_at ASC, id ASC`, date)
	if err != nil {
		return nil, err
	}
	ids := []int64{}
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return nil, err
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return nil, err
	}
	rows.Close()

	out := []Batch{}
	for _, id := range ids {
		b, err := s.GetBatch(ctx, id)
		if errors.Is(err, ErrNotFound) {
			continue
		}
		if err != nil {
			return nil, err
		}
		out = append(out, *b)
	}
	return out, nil
}

// DayMarks 返回 [from,to] 内每天是否有作业。没有批次的日子不会出现在结果里，
// 由调用方补空位。
func (s *Store) DayMarks(ctx context.Context, from, to string) ([]DayMark, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT b.date,
		        (SELECT COUNT(*) FROM image i WHERE i.batch_id = b.id),
		        (SELECT COUNT(*) FROM item it WHERE it.batch_id = b.id)
		 FROM batch b WHERE b.date BETWEEN ? AND ?`, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	acc := map[string]*DayMark{}
	for rows.Next() {
		var date string
		var imgN, itemN int
		if err := rows.Scan(&date, &imgN, &itemN); err != nil {
			return nil, err
		}
		m, ok := acc[date]
		if !ok {
			m = &DayMark{Date: date}
			acc[date] = m
		}
		if imgN > 0 {
			m.Has = true
		}
		m.ItemCount += itemN
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	out := make([]DayMark, 0, len(acc))
	for _, m := range acc {
		out = append(out, *m)
	}
	return out, nil
}

// DeleteBatch 删除批次（item/image 级联）并返回需要从磁盘删除的相对路径。
func (s *Store) DeleteBatch(ctx context.Context, id int64) ([]string, error) {
	ok, err := s.BatchExists(ctx, id)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrNotFound
	}
	rows, err := s.db.QueryContext(ctx, `SELECT path FROM image WHERE batch_id = ?`, id)
	if err != nil {
		return nil, err
	}
	paths := []string{}
	for rows.Next() {
		var p string
		if err := rows.Scan(&p); err != nil {
			rows.Close()
			return nil, err
		}
		paths = append(paths, p)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return nil, err
	}
	rows.Close()

	if _, err := s.db.ExecContext(ctx, `DELETE FROM batch WHERE id = ?`, id); err != nil {
		return nil, err
	}
	return paths, nil
}

// UpdateStatus 更新批次状态与错误说明。status=failed 之外会清空 error。
func (s *Store) UpdateStatus(ctx context.Context, id int64, status, errMsg string) error {
	var e any
	if status == StatusFailed {
		e = nullString(errMsg)
	}
	_, err := s.db.ExecContext(ctx, `UPDATE batch SET status = ?, error = ? WHERE id = ?`, status, e, id)
	return err
}

// SetImageOCR 保存单图 OCR 结果。
func (s *Store) SetImageOCR(ctx context.Context, imageID int64, text string) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE image SET ocr_raw = ?, ocr_at = ? WHERE id = ?`, text, FormatTime(Now()), imageID)
	return err
}

// ClearOCR 清空批次下所有图片的 OCR 结果（rerun 时用）。
func (s *Store) ClearOCR(ctx context.Context, batchID int64) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE image SET ocr_raw = NULL, ocr_at = NULL WHERE batch_id = ?`, batchID)
	return err
}

// ReplaceItems 在事务里清空并重建批次下的条目。checkin 表不动。
func (s *Store) ReplaceItems(ctx context.Context, batchID int64, items []NewItem) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DELETE FROM item WHERE batch_id = ?`, batchID); err != nil {
		return err
	}
	for _, it := range items {
		var imgID any
		if it.ImageID > 0 {
			imgID = it.ImageID
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO item(batch_id, image_id, subject, content, sort) VALUES(?,?,?,?,?)`,
			batchID, imgID, it.Subject, it.Content, it.Sort); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// ResetInFlight 把上次进程遗留的 ocr/parsing 状态改回 pending，并返回所有待处理批次 id。
func (s *Store) ResetInFlight(ctx context.Context) ([]int64, error) {
	if _, err := s.db.ExecContext(ctx,
		`UPDATE batch SET status = ? WHERE status IN (?, ?)`, StatusPending, StatusOCR, StatusParsing); err != nil {
		return nil, err
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT id FROM batch WHERE status = ? ORDER BY id`, StatusPending)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	ids := []int64{}
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// CheckinKey 是打勾状态的稳定主键：sha256(subject + content)。
// rerun 后条目 id 会变，但同一条作业的 key 不变。
func CheckinKey(subject, content string) string {
	h := sha256.Sum256([]byte(subject + content))
	return hex.EncodeToString(h[:])
}

// SetCheckin 供测试与将来的打勾接口使用。
func (s *Store) SetCheckin(ctx context.Context, subject, content string, done bool) error {
	key := CheckinKey(subject, content)
	var doneAt any
	if done {
		doneAt = FormatTime(Now())
	}
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO checkin(item_key, done, done_at) VALUES(?,?,?)
		 ON CONFLICT(item_key) DO UPDATE SET done = excluded.done, done_at = excluded.done_at`,
		key, boolInt(done), doneAt)
	return err
}

// GetCheckin 返回打勾状态。
func (s *Store) GetCheckin(ctx context.Context, subject, content string) (bool, string, error) {
	var done int
	var at sql.NullString
	err := s.db.QueryRowContext(ctx,
		`SELECT done, done_at FROM checkin WHERE item_key = ?`, CheckinKey(subject, content)).Scan(&done, &at)
	if errors.Is(err, sql.ErrNoRows) {
		return false, "", nil
	}
	if err != nil {
		return false, "", err
	}
	return done != 0, at.String, nil
}

func nullString(s string) any {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return s
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
