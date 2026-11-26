package main

import (
	"path/filepath"
	"testing"
	"time"
)

func TestActivityFullMonthsLocalCalendar(t *testing.T) {
	for _, zone := range []string{"Europe/Berlin", "America/New_York", "Asia/Kathmandu", "Pacific/Kiritimati"} {
		loc, _ := time.LoadLocation(zone)
		for _, date := range []string{"2026-02-01", "2024-02-01", "2026-03-01", "2026-10-01", "2026-11-01", "2026-12-01"} {
			start, _ := time.ParseInLocation("2006-01-02", date, loc)
			end := start.AddDate(0, 1, 0)
			days := end.AddDate(0, 0, -1).Day()
			cfg := &serverConfig{historyPath: filepath.Join(t.TempDir(), "history.json")}
			store, err := openHistory(filepath.Join(filepath.Dir(cfg.historyPath), "users", sessionHash("a")+".json"))
			if err != nil {
				t.Fatal(err)
			}
			for i, at := range []time.Time{start.Add(-time.Second), start, end.Add(-time.Second), end} {
				if err = store.append(translationRecord{ID: string(rune('a' + i)), CreatedAt: at, translationResult: translationResult{Translation: "saved"}}); err != nil {
					t.Fatal(err)
				}
			}
			got := cfg.activityRange("a", start, loc, days)
			if len(got.Days) != days || got.Days[0].KnownCount != 1 || got.Days[days-1].KnownCount != 1 {
				t.Fatalf("%s %s: %+v", zone, date, got)
			}
			total := 0
			for i, d := range got.Days {
				total += d.KnownCount
				if d.Date != start.AddDate(0, 0, i).Format("2006-01-02") {
					t.Fatal("calendar day gap")
				}
			}
			if total != 2 {
				t.Fatal("range leaked boundary", total)
			}
			if len(cfg.activityWeek("a", start, loc).Days) != 7 {
				t.Fatal("native changed")
			}
		}
	}
}
