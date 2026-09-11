/// The fixed decline-reason vocabulary for order requests (Section 4.6) —
/// keys must match validDeclineReasons in
/// internal/http/handlers/order_requests.go exactly. Canned messages live
/// here, not on the server: composing the customer-facing text is the
/// mobile client's job everywhere else in this app (see
/// InvoiceSentScreen._messageText), and the backend never needs to know the
/// wording, only the category.
const List<String> declineReasonKeys = [
  'out_of_stock',
  'cant_deliver_there',
  'not_taking_orders',
  'duplicate',
  'suspected_spam',
  'other',
];

/// What the merchant sees on the reason picker.
const Map<String, String> declineReasonLabels = {
  'out_of_stock': 'Out of stock',
  'cant_deliver_there': "Can't deliver to that location",
  'not_taking_orders': 'Not taking new orders right now',
  'duplicate': 'Duplicate — already have this order',
  'suspected_spam': "Suspicious / couldn't verify the request",
  'other': 'Other',
};

/// The default customer-facing message for each category — empty for
/// 'other' (the merchant's own note *is* the message there) and for
/// 'suspected_spam' (see declineDeemphasizesNotifying below: this one
/// falls back to a neutral line only if the merchant sends anyway, since
/// leading with "you looked suspicious" helps no one).
const Map<String, String> declineReasonCannedMessages = {
  'out_of_stock': "Sorry, this item isn't in stock right now.",
  'cant_deliver_there': "Sorry, we don't deliver to that area.",
  'not_taking_orders':
      "We're not able to take new orders at the moment — please try again later.",
  'duplicate': 'Looks like we already have this order — no need to resubmit.',
  'suspected_spam': "We're unable to process this order request.",
  'other': '',
};

/// A merchant declining as spam/unverifiable probably shouldn't be
/// nudged to message the customer back at all — replying just confirms a
/// possibly-fake contact is live. Every other category defaults to
/// prompting the merchant to let the customer know; this one flips that
/// default without removing the option.
bool declineDeemphasizesNotifying(String category) =>
    category == 'suspected_spam';

/// The full outbound message for a decline: the category's canned line,
/// plus the merchant's own note appended if they added one. 'other' has no
/// canned line, so the note (required in that case — see
/// setOrderRequestStatusRequest.validate) carries the whole message.
String declineMessageFor(String category, String note) {
  final canned = declineReasonCannedMessages[category] ?? '';
  final trimmedNote = note.trim();
  if (canned.isEmpty) return trimmedNote;
  if (trimmedNote.isEmpty) return canned;
  return '$canned $trimmedNote';
}
