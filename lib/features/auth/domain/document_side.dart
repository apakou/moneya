import 'kyc_document_type.dart';

/// Which side of an identity document is being captured.
///
/// Passport only ever uses [front] (the photo page). National ID uses both
/// [front] and [back].
enum DocumentSide {
  front,
  back;

  /// Title shown above the camera viewfinder for this side.
  String get instruction {
    switch (this) {
      case DocumentSide.front:
        return 'Position the front of your document in the frame';
      case DocumentSide.back:
        return 'Position the back of your document in the frame';
    }
  }
}

/// Whether [type] requires capturing the back side as well as the front.
bool documentRequiresBackSide(KycDocumentType type) {
  switch (type) {
    case KycDocumentType.nationalId:
      return true;
    case KycDocumentType.passport:
      return false;
  }
}
