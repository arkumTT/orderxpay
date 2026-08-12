export function PlaceholderPage({
  title,
  section,
  description,
}: {
  title: string;
  section: string;
  description: string;
}) {
  return (
    <div className="space-y-2">
      <div className="flex items-baseline gap-2">
        <h1 className="text-2xl font-semibold text-neutral-900">{title}</h1>
        <span className="text-xs font-mono text-neutral-400">
          Section {section}
        </span>
      </div>
      <p className="max-w-2xl text-sm text-neutral-500">{description}</p>
      <div className="mt-6 rounded-lg border border-dashed border-neutral-300 p-8 text-center text-sm text-neutral-400">
        Not yet implemented — structural placeholder only.
      </div>
    </div>
  );
}
