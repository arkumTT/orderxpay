package psp

import "testing"

// InitializeTransaction's structural guardrail: a split with no explicit
// flat fee must be refused rather than silently falling back to the
// subaccount's static percentage_charge (see InitializeParams' doc comment
// on why that fallback must never decide a real transaction). Tested
// directly against the pure validator — no network call.
func TestValidateInitializeParams(t *testing.T) {
	cases := []struct {
		name    string
		params  InitializeParams
		wantErr bool
	}{
		{
			name:    "subaccount with no transaction_charge",
			params:  InitializeParams{Subaccount: "ACCT_xxx", TransactionChargePesewas: 0},
			wantErr: true,
		},
		{
			name:    "subaccount with a negative transaction_charge",
			params:  InitializeParams{Subaccount: "ACCT_xxx", TransactionChargePesewas: -1},
			wantErr: true,
		},
		{
			name:    "subaccount with a positive transaction_charge",
			params:  InitializeParams{Subaccount: "ACCT_xxx", TransactionChargePesewas: 100},
			wantErr: false,
		},
		{
			name:    "no subaccount, no transaction_charge — the ordinary unsplit path",
			params:  InitializeParams{},
			wantErr: false,
		},
		{
			name:    "no subaccount but a transaction_charge set anyway — harmless, ignored",
			params:  InitializeParams{TransactionChargePesewas: 50},
			wantErr: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateInitializeParams(tc.params)
			if tc.wantErr && err != errSplitRequiresTransactionCharge {
				t.Errorf("expected errSplitRequiresTransactionCharge, got: %v", err)
			}
			if !tc.wantErr && err != nil {
				t.Errorf("expected no error, got: %v", err)
			}
		})
	}
}
