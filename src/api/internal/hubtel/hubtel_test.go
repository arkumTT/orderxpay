package hubtel

import "testing"

// pesewasToCedis is the one place this codebase deliberately touches a
// float for money — every value here must round-trip exactly for whole-
// pesewa amounts, since a rounding drift here is real money misstated on
// a real payment prompt.
func TestPesewasToCedis(t *testing.T) {
	cases := []struct {
		pesewas int64
		want    float64
	}{
		{0, 0},
		{1, 0.01},
		{99, 0.99},
		{100, 1.00},
		{755, 7.55},     // the exact worked example found in Hubtel SDK docs
		{10256, 102.56}, // matches a figure already used elsewhere in this codebase
		{100000, 1000.00},
		{1, 0.01},
	}
	for _, tc := range cases {
		got := pesewasToCedis(tc.pesewas)
		if got != tc.want {
			t.Errorf("pesewasToCedis(%d) = %v, want %v", tc.pesewas, got, tc.want)
		}
	}
}

func TestClientEnabledRequiresAllThreeValues(t *testing.T) {
	cases := []struct {
		name                               string
		clientID, clientSecret, posSalesID string
		want                               bool
	}{
		{"all three set", "id", "secret", "pos", true},
		{"missing client id", "", "secret", "pos", false},
		{"missing client secret", "id", "", "pos", false},
		{"missing pos sales id", "id", "secret", "", false},
		{"nothing set", "", "", "", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c := NewClient(tc.clientID, tc.clientSecret, tc.posSalesID)
			if got := c.Enabled(); got != tc.want {
				t.Errorf("Enabled() = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestNilClientIsNotEnabled(t *testing.T) {
	var c *Client
	if c.Enabled() {
		t.Error("a nil *Client must report Enabled() == false, not panic")
	}
}

func TestReceiveMoneyRejectsWhenNotConfigured(t *testing.T) {
	c := NewClient("", "", "")
	_, err := c.ReceiveMoney(nil, ReceiveMoneyParams{ClientReference: "ref"}) //nolint:staticcheck // nil context: this call must fail before ever using it
	if err == nil {
		t.Error("ReceiveMoney should refuse to run against an unconfigured client")
	}
}

func TestReceiveMoneyRequiresClientReference(t *testing.T) {
	c := NewClient("id", "secret", "pos")
	_, err := c.ReceiveMoney(nil, ReceiveMoneyParams{}) //nolint:staticcheck
	if err == nil {
		t.Error("ReceiveMoney should require a client reference before attempting any network call")
	}
}

func TestBasicAuthEncoding(t *testing.T) {
	// RFC 7617 worked example ("Aladdin:open sesame") — verifies this
	// package's base64(id:secret) construction matches the standard
	// exactly, independent of anything Hubtel-specific.
	got := basicAuth("Aladdin", "open sesame")
	want := "QWxhZGRpbjpvcGVuIHNlc2FtZQ=="
	if got != want {
		t.Errorf("basicAuth = %q, want %q", got, want)
	}
}
