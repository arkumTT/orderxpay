package handlers

import "testing"

func TestCreateStaffRequestValidation(t *testing.T) {
	valid := createStaffRequest{
		Name:     "Ama Boateng",
		Phone:    "+233240000000",
		Password: "hunter222",
	}
	if err := valid.validate(); err != nil {
		t.Fatalf("name + phone + password should be valid, got: %v", err)
	}

	// email is optional — a staffer of a phone-first merchant.
	withEmail := valid
	withEmail.Email = "ama@shop.test"
	if err := withEmail.validate(); err != nil {
		t.Fatalf("optionally supplying an email should still be valid, got: %v", err)
	}

	// role defaults to "staff" in the handler; blank is allowed here.
	if err := valid.validate(); err != nil {
		t.Fatalf("a blank role should be valid (handler defaults it), got: %v", err)
	}
	owner := valid
	owner.Role = "owner"
	if err := owner.validate(); err != nil {
		t.Fatalf("role \"owner\" should be valid, got: %v", err)
	}

	for name, mutate := range map[string]func(*createStaffRequest){
		"blank name":             func(r *createStaffRequest) { r.Name = "" },
		"blank phone":            func(r *createStaffRequest) { r.Phone = "" },
		"blank password":         func(r *createStaffRequest) { r.Password = "" },
		"password under 8 chars": func(r *createStaffRequest) { r.Password = "short1" },
		"unknown role":           func(r *createStaffRequest) { r.Role = "manager" },
	} {
		req := valid
		mutate(&req)
		if err := req.validate(); err == nil {
			t.Errorf("%s should be rejected", name)
		}
	}
}

// The point of the phone-only-staff change: a request with no email at all
// — not just a blank string passed explicitly — is valid.
func TestCreateStaffRequestEmailIsOptional(t *testing.T) {
	req := createStaffRequest{
		Name:     "Kofi Mensah",
		Phone:    "+233270000000",
		Password: "hunter222",
	}
	if req.Email != "" {
		t.Fatalf("test setup error: expected Email zero-valued")
	}
	if err := req.validate(); err != nil {
		t.Errorf("a phone-only staff member should be valid, got: %v", err)
	}
}
