import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import 'package:island/core/api/auth_api.dart';

/// Runs the platform WebAuthn ceremony and returns the assertion to post back.
typedef PasskeyCeremony =
    Future<LkmPasskeyAssertion> Function(LkmPasskeyOptions options);

/// The ceremony is a platform call (Touch ID / Windows Hello / security key),
/// so it is injected rather than called inline: tests replace it with a canned
/// assertion instead of depending on a real authenticator.
final passkeyCeremonyProvider = Provider<PasskeyCeremony>(
  (ref) => runPasskeyCeremony,
);

/// Same plugin the Solian login uses, so both backends go through one
/// implementation of the ceremony.
Future<LkmPasskeyAssertion> runPasskeyCeremony(LkmPasskeyOptions options) async {
  final authenticator = PasskeyAuthenticator(debugMode: kDebugMode);
  final request = AuthenticateRequestType(
    challenge: options.challenge,
    relyingPartyId: options.rpId,
    allowCredentials: options.allowCredentials
        .map(
          (entry) => CredentialType(
            type: '${entry['type'] ?? 'public-key'}',
            id: '${entry['id'] ?? ''}',
            transports:
                (entry['transports'] as List?)
                    ?.map((t) => '$t')
                    .toList(growable: false) ??
                const <String>[],
          ),
        )
        .toList(growable: false),
    userVerification: 'preferred',
    mediation: MediationType.Optional,
    preferImmediatelyAvailableCredentials: false,
  );

  final credential = await authenticator.authenticate(request);
  return LkmPasskeyAssertion(
    rawId: credential.id,
    clientDataJson: credential.clientDataJSON,
    authenticatorData: credential.authenticatorData,
    signature: credential.signature,
    userHandle: credential.userHandle.isEmpty ? null : credential.userHandle,
  );
}
