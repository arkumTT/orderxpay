package handlers

import "testing"

func TestResetPasswordRequestValidation(t *testing.T) {
	cases := []struct {
		name    string
		req     resetPasswordRequest
		wantErr bool
	}{
		{
			name: "valid",
			req:  resetPasswordRequest{Phone: "+233244123456", NewPassword: "supersecret"},
		},
		{
			name:    "missing phone",
			req:     resetPasswordRequest{NewPassword: "supersecret"},
			wantErr: true,
		},
		{
			name:    "password too short",
			req:     resetPasswordRequest{Phone: "+233244123456", NewPassword: "short"},
			wantErr: true,
		},
		{
			name:    "empty password",
			req:     resetPasswordRequest{Phone: "+233244123456"},
			wantErr: true,
		},
		{
			name: "exactly the minimum length is allowed",
			req:  resetPasswordRequest{Phone: "+233244123456", NewPassword: "12345678"},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := tc.req.validate()
			if tc.wantErr && err == nil {
				t.Fatal("expected an error, got nil")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}
