package handlers

import (
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	db "github.com/orderxpay/api/internal/db/sqlc"
)

func clawback(amount int64) db.SettlementClawback {
	return db.SettlementClawback{
		ID:            pgtype.UUID{Bytes: uuid.New(), Valid: true},
		AmountPesewas: amount,
	}
}

func TestConsumeOutstandingClawbacksNoDebt(t *testing.T) {
	remaining, applied := consumeOutstandingClawbacks(10_000, nil)
	if remaining != 10_000 {
		t.Errorf("remaining = %d, want 10000 (untouched)", remaining)
	}
	if len(applied) != 0 {
		t.Errorf("applied = %v, want none", applied)
	}
}

func TestConsumeOutstandingClawbacksFullyAbsorbed(t *testing.T) {
	outstanding := []db.SettlementClawback{clawback(1_000), clawback(500)}
	remaining, applied := consumeOutstandingClawbacks(10_000, outstanding)
	if remaining != 8_500 {
		t.Errorf("remaining = %d, want 8500", remaining)
	}
	if len(applied) != 2 {
		t.Fatalf("applied = %d rows, want 2", len(applied))
	}
}

// A payout that clawback reduces to exactly the threshold, or below it, is
// the case GenerateSettlement's threshold check must see — this only
// verifies the arithmetic stays exact at the boundary.
func TestConsumeOutstandingClawbacksExactMatch(t *testing.T) {
	remaining, applied := consumeOutstandingClawbacks(1_000, []db.SettlementClawback{clawback(1_000)})
	if remaining != 0 {
		t.Errorf("remaining = %d, want 0", remaining)
	}
	if len(applied) != 1 {
		t.Fatalf("applied = %d rows, want 1", len(applied))
	}
}

// The core guarantee: a single clawback larger than this settlement's whole
// payout is never partially taken — it waits, whole, for a settlement big
// enough to cover it. A payout can never be forced negative to "collect" a
// debt.
func TestConsumeOutstandingClawbacksNeverGoesNegativeOrSplits(t *testing.T) {
	remaining, applied := consumeOutstandingClawbacks(1_000, []db.SettlementClawback{clawback(5_000)})
	if remaining != 1_000 {
		t.Errorf("remaining = %d, want 1000 (untouched — the debt didn't fit)", remaining)
	}
	if len(applied) != 0 {
		t.Errorf("applied = %v, want none — a clawback is never partially consumed", applied)
	}
}

// Oldest-first, and a debt that doesn't fit blocks the queue rather than
// letting a smaller one behind it jump ahead — otherwise a single large
// chargeback could sit outstanding forever while smaller, newer ones keep
// getting collected around it.
func TestConsumeOutstandingClawbacksOldestFirstBlocksQueue(t *testing.T) {
	big := clawback(5_000)
	small := clawback(200)
	remaining, applied := consumeOutstandingClawbacks(1_000, []db.SettlementClawback{big, small})
	if remaining != 1_000 {
		t.Errorf("remaining = %d, want 1000 — nothing should have been taken", remaining)
	}
	if len(applied) != 0 {
		t.Errorf("applied = %v, want none — the big one blocks the smaller one behind it", applied)
	}
}

func TestConsumeOutstandingClawbacksPartialQueueFits(t *testing.T) {
	first := clawback(300)
	second := clawback(300)
	third := clawback(10_000) // doesn't fit — stops the queue here
	fourth := clawback(1)     // would fit on its own, but stays blocked
	remaining, applied := consumeOutstandingClawbacks(1_000, []db.SettlementClawback{first, second, third, fourth})
	if remaining != 400 {
		t.Errorf("remaining = %d, want 400 (1000 - 300 - 300)", remaining)
	}
	if len(applied) != 2 {
		t.Fatalf("applied = %d rows, want 2 (first and second only)", len(applied))
	}
}
