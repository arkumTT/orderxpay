package handlers

import "testing"

func TestCreateMerchantRequestValidation(t *testing.T) {
	valid := createMerchantRequest{
		BusinessName: "Hand2Muff",
		Phone:        "+233200553771",
		Password:     "hunter222",
	}
	if err := valid.validate(); err != nil {
		t.Fatalf("business_name + phone + password should be valid, got: %v", err)
	}

	// username and email are optional — phone-first signup (Section 4.1).
	withCredentials := valid
	withCredentials.Username = "hand2muff"
	withCredentials.Email = "you@business.com"
	if err := withCredentials.validate(); err != nil {
		t.Fatalf("optionally supplying username/email should still be valid, got: %v", err)
	}

	for name, mutate := range map[string]func(*createMerchantRequest){
		"blank business_name":    func(r *createMerchantRequest) { r.BusinessName = "" },
		"blank phone":            func(r *createMerchantRequest) { r.Phone = "" },
		"blank password":         func(r *createMerchantRequest) { r.Password = "" },
		"password under 8 chars": func(r *createMerchantRequest) { r.Password = "short1" },
	} {
		req := valid
		mutate(&req)
		if err := req.validate(); err == nil {
			t.Errorf("%s should be rejected", name)
		}
	}
}

// The whole point of phone-first signup: a request with no username and no
// email at all — not just blank strings passed explicitly — is valid as
// long as business_name/phone/password are present.
func TestCreateMerchantRequestUsernameAndEmailAreOptional(t *testing.T) {
	req := createMerchantRequest{
		BusinessName: "Hand2Muff",
		Phone:        "+233200553771",
		Password:     "hunter222",
	}
	if req.Username != "" || req.Email != "" {
		t.Fatalf("test setup error: expected both fields zero-valued")
	}
	if err := req.validate(); err != nil {
		t.Errorf("a phone-only signup should be valid, got: %v", err)
	}
}

func TestUpdateMerchantEmailRequestValidation(t *testing.T) {
	valid := updateMerchantEmailRequest{Email: "you@business.com"}
	if err := valid.validate(); err != nil {
		t.Fatalf("a non-blank email should be valid, got: %v", err)
	}

	blank := updateMerchantEmailRequest{Email: ""}
	if err := blank.validate(); err == nil {
		t.Error("a blank email should be rejected")
	}
}

func TestUpdateMerchantEmailRequestNormalizeTrims(t *testing.T) {
	req := updateMerchantEmailRequest{Email: "  you@business.com  "}
	req.normalize()
	if req.Email != "you@business.com" {
		t.Errorf("normalize did not trim whitespace, got: %q", req.Email)
	}
}

// Whitespace-only must still fail validation — normalize runs before
// validate in the handler, and a caller that skipped normalize entirely
// should not accidentally pass either.
func TestUpdateMerchantEmailRequestWhitespaceOnlyIsNotValid(t *testing.T) {
	req := updateMerchantEmailRequest{Email: "   "}
	req.normalize()
	if err := req.validate(); err == nil {
		t.Error("a whitespace-only email should be rejected")
	}
}
