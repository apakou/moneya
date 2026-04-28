/// Result of looking up a phone number against the MoneyA user
/// directory.
///
/// Two-state model:
/// * [found] — the number maps to an existing MoneyA account; we know
///   the recipient's display name and can route the funds directly to
///   their wallet.
/// * [notFound] — no account yet; we'll fall back to the SMS-invite
///   flow (escrow the funds, send the recipient an invite, release on
///   sign-up + phone verification).
sealed class RecipientLookupResult {
  const RecipientLookupResult();
}

class RecipientFound extends RecipientLookupResult {
  const RecipientFound({required this.displayName});

  final String displayName;
}

class RecipientNotFound extends RecipientLookupResult {
  const RecipientNotFound();
}
