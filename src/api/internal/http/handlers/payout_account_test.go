package handlers

import "testing"

func TestBankTypeForAccountType(t *testing.T) {
	cases := map[string]string{
		"momo": "mobile_money",
		"bank": "ghipss",
	}
	for accountType, want := range cases {
		got, err := bankTypeForAccountType(accountType)
		if err != nil {
			t.Fatalf("%s: unexpected error: %v", accountType, err)
		}
		if got != want {
			t.Errorf("%s: got %q, want %q", accountType, got, want)
		}
	}

	for _, bad := range []string{"", "MOMO", "cash", "mobile_money"} {
		if _, err := bankTypeForAccountType(bad); err == nil {
			t.Errorf("%q should be rejected — momo/bank are the only account types the schema allows", bad)
		}
	}
}

func TestPayoutAccountRequestValidation(t *testing.T) {
	valid := payoutAccountRequest{AccountType: "momo", AccountNumber: "0551234567", BankCode: "MTN"}
	if err := valid.validate(); err != nil {
		t.Fatalf("a complete request should be valid, got: %v", err)
	}

	for name, mutate := range map[string]func(*payoutAccountRequest){
		"blank account_type":   func(r *payoutAccountRequest) { r.AccountType = "" },
		"unknown account_type": func(r *payoutAccountRequest) { r.AccountType = "wallet" },
		"blank account_number": func(r *payoutAccountRequest) { r.AccountNumber = "" },
		"blank bank_code":      func(r *payoutAccountRequest) { r.BankCode = "" },
	} {
		req := valid
		mutate(&req)
		if err := req.validate(); err == nil {
			t.Errorf("%s should be rejected", name)
		}
	}
}

func TestPayoutAccountRequestNormalizeTrims(t *testing.T) {
	req := payoutAccountRequest{
		AccountType:   " momo ",
		AccountNumber: " 0551234567 ",
		BankCode:      " MTN ",
	}
	req.normalize()
	if req.AccountType != "momo" || req.AccountNumber != "0551234567" || req.BankCode != "MTN" {
		t.Errorf("normalize did not trim whitespace, got: %+v", req)
	}
}

// A whitespace-only account_type must still fail validation — normalize
// runs before validate in both handlers, and a caller that skipped
// normalize entirely should not accidentally pass either.
func TestPayoutAccountRequestWhitespaceOnlyIsNotValid(t *testing.T) {
	req := payoutAccountRequest{AccountType: "   ", AccountNumber: "1", BankCode: "1"}
	if err := req.validate(); err == nil {
		t.Error("a whitespace-only account_type should be rejected")
	}
}
