import 'dart:convert';
import 'dart:typed_data';

import 'package:cardano_dart_types/cardano_dart_types.dart';

import 'attestation.dart';
import 'errors.dart';
import 'signing_engine.dart';
import 'uri_parser.dart';

/// Pluggable strategy for decoding the encrypted `payload` of a signTx request
/// into its `tx` / `partialSign` / `vkeyHints` JSON fields.
abstract class SignTxPayloadDecoder {
  Map<String, dynamic> decode({
    required Uint8List payload,
    required Uint8List walletNonce,
    required Uint8List dappKey,
  });

  Set<String> get witnessAddresses;

  factory SignTxPayloadDecoder.plaintextJson({
    required Set<String> witnessAddresses,
  }) =>
      _PlaintextJsonDecoder(witnessAddresses);
}

class _PlaintextJsonDecoder implements SignTxPayloadDecoder {
  _PlaintextJsonDecoder(this._witnessAddresses);

  final Set<String> _witnessAddresses;

  @override
  Set<String> get witnessAddresses => _witnessAddresses;

  @override
  Map<String, dynamic> decode({
    required Uint8List payload,
    required Uint8List walletNonce,
    required Uint8List dappKey,
  }) {
    try {
      return jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    } catch (e) {
      throw Cip186Exception(
        Cip186ErrorCode.decryptFailed,
        'plaintext-JSON payload decode failed: $e',
      );
    }
  }
}

/// Outcome of routing a single deep-link URL.
class DeepLinkOutcome {
  DeepLinkOutcome.success({required this.responseUri, required this.signResult})
      : errorCode = null,
        errorMessage = null;

  DeepLinkOutcome.failure({
    required this.responseUri,
    required this.errorCode,
    required this.errorMessage,
  }) : signResult = null;

  final Uri? responseUri;
  final Cip186SignResult? signResult;
  final Cip186ErrorCode? errorCode;
  final String? errorMessage;
}

/// Top-level orchestrator: parses the deep-link URL, validates redirect host,
/// dispatches to the signer for signTx, and constructs the callback URL.
class Cip186DeepLinkService {
  Cip186DeepLinkService({
    required CardanoWallet wallet,
    required this.walletId,
    required this.walletScheme,
  }) : _engine = Cip186SigningEngine(wallet: wallet);

  final String walletId;
  final String walletScheme;
  final Cip186SigningEngine _engine;

  Future<DeepLinkOutcome> handle({
    required Uri url,
    required SignTxPayloadDecoder signTxSemantics,
  }) async {
    final Cip186Request request;
    try {
      request = Cip186UriParser.parse(
        url,
        expectedWalletId: walletId,
        expectedScheme: walletScheme,
      );
    } on Cip186Exception catch (e) {
      return DeepLinkOutcome.failure(
        responseUri: _maybeBuildErrorRedirect(url, e),
        errorCode: e.code,
        errorMessage: e.message,
      );
    }

    if (request.redirectUri == null) {
      return DeepLinkOutcome.failure(
        responseUri: null,
        errorCode: Cip186ErrorCode.redirectHostMismatch,
        errorMessage: '"redirect" parameter missing',
      );
    }

    switch (request.method) {
      case Cip186Method.signTx:
        return _handleSignTx(request, signTxSemantics);
      case Cip186Method.connect:
      case Cip186Method.disconnect:
      case Cip186Method.signData:
      case Cip186Method.getUsedAddresses:
      case Cip186Method.getUnusedAddresses:
      case Cip186Method.getRewardAddresses:
      case Cip186Method.getNetworkId:
      case Cip186Method.submitTx:
        // TODO(cip186): implement non-signTx methods. Spec §Methods.
        return DeepLinkOutcome.failure(
          responseUri: AttestationBuilder.buildRejected(
            redirect: request.redirectUri!,
            code: Cip186ErrorCode.unsupportedVersion,
            message: 'method ${request.method.wireName} not yet implemented',
          ),
          errorCode: Cip186ErrorCode.unsupportedVersion,
          errorMessage: 'method ${request.method.wireName} not yet implemented',
        );
    }
  }

  Future<DeepLinkOutcome> _handleSignTx(
    Cip186Request request,
    SignTxPayloadDecoder decoder,
  ) async {
    if (request.payloadBytes == null ||
        request.commitBytes == null ||
        request.nonceBytes == null ||
        request.dappKeyBytes == null) {
      return DeepLinkOutcome.failure(
        responseUri: AttestationBuilder.buildRejected(
          redirect: request.redirectUri!,
          code: Cip186ErrorCode.unsupportedVersion,
          message: 'signTx is missing required encrypted-envelope fields',
        ),
        errorCode: Cip186ErrorCode.unsupportedVersion,
        errorMessage: 'signTx missing encrypted-envelope fields',
      );
    }

    final Map<String, dynamic> payload;
    try {
      payload = decoder.decode(
        payload: request.payloadBytes!,
        walletNonce: request.nonceBytes!,
        dappKey: request.dappKeyBytes!,
      );
    } on Cip186Exception catch (e) {
      return DeepLinkOutcome.failure(
        responseUri: AttestationBuilder.buildRejected(
          redirect: request.redirectUri!,
          code: e.code,
          message: e.message,
        ),
        errorCode: e.code,
        errorMessage: e.message,
      );
    }

    final txHex = payload['tx'] as String?;
    if (txHex == null) {
      return DeepLinkOutcome.failure(
        responseUri: AttestationBuilder.buildRejected(
          redirect: request.redirectUri!,
          code: Cip186ErrorCode.unsupportedVersion,
          message: 'payload.tx missing',
        ),
        errorCode: Cip186ErrorCode.unsupportedVersion,
        errorMessage: 'payload.tx missing',
      );
    }

    try {
      final result = await _engine.signTxBody(
        transactionHex: txHex,
        expectedCommit: request.commitBytes!,
        witnessAddresses: decoder.witnessAddresses,
      );

      // Approved response: plaintext placeholder for ciphertext until the
      // platform channel wires NaCl-box encryption (spec §Encryption).
      // The witness-set CBOR is the payload bytes the dApp consumes.
      final walletNonce = Uint8List(24);
      final signature = Uint8List(64);

      return DeepLinkOutcome.success(
        responseUri: AttestationBuilder.buildApproved(
          redirect: request.redirectUri!,
          walletNonce: walletNonce,
          ciphertext: result.witnessSetCbor,
          signature: signature,
        ),
        signResult: result,
      );
    } on Cip186Exception catch (e) {
      return DeepLinkOutcome.failure(
        responseUri: AttestationBuilder.buildRejected(
          redirect: request.redirectUri!,
          code: e.code,
          message: e.message,
        ),
        errorCode: e.code,
        errorMessage: e.message,
      );
    }
  }

  static Uri? _maybeBuildErrorRedirect(Uri original, Cip186Exception e) {
    final raw = original.queryParameters['redirect'];
    if (raw == null) return null;
    final Uri target;
    try {
      target = Uri.parse(raw);
    } catch (_) {
      return null;
    }
    return AttestationBuilder.buildRejected(
      redirect: target,
      code: e.code,
      message: e.message,
    );
  }
}
