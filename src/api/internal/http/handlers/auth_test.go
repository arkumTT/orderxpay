package handlers

import "testing"

func TestMerchantLoginRequestValidation(t *testing.T) {
	valid := merchantLoginRequest{Email: "a@b.com", Password: "hunter22"}
	if err := valid.validate(); err != nil {
		t.Fatalf("email + password should be valid, got: %v", err)
	}

	phoneOnly := merchantLoginRequest{Phone: "+233200553771", Password: "hunter22"}
	if err := phoneOnly.validate(); err != nil {
		t.Fatalf("phone + password should be valid, got: %v", err)
	}

	both := merchantLoginRequest{Email: "a@b.com", Phone: "+233200553771", Password: "hunter22"}
	if err := both.validate(); err != nil {
		t.Fatalf("email and phone together should still be valid (email wins), got: %v", err)
	}

	for name, mutate := range map[string]func(*merchantLoginRequest){
		"blank password":             func(r *merchantLoginRequest) { r.Password = "" },
		"no email and no phone":      func(r *merchantLoginRequest) { r.Email = ""; r.Phone = "" },
		"only phone, blank password": func(r *merchantLoginRequest) { r.Email = ""; r.Password = "" },
	} {
		req := valid
		mutate(&req)
		if err := req.validate(); err == nil {
			t.Errorf("%s should be rejected", name)
		}
	}
}

// A request with neither identifier is rejected before ever reaching a DB
// lookup — this is the case a merchant hits if the mobile client has a bug
// and sends an empty login request.
func TestMerchantLoginRequestNoIdentifierIsInvalid(t *testing.T) {
	req := merchantLoginRequest{Password: "hunter22"}
	if err := req.validate(); err == nil {
		t.Error("a request with no email and no phone should be rejected")
	}
}
