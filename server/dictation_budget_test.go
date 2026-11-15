package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestDictationPaidBudgetDurableReservation(t *testing.T) {
	root := t.TempDir()
	c := dictationOpenAIConfig{chars: 20, seconds: 5, dailyChars: 10, dailySeconds: 10, dailyRequests: 2}
	if err := dictationReservePaid(root, c, "Hallo"); err != nil {
		t.Fatal(err)
	}
	if err := dictationReservePaid(root, c, "Hallo"); err != nil {
		t.Fatal(err)
	}
	if err := dictationReservePaid(root, c, "A"); err == nil {
		t.Fatal("third paid attempt admitted")
	}
	b, err := os.ReadFile(filepath.Join(root, "paid-budget.json"))
	if err != nil {
		t.Fatal(err)
	}
	var d dictationPaidBudget
	if err = json.Unmarshal(b, &d); err != nil {
		t.Fatal(err)
	}
	if d.Requests != 2 || d.Characters != 10 || d.Seconds != 10 {
		t.Fatal("lost reservation", d)
	}
	for _, tc := range []dictationOpenAIConfig{
		{chars: 2, seconds: 1, dailyChars: 100, dailySeconds: 100, dailyRequests: 100},
		{chars: 20, seconds: 1, dailyChars: 3, dailySeconds: 100, dailyRequests: 100},
		{chars: 20, seconds: 5, dailyChars: 100, dailySeconds: 3, dailyRequests: 100},
	} {
		if err := dictationReservePaid(t.TempDir(), tc, "Hallo"); err == nil {
			t.Fatal("bound ignored")
		}
	}
}
