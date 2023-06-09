import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:version/version.dart';

import 'test_utils/no_op_services.dart';

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

bool wrappedDecryptSucceeds(
    {required String cipherText,
    required String aesKey,
    required String? ivBase64,
    required String clearText}) {
  try {
    var deciphered =
        EncryptionUtil.decryptValue(cipherText, aesKey, ivBase64: ivBase64);
    if (deciphered != clearText) {
      return false;
    } else {
      return true;
    }
  } catch (e) {
    return false;
  }
}

void main() {
  group('Test with full client stack except mockRemoteSecondary', () {
    final fullStackPrefs = AtClientPreference()
      ..namespace = 'full_stack_tests'
      ..useAtChops = true
      ..isLocalStoreRequired = true
      ..hiveStoragePath = 'full_stack_tests/put/hive'
      ..commitLogPath = 'full_stack_tests/put/commitLog';

    late AtClient atClient;

    var clearText = 'Some clear text';

    RSAKeypair alicesRSAKeyPair = RSAKeypair.fromRandom();
    RSAKeypair bobsRSAKeyPair = RSAKeypair.fromRandom();

    AtEncryptionKeyPair atEncryptionKeyPair = AtEncryptionKeyPair.create(
        alicesRSAKeyPair.publicKey.toString(),
        alicesRSAKeyPair.privateKey.toString());

    var selfEncryptionKey = EncryptionUtil.generateAESKey();

    var bobSharedKey = EncryptionUtil.generateAESKey();
    var myEncryptedBobSharedKey = EncryptionUtil.encryptKey(
        bobSharedKey, alicesRSAKeyPair.publicKey.toString());
    var llookupMySharedKeyForBob = LLookupVerbBuilder()
      ..atKey = '$AT_ENCRYPTION_SHARED_KEY.bob'
      ..sharedBy = '@alice';

    registerFallbackValue(llookupMySharedKeyForBob);

    setUpAll(() async {
      MockRemoteSecondary mockRemoteSecondary = MockRemoteSecondary();
      MockSecondaryAddressFinder mockSecondaryAddressFinder =
          MockSecondaryAddressFinder();
      AtClientManager.getInstance().secondaryAddressFinder =
          mockSecondaryAddressFinder;
      when(() => mockSecondaryAddressFinder.findSecondary('@bob'))
          .thenAnswer((invocation) async => SecondaryAddress('testing', 12));
      AtChops atChops =
          AtChopsImpl(AtChopsKeys.create(atEncryptionKeyPair, null));
      atClient = await AtClientImpl.create('@alice', 'gary', fullStackPrefs,
          remoteSecondary: mockRemoteSecondary, atChops: atChops);
      atClient.syncService = NoOpSyncService();

      // Create our symmetric 'self' encryption key
      await atClient
          .getLocalSecondary()!
          .putValue(AT_ENCRYPTION_SELF_KEY, selfEncryptionKey);

      // Create our symmetric encryption key for sharing with @bob
      await atClient
          .getLocalSecondary()!
          .putValue('shared_key.bob@alice', myEncryptedBobSharedKey);

      when(() => mockRemoteSecondary.executeVerb(
          any(that: isA<LLookupVerbBuilder>()))).thenAnswer((invocation) async {
        var builder = invocation.positionalArguments[0];
        print('LLookupVerbBuilder : ${builder.buildCommand()}');
        return myEncryptedBobSharedKey;
      });
      when(() => mockRemoteSecondary.executeVerb(
          any(that: isA<PLookupVerbBuilder>()))).thenAnswer((invocation) async {
        var builder = invocation.positionalArguments[0];
        print('PLookupVerbBuilder : ${builder.buildCommand()}');
        return bobsRSAKeyPair.publicKey.toString();
      });
      when(() => mockRemoteSecondary.executeVerb(
          any(that: isA<UpdateVerbBuilder>()),
          sync: true)).thenAnswer((invocation) async {
        var builder = invocation.positionalArguments[0];
        print('UpdateVerbBuilder : ${builder.buildCommand()}');
        return 'data:10';
      });
    });

    group('Test encryption for self', () {
      test('Test put self, then get, no IV, 1.5 to 1.5', () async {
        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);

        var atKey = AtKey.self('test_put').build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata?.ivNonce, isNull);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
        expect(EncryptionUtil.decryptValue(cipherText, selfEncryptionKey),
            clearText);

        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });

      test('Test put self, then get, no IV, 1.5 to 2.0', () async {
        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);

        var atKey = AtKey.self('test_put').build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata?.ivNonce, isNull);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
        expect(EncryptionUtil.decryptValue(cipherText, selfEncryptionKey),
            clearText);

        fullStackPrefs.atProtocolEmitted = Version(2, 0, 0);
        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });

      test('Test put self, then get, with IV, 2.0 to 2.0', () async {
        fullStackPrefs.atProtocolEmitted = Version(2, 0, 0);

        var atKey = AtKey.self('test_put').build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata?.ivNonce, isNotNull);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
        expect(
            wrappedDecryptSucceeds(
                cipherText: cipherText,
                aesKey: selfEncryptionKey,
                ivBase64: null,
                clearText: clearText),
            false);
        expect(
            EncryptionUtil.decryptValue(cipherText, selfEncryptionKey,
                ivBase64: atKey.metadata?.ivNonce),
            clearText);

        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });

      test('Test put self, then get, with IV, 2.0 to 1.5', () async {
        fullStackPrefs.atProtocolEmitted = Version(2, 0, 0);

        var atKey = AtKey.self('test_put').build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata?.ivNonce, isNotNull);

        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
        expect(
            wrappedDecryptSucceeds(
                cipherText: cipherText,
                aesKey: selfEncryptionKey,
                ivBase64: null,
                clearText: clearText),
            false);
        expect(
            EncryptionUtil.decryptValue(cipherText, selfEncryptionKey,
                ivBase64: atKey.metadata?.ivNonce),
            clearText);

        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });
    });

    group('Test encryption for sharing', () {
      test('Test put shared, then get, no IV, 1.5 to 1.5', () async {
        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);

        var atKey = (AtKey.shared('test_put')..sharedWith('@bob')).build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata?.ivNonce, isNull);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
        expect(
            EncryptionUtil.decryptValue(cipherText, bobSharedKey), clearText);

        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });

      test('Test put shared, then get, no IV, 1.5 to 2.0', () async {
        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);

        var atKey = (AtKey.shared('test_put')..sharedWith('@bob')).build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata?.ivNonce, isNull);

        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);
        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
        expect(
            EncryptionUtil.decryptValue(cipherText, bobSharedKey), clearText);

        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });

      test('Test put shared, then get, with IV, 2.0 to 2.0', () async {
        fullStackPrefs.atProtocolEmitted = Version(2, 0, 0);

        var atKey = (AtKey.shared('test_put')..sharedWith('@bob')).build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata?.ivNonce, isNotNull);

        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
        expect(
            wrappedDecryptSucceeds(
                cipherText: cipherText,
                aesKey: selfEncryptionKey,
                ivBase64: null,
                clearText: clearText),
            false);
        expect(
            wrappedDecryptSucceeds(
                cipherText: cipherText,
                aesKey: selfEncryptionKey,
                ivBase64: atKey.metadata?.ivNonce,
                clearText: clearText),
            false);
        expect(
            wrappedDecryptSucceeds(
                cipherText: cipherText,
                aesKey: bobSharedKey,
                ivBase64: null,
                clearText: clearText),
            false);
        expect(
            EncryptionUtil.decryptValue(cipherText, bobSharedKey,
                ivBase64: atKey.metadata?.ivNonce),
            clearText);

        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });

      test('Test put shared, then get, with IV, 2.0 to 1.5', () async {
        fullStackPrefs.atProtocolEmitted = Version(2, 0, 0);

        var atKey = (AtKey.shared('test_put')..sharedWith('@bob')).build();
        await atClient.put(atKey, clearText);
        expect(atKey.metadata?.ivNonce, isNotNull);

        fullStackPrefs.atProtocolEmitted = Version(1, 5, 0);
        var atData = await (atClient
            .getLocalSecondary()!
            .keyStore!
            .get(atKey.toString()));
        var cipherText = atData.data;
        expect(
            wrappedDecryptSucceeds(
                cipherText: cipherText,
                aesKey: selfEncryptionKey,
                ivBase64: null,
                clearText: clearText),
            false);
        expect(
            wrappedDecryptSucceeds(
                cipherText: cipherText,
                aesKey: selfEncryptionKey,
                ivBase64: atKey.metadata?.ivNonce,
                clearText: clearText),
            false);
        expect(
            wrappedDecryptSucceeds(
                cipherText: cipherText,
                aesKey: bobSharedKey,
                ivBase64: null,
                clearText: clearText),
            false);
        expect(
            EncryptionUtil.decryptValue(cipherText, bobSharedKey,
                ivBase64: atKey.metadata?.ivNonce),
            clearText);

        var getResult = await atClient.get(atKey);
        expect(getResult.value, clearText);
      });
    });
  });
}
