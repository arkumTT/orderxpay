package handlers

import "testing"

func TestProratedCommissionPesewas(t *testing.T) {
	cases := []struct {
		name                     string
		invoiceCommissionPesewas int64
		invoiceTotalPesewas      int64
		chargeAmountPesewas      int64
		want                     int64
	}{
		{
			name:                     "full payment carries the full commission",
			invoiceCommissionPesewas: 256,
			invoiceTotalPesewas:      10256,
			chargeAmountPesewas:      10256,
			want:                     256,
		},
		{
			name:                     "half payment carries half the commission",
			invoiceCommissionPesewas: 256,
			invoiceTotalPesewas:      10256,
			chargeAmountPesewas:      5128,
			want:                     128,
		},
		{
			name:                     "a payment small enough to floor to zero",
			invoiceCommissionPesewas: 30, // a ₵5 floor-priced invoice's commission
			invoiceTotalPesewas:      530,
			chargeAmountPesewas:      10, // ten pesewas
			want:                     0,  // 30*10/530 = 0.56 → floors to 0
		},
		{
			name:                     "zero invoice total never divides by zero",
			invoiceCommissionPesewas: 100,
			invoiceTotalPesewas:      0,
			chargeAmountPesewas:      100,
			want:                     0,
		},
		{
			name:                     "negative invoice total (should never happen) still doesn't panic",
			invoiceCommissionPesewas: 100,
			invoiceTotalPesewas:      -1,
			chargeAmountPesewas:      100,
			want:                     0,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := proratedCommissionPesewas(tc.invoiceCommissionPesewas, tc.invoiceTotalPesewas, tc.chargeAmountPesewas)
			if got != tc.want {
				t.Errorf("proratedCommissionPesewas(%d, %d, %d) = %d, want %d",
					tc.invoiceCommissionPesewas, tc.invoiceTotalPesewas, tc.chargeAmountPesewas, got, tc.want)
			}
		})
	}
}

// Summing every partial payment's prorated share should never exceed the
// invoice's true commission — the whole point of using floor (never
// ceiling) division here.
func TestProratedCommissionNeverOverAllocatesAcrossPartialPayments(t *testing.T) {
	const commission = 256
	const total = 10256
	parts := []int64{3000, 3000, 3000, 1256} // sums to total

	var sum int64
	for _, part := range parts {
		sum += proratedCommissionPesewas(commission, total, part)
	}
	if sum > commission {
		t.Errorf("summed prorated commission %d exceeds the invoice's true commission %d", sum, commission)
	}
}
