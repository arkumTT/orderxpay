"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export function SupportSearchBox({ query }: { query: string }) {
  const router = useRouter();
  const [value, setValue] = useState(query);

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        const q = value.trim();
        router.push(q ? `/support?q=${encodeURIComponent(q)}` : "/support");
      }}
      className="flex gap-2"
    >
      <input
        type="text"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder="Merchant name/phone, customer phone, or invoice reference…"
        className="w-full max-w-lg rounded-md border border-neutral-300 px-3 py-2 text-sm"
        autoFocus
      />
      <button
        type="submit"
        className="rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white"
      >
        Search
      </button>
    </form>
  );
}
