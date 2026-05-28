/// CIP-186 callback error codes per Appendix A.
enum Cip186ErrorCode {
  userRejected(-1),
  commitMismatch(-2),
  sessionExpired(-3),
  redirectHostMismatch(-4),
  nonceReplay(-5),
  ttlExpired(-6),
  decryptFailed(-7),
  unsupportedChain(-8),
  unsupportedVersion(-9),
  responseSignatureInvalid(-10),
  auxiliaryDataHashMismatch(-11),
  sessionEntropyReuse(-12),
  sourceAppUnverified(-13),
  useInjectedApi(-14),
  payloadTooLarge(-32),
  internalError(-100);

  const Cip186ErrorCode(this.wireValue);

  final int wireValue;

  String get errorName {
    switch (this) {
      case Cip186ErrorCode.userRejected:
        return 'UserRejected';
      case Cip186ErrorCode.commitMismatch:
        return 'CommitMismatch';
      case Cip186ErrorCode.sessionExpired:
        return 'SessionExpired';
      case Cip186ErrorCode.redirectHostMismatch:
        return 'RedirectHostMismatch';
      case Cip186ErrorCode.nonceReplay:
        return 'NonceReplay';
      case Cip186ErrorCode.ttlExpired:
        return 'TtlExpired';
      case Cip186ErrorCode.decryptFailed:
        return 'DecryptFailed';
      case Cip186ErrorCode.unsupportedChain:
        return 'UnsupportedChain';
      case Cip186ErrorCode.unsupportedVersion:
        return 'UnsupportedVersion';
      case Cip186ErrorCode.responseSignatureInvalid:
        return 'ResponseSignatureInvalid';
      case Cip186ErrorCode.auxiliaryDataHashMismatch:
        return 'AuxiliaryDataHashMismatch';
      case Cip186ErrorCode.sessionEntropyReuse:
        return 'SessionEntropyReuse';
      case Cip186ErrorCode.sourceAppUnverified:
        return 'SourceAppUnverified';
      case Cip186ErrorCode.useInjectedApi:
        return 'UseInjectedAPI';
      case Cip186ErrorCode.payloadTooLarge:
        return 'PayloadTooLarge';
      case Cip186ErrorCode.internalError:
        return 'InternalError';
    }
  }
}

/// CIP-186 protocol-level rejection raised by parser, validator, or signer.
class Cip186Exception implements Exception {
  Cip186Exception(this.code, this.message, {this.offendingKey});

  final Cip186ErrorCode code;
  final String message;
  final String? offendingKey;

  @override
  String toString() =>
      'Cip186Exception(${code.errorName}/${code.wireValue}: $message'
      '${offendingKey != null ? ' [key=$offendingKey]' : ''})';
}
