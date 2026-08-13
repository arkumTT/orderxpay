// Money is always bigint pesewas (GHS lowest unit) over the wire — never floats.
export function formatPesewas(pesewas: number): string {
  return new Intl.NumberFormat("en-GH", {
    style: "currency",
    currency: "GHS",
  }).format(pesewas / 100);
}
