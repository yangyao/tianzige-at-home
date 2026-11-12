package store

import "time"

// 全服务统一使用 Asia/Shanghai。用 FixedZone 而不是 LoadLocation，
// 避免 NAS 上缺少 tzdata 导致启动失败。
const (
	DateLayout     = "2006-01-02"
	dateTimeLayout = "2006-01-02T15:04:05+08:00"
)

var loc = time.FixedZone("Asia/Shanghai", 8*3600)

// Location 返回服务端统一时区。
func Location() *time.Location { return loc }

// Now 返回上海时区的当前时间。
func Now() time.Time { return time.Now().In(loc) }

// Today 返回上海时区的今天，YYYY-MM-DD。
func Today() string { return Now().Format(DateLayout) }

// FormatTime 输出 RFC3339 +08:00，用于 created_at / ocr_at / done_at。
func FormatTime(t time.Time) string { return t.In(loc).Format(dateTimeLayout) }

// ParseDate 解析 YYYY-MM-DD，并做严格校验（2026-02-30 会失败）。
func ParseDate(s string) (time.Time, error) {
	return time.ParseInLocation(DateLayout, s, loc)
}

// ValidDate 判断字符串是否为合法日期。
func ValidDate(s string) bool {
	_, err := ParseDate(s)
	return err == nil
}

// DaysAgo 计算 date 相对 today 的天数差：昨天 1，今天 0，未来为负。
func DaysAgo(date, today string) (int, error) {
	d, err := ParseDate(date)
	if err != nil {
		return 0, err
	}
	t, err := ParseDate(today)
	if err != nil {
		return 0, err
	}
	return int(t.Sub(d).Hours() / 24), nil
}
